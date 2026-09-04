import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'anilist_service.dart';
import '../models/pulse_card.dart';

class PulseService {
  PulseService._();
  static final instance = PulseService._();

  static const _apiUrl = 'https://graphql.anilist.co';
  static const _cacheTtl = Duration(hours: 2);

  static final Map<String, List<PulseCard>> _memCache = {};
  static final Map<String, DateTime> _cacheTs = {};

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<Map<String, dynamic>?> _query(Map<String, dynamic> body) async {
    await AnilistService.throttle();
    try {
      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Hanj/1.0',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 429) {
        final retryAfter =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 10;
        AnilistService.backoff(retryAfter);
        return null;
      }
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<List<Map<String, dynamic>>> _getUserList() async {
    if (_uid == null) return [];
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('animeList')
          .get();
      return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (_) {
      return [];
    }
  }

  static const String _batchQuery = r'''
  query ($ids: [Int], $perPage: Int) {
    Page(page: 1, perPage: $perPage) {
      media(id_in: $ids, type: ANIME) {
        id
        title { romaji english }
        coverImage { large }
        status
        season
        seasonYear
        format
        genres
        trailer { id site }
        nextAiringEpisode { airingAt episode }
        relations {
          edges {
            relationType
            node {
              id
              title { romaji english }
              coverImage { large }
              status
              format
              seasonYear
            }
          }
        }
      }
    }
  }
  ''';

  Future<List<Map<String, dynamic>>> _fetchByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < ids.length; i += 50) {
      final chunk = ids.sublist(i, (i + 50).clamp(0, ids.length));
      final data = await _query({
        'query': _batchQuery,
        'variables': {'ids': chunk, 'perPage': chunk.length},
      });
      if (data != null) {
        final media = data['data']?['Page']?['media'] as List? ?? [];
        results.addAll(media.cast<Map<String, dynamic>>());
      }
    }
    return results;
  }

  static const String _statusQuery = r'''
  query ($status: MediaStatus, $genre: String, $perPage: Int, $sort: [MediaSort]) {
    Page(page: 1, perPage: $perPage) {
      media(
        type: ANIME,
        status: $status,
        genre: $genre,
        sort: $sort,
        isAdult: false
      ) {
        id
        title { romaji english }
        coverImage { large }
        status
        season
        seasonYear
        format
        genres
        trailer { id site }
        nextAiringEpisode { airingAt episode }
      }
    }
  }
  ''';

  Future<List<Map<String, dynamic>>> _fetchByStatus(
    String status, {
    String? genre,
    int perPage = 20,
    String sort = 'POPULARITY_DESC',
  }) async {
    final data = await _query({
      'query': _statusQuery,
      'variables': {
        'status': status,
        if (genre != null) 'genre': genre,
        'perPage': perPage,
        'sort': [sort],
      },
    });
    if (data == null) return [];
    return (data['data']?['Page']?['media'] as List? ?? [])
        .cast<Map<String, dynamic>>();
  }

  String? _trailerUrl(Map<String, dynamic>? trailer) {
    if (trailer == null) return null;
    final id = trailer['id'] as String?;
    final site = trailer['site'] as String?;
    if (id == null || id.isEmpty) return null;
    if (site == 'youtube') return 'https://www.youtube.com/watch?v=$id';
    return null;
  }

  String _displayTitle(Map<String, dynamic> item) =>
      (item['title']?['english'] as String?)?.isNotEmpty == true
          ? item['title']['english'] as String
          : (item['title']?['romaji'] as String? ?? 'Unknown');

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0]}${s.substring(1).toLowerCase()}';

  bool _isFresh(String key) {
    final ts = _cacheTs[key];
    if (ts == null) return false;
    return DateTime.now().difference(ts) < _cacheTtl;
  }

  List<PulseCard>? _fromCache(String key) =>
      _isFresh(key) ? _memCache[key] : null;

  void _toCache(String key, List<PulseCard> cards) {
    _memCache[key] = cards;
    _cacheTs[key] = DateTime.now();
  }

  void invalidate() {
    _memCache.clear();
    _cacheTs.clear();
  }

  // ── For You ────────────────────────────────────────────────
  // Trailers are deliberately excluded here — they have their
  // own dedicated Trailers tab. For You focuses on airing-soon
  // alerts, sequel/new-season announcements, and genre-based
  // upcoming picks.
  Future<List<PulseCard>> getForYou({bool forceRefresh = false}) async {
    const key = 'for_you';
    if (!forceRefresh) {
      final cached = _fromCache(key);
      if (cached != null) return cached;
    }

    final cards = <PulseCard>[];
    final seen = <String>{};
    void add(PulseCard c) {
      if (seen.add(c.id)) cards.add(c);
    }

    final userList = await _getUserList();
    if (userList.isEmpty) {
      _toCache(key, []);
      return [];
    }

    final watchingIds = <int>[];
    final planIds = <int>[];
    final genreCounts = <String, int>{};

    for (final item in userList) {
      final id = int.tryParse(item['id'] as String? ?? '');
      if (id == null) continue;
      switch (item['status'] as String? ?? '') {
        case 'WATCHING':
          watchingIds.add(id);
          break;
        case 'PLAN_TO_WATCH':
          planIds.add(id);
          break;
      }
      for (final g
          in (item['genres'] as List<dynamic>?)?.cast<String>() ?? <String>[]) {
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
      }
    }

    // Also count genres from completed titles for sequel detection
    for (final item in userList) {
      if (item['status'] != 'COMPLETED') continue;
      for (final g
          in (item['genres'] as List<dynamic>?)?.cast<String>() ?? <String>[]) {
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
      }
    }

    final now = DateTime.now();

    // ── Batch-fetch watching + plan ────────────────────────
    final priorityIds = [...watchingIds, ...planIds].take(40).toList();
    if (priorityIds.isNotEmpty) {
      final media = await _fetchByIds(priorityIds);
      for (final item in media) {
        final animeId = item['id'].toString();
        final title = _displayTitle(item);
        final image = item['coverImage']?['large'] as String?;
        final isWatching = watchingIds.contains(item['id'] as int);
        final reason =
            isWatching ? 'On your Watching list' : 'On your Plan to Watch list';

        // ── Airing-soon card (next episode within 7 days) ──
        final next = item['nextAiringEpisode'] as Map<String, dynamic>?;
        if (next != null) {
          final airingAt = next['airingAt'] as int?;
          final episode = next['episode'] as int?;
          if (airingAt != null && episode != null) {
            final airingDate =
                DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
            final daysUntil = airingDate.difference(now).inDays;
            if (daysUntil >= 0 && daysUntil <= 7) {
              final label = daysUntil == 0
                  ? 'today'
                  : daysUntil == 1
                      ? 'tomorrow'
                      : 'in $daysUntil days';
              add(PulseCard(
                id: PulseCard.makeId(
                    PulseCardType.airingSoon, animeId, 'ep$episode'),
                type: PulseCardType.airingSoon,
                animeId: animeId,
                title: title,
                imageUrl: image,
                headline: 'Episode $episode airs $label',
                reason: reason,
                timestamp: now,
                payload: {'airingAt': airingAt, 'episode': episode},
              ));
            }
          }
        }

        // ── Sequel / new season announced ──────────────────
        final edges = item['relations']?['edges'] as List? ?? [];
        for (final edge in edges) {
          final relType = edge['relationType'] as String?;
          if (relType != 'SEQUEL' && relType != 'SIDE_STORY') continue;
          final node = edge['node'] as Map<String, dynamic>;
          final nodeStatus = node['status'] as String?;
          if (nodeStatus != 'NOT_YET_RELEASED' && nodeStatus != 'RELEASING') {
            continue;
          }
          final seqId = node['id'].toString();
          final seqTitle = _displayTitle(node);
          final seqImage = node['coverImage']?['large'] as String?;
          final seqHeadline = nodeStatus == 'RELEASING'
              ? '$seqTitle is now airing'
              : '$seqTitle announced';
          add(PulseCard(
            id: PulseCard.makeId(PulseCardType.newSeason, seqId),
            type: PulseCardType.newSeason,
            animeId: seqId,
            title: seqTitle,
            imageUrl: seqImage,
            headline: seqHeadline,
            reason: 'Because you tracked $title',
            timestamp: now,
            payload: {'parentTitle': title, 'relationType': relType},
          ));
        }
      }
    }

    // ── Upcoming in top 3 genres ───────────────────────────
    final topGenres = (genreCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .map((e) => e.key)
        .toList();

    for (final genre in topGenres) {
      final media = await _fetchByStatus(
        'NOT_YET_RELEASED',
        genre: genre,
        perPage: 5,
        sort: 'POPULARITY_DESC',
      );
      for (final item in media) {
        final animeId = item['id'].toString();
        final title = _displayTitle(item);
        add(PulseCard(
          id: PulseCard.makeId(PulseCardType.upcoming, animeId, 'g_$genre'),
          type: PulseCardType.upcoming,
          animeId: animeId,
          title: title,
          imageUrl: item['coverImage']?['large'] as String?,
          headline: 'Coming soon',
          reason: 'Because you follow $genre',
          timestamp: now,
          payload: {'genre': genre},
        ));
      }
    }

    const typeOrder = [
      PulseCardType.airingSoon,
      PulseCardType.newSeason,
      PulseCardType.upcoming,
      PulseCardType.nowAiring,
      PulseCardType.trailer,
    ];
    cards.sort(
        (a, b) => typeOrder.indexOf(a.type).compareTo(typeOrder.indexOf(b.type)));

    _toCache(key, cards);
    return cards;
  }

  // ── Trailers ───────────────────────────────────────────────
  Future<List<PulseCard>> getTrailers({bool forceRefresh = false}) async {
    const key = 'trailers';
    if (!forceRefresh) {
      final cached = _fromCache(key);
      if (cached != null) return cached;
    }

    final now = DateTime.now();
    final seen = <String>{};
    final cards = <PulseCard>[];

    final releasing =
        await _fetchByStatus('RELEASING', perPage: 30, sort: 'TRENDING_DESC');
    final upcoming = await _fetchByStatus('NOT_YET_RELEASED',
        perPage: 25, sort: 'POPULARITY_DESC');

    for (final item in [...releasing, ...upcoming]) {
      final animeId = item['id'].toString();
      if (!seen.add(animeId)) continue;
      final trailerUrl =
          _trailerUrl(item['trailer'] as Map<String, dynamic>?);
      if (trailerUrl == null) continue;
      final title = _displayTitle(item);
      cards.add(PulseCard(
        id: PulseCard.makeId(PulseCardType.trailer, animeId),
        type: PulseCardType.trailer,
        animeId: animeId,
        title: title,
        imageUrl: item['coverImage']?['large'] as String?,
        headline: 'Watch the trailer',
        timestamp: now,
        payload: {'trailerUrl': trailerUrl},
      ));
    }

    _toCache(key, cards);
    return cards;
  }

  // ── Airing ─────────────────────────────────────────────────
  Future<List<PulseCard>> getAiring({bool forceRefresh = false}) async {
    const key = 'airing';
    if (!forceRefresh) {
      final cached = _fromCache(key);
      if (cached != null) return cached;
    }

    final now = DateTime.now();
    final media =
        await _fetchByStatus('RELEASING', perPage: 30, sort: 'TRENDING_DESC');

    final cards = media.map((item) {
      final animeId = item['id'].toString();
      final title = _displayTitle(item);
      final next = item['nextAiringEpisode'] as Map<String, dynamic>?;

      String headline = 'Currently airing';
      Map<String, dynamic> payload = {};

      if (next != null) {
        final airingAt = next['airingAt'] as int?;
        final episode = next['episode'] as int?;
        payload = {'airingAt': airingAt, 'episode': episode};
        if (airingAt != null && episode != null) {
          final airingDate =
              DateTime.fromMillisecondsSinceEpoch(airingAt * 1000);
          final daysUntil = airingDate.difference(now).inDays;
          headline = daysUntil == 0
              ? 'Ep $episode airs today'
              : daysUntil == 1
                  ? 'Ep $episode airs tomorrow'
                  : 'Ep $episode in $daysUntil days';
        }
      }

      return PulseCard(
        id: PulseCard.makeId(PulseCardType.nowAiring, animeId),
        type: PulseCardType.nowAiring,
        animeId: animeId,
        title: title,
        imageUrl: item['coverImage']?['large'] as String?,
        headline: headline,
        timestamp: now,
        payload: payload,
      );
    }).toList();

    _toCache(key, cards);
    return cards;
  }

  // ── Upcoming ───────────────────────────────────────────────
  Future<List<PulseCard>> getUpcoming({bool forceRefresh = false}) async {
    const key = 'upcoming';
    if (!forceRefresh) {
      final cached = _fromCache(key);
      if (cached != null) return cached;
    }

    final now = DateTime.now();
    final media = await _fetchByStatus('NOT_YET_RELEASED',
        perPage: 25, sort: 'POPULARITY_DESC');

    final cards = media.map((item) {
      final animeId = item['id'].toString();
      final title = _displayTitle(item);
      final season = item['season'] as String?;
      final year = item['seasonYear'] as int?;
      final headline = (season != null && year != null)
          ? '${_capitalize(season)} $year'
          : 'Coming soon';

      return PulseCard(
        id: PulseCard.makeId(PulseCardType.upcoming, animeId),
        type: PulseCardType.upcoming,
        animeId: animeId,
        title: title,
        imageUrl: item['coverImage']?['large'] as String?,
        headline: headline,
        timestamp: now,
        payload: {
          if (season != null) 'season': season,
          if (year != null) 'year': year,
        },
      );
    }).toList();

    _toCache(key, cards);
    return cards;
  }
}
