// Tier lists: the three AniList questions the character picker asks.
//
//  - anime by title (to open one's cast);
//  - one anime's characters, 50 a page, main cast first;
//  - characters by name, across every anime.
//
// Every request goes through AnilistService's shared queue the way
// PulseService._query does: throttle() first, then noteStatus, noteLimits,
// and backoff() on a 429, with a 15 s timeout. Answers are kept in memory
// (static, so they survive leaving the screen) and a stale one is still
// shown when AniList can't answer, so a rate limit doesn't blank the picker.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../services/anilist_service.dart';
import 'tier_list_model.dart';

/// An anime in the picker's search results.
class TierAnime {
  const TierAnime({
    required this.id,
    required this.title,
    this.cover,
    this.color,
    this.year,
    this.format,
  });

  final int id;
  final String title;
  final String? cover;

  /// `coverImage.color` as 0xFFRRGGBB.
  final int? color;
  final int? year;
  final String? format;

  static TierAnime? fromJson(Object? m) {
    if (m is! Map || m['id'] is! int) return null;
    final t = m['title'];
    final title = (t is Map ? (t['english'] ?? t['romaji']) : null) as String?;
    final c = m['coverImage'];
    return TierAnime(
      id: m['id'] as int,
      title: title ?? 'Untitled',
      cover: c is Map ? (c['large'] ?? c['medium']) as String? : null,
      color: c is Map ? TierCharacter.parseHexColor(c['color'] as String?) : null,
      year: m['seasonYear'] as int?,
      format: m['format'] as String?,
    );
  }
}

/// A character the picker can offer, with their role in that anime.
class TierPick {
  const TierPick(this.character, {this.role});
  final TierCharacter character;

  /// MAIN, SUPPORTING or BACKGROUND, when picked from an anime's cast.
  final String? role;
}

/// One page of an anime's cast.
class TierCastPage {
  const TierCastPage({required this.anime, required this.picks, required this.hasNextPage});
  final TierAnime anime;
  final List<TierPick> picks;
  final bool hasNextPage;
}

/// What a fetch came back with: a value (perhaps a stale one), and the
/// status of the request behind it when that request failed.
class TierFetch<T> {
  const TierFetch(this.value, {this.failStatus, this.stale = false});
  final T? value;

  /// 0 for no response, else the HTTP status; null when AniList answered.
  final int? failStatus;

  /// True when [value] is an older answer shown because the new one failed.
  final bool stale;
}

class _Answer {
  const _Answer(this.status, [this.data]);
  final int status;
  final Map<String, dynamic>? data;
}

class _Kept {
  _Kept(this.value) : at = DateTime.now();
  final Object value;
  final DateTime at;
}

class TierListAnilist {
  TierListAnilist._();
  static final instance = TierListAnilist._();

  static const _apiUrl = 'https://graphql.anilist.co';
  static const _searchTtl = Duration(minutes: 30);
  static const _castTtl = Duration(hours: 6);
  static const _keep = 80;

  // Insertion-ordered, so the oldest answer is the first to go.
  static final Map<String, _Kept> _kept = {};
  static final Map<String, Future<TierFetch<Object>>> _inFlight = {};

  static const String _animeQuery = r'''
  query ($search: String) {
    Page(page: 1, perPage: 12) {
      media(search: $search, type: ANIME, isAdult: false, sort: [SEARCH_MATCH]) {
        id
        title { romaji english }
        coverImage { large color }
        seasonYear
        format
      }
    }
  }
  ''';

  static const String _castQuery = r'''
  query ($id: Int, $page: Int) {
    Media(id: $id, type: ANIME) {
      id
      isAdult
      title { romaji english }
      coverImage { large color }
      seasonYear
      format
      characters(sort: [ROLE, RELEVANCE, ID], page: $page, perPage: 50) {
        pageInfo { hasNextPage }
        edges {
          role
          node { id name { full } image { large } }
        }
      }
    }
  }
  ''';

  static const String _characterQuery = r'''
  query ($search: String) {
    Page(page: 1, perPage: 20) {
      characters(search: $search, sort: [SEARCH_MATCH]) {
        id
        name { full }
        image { large }
        media(type: ANIME, sort: [POPULARITY_DESC], perPage: 1) {
          nodes { id isAdult title { romaji english } coverImage { large color } }
        }
      }
    }
  }
  ''';

  /// Anime whose title matches [search].
  Future<TierFetch<List<TierAnime>>> searchAnime(String search,
      {bool Function()? stillWanted}) async {
    final q = _norm(search);
    final r = await _cached('a:$q', _searchTtl, stillWanted, () {
      return _query({'query': _animeQuery, 'variables': {'search': q}}, stillWanted);
    }, (data) {
      final media = (data['Page']?['media'] as List?) ?? const [];
      return <TierAnime>[
        for (final m in media)
          if (TierAnime.fromJson(m) case final TierAnime a) a,
      ];
    });
    return _as<List<TierAnime>>(r);
  }

  /// Page [page] of [mediaId]'s cast, main characters first.
  Future<TierFetch<TierCastPage>> cast(int mediaId, {int page = 1}) async {
    final r = await _cached('c:$mediaId:$page', _castTtl, null, () {
      return _query({'query': _castQuery, 'variables': {'id': mediaId, 'page': page}}, null);
    }, (data) {
      final m = data['Media'];
      final anime = TierAnime.fromJson(m);
      if (anime == null || m['isAdult'] == true) {
        return const TierCastPage(
            anime: TierAnime(id: 0, title: ''), picks: [], hasNextPage: false);
      }
      final chars = m['characters'];
      final edges = (chars is Map ? chars['edges'] as List? : null) ?? const [];
      final picks = <TierPick>[];
      for (final e in edges) {
        if (e is! Map) continue;
        final n = e['node'];
        if (n is! Map || n['id'] is! int) continue;
        picks.add(TierPick(
          TierCharacter(
            id: n['id'] as int,
            name: (n['name']?['full'] as String?) ?? 'Unknown',
            imageUrl: n['image']?['large'] as String?,
            mediaId: anime.id,
            mediaTitle: anime.title,
            mediaCover: anime.cover,
            mediaColor: anime.color,
          ),
          role: e['role'] as String?,
        ));
      }
      // AniList marks every full page as having a next one, even the last;
      // an empty page ends it (see the import fixes' notes).
      final more = chars is Map && chars['pageInfo']?['hasNextPage'] == true && picks.isNotEmpty;
      return TierCastPage(anime: anime, picks: picks, hasNextPage: more);
    });
    return _as<TierCastPage>(r);
  }

  /// Characters whose name matches [search], each with the anime they're
  /// best known from. Characters who appear in no anime, or only in adult
  /// titles, are left out.
  Future<TierFetch<List<TierPick>>> searchCharacters(String search,
      {bool Function()? stillWanted}) async {
    final q = _norm(search);
    final r = await _cached('n:$q', _searchTtl, stillWanted, () {
      return _query({'query': _characterQuery, 'variables': {'search': q}}, stillWanted);
    }, (data) {
      final list = (data['Page']?['characters'] as List?) ?? const [];
      final picks = <TierPick>[];
      for (final n in list) {
        if (n is! Map || n['id'] is! int) continue;
        final nodes = (n['media']?['nodes'] as List?) ?? const [];
        final m = nodes.isEmpty ? null : nodes.first;
        if (m is! Map || m['isAdult'] == true) continue;
        final anime = TierAnime.fromJson(m);
        if (anime == null) continue;
        picks.add(TierPick(TierCharacter(
          id: n['id'] as int,
          name: (n['name']?['full'] as String?) ?? 'Unknown',
          imageUrl: n['image']?['large'] as String?,
          mediaId: anime.id,
          mediaTitle: anime.title,
          mediaCover: anime.cover,
          mediaColor: anime.color,
        )));
      }
      return picks;
    });
    return _as<List<TierPick>>(r);
  }

  static String _norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

  static TierFetch<T> _as<T>(TierFetch<Object> r) =>
      TierFetch<T>(r.value as T?, failStatus: r.failStatus, stale: r.stale);

  /// A fresh kept answer if there is one; else one request (shared with any
  /// identical request already on its way), falling back to a stale kept
  /// answer when it fails.
  Future<TierFetch<Object>> _cached(
    String key,
    Duration ttl,
    bool Function()? stillWanted,
    Future<_Answer> Function() fetch,
    Object Function(Map<String, dynamic> data) parse,
  ) {
    final kept = _kept[key];
    if (kept != null && DateTime.now().difference(kept.at) < ttl) {
      return Future.value(TierFetch<Object>(kept.value));
    }
    final running = _inFlight[key];
    if (running != null) return running;
    final f = () async {
      try {
        final a = await fetch();
        final data = a.data;
        if (data != null) {
          Object? value;
          try {
            value = parse(data);
          } catch (_) {
            value = null;
          }
          if (value != null) {
            _kept.remove(key);
            _kept[key] = _Kept(value);
            while (_kept.length > _keep) {
              _kept.remove(_kept.keys.first);
            }
            return TierFetch<Object>(value);
          }
        }
        // -1: skipped because nobody wants it any more, which is not a
        // failure. A 200 with no usable data is reported as a generic
        // failure (500), so the message names no cause the app can't see.
        final int? fail = a.status < 0 ? null : (a.status == 200 ? 500 : a.status);
        if (kept != null) {
          return TierFetch<Object>(kept.value, failStatus: fail, stale: true);
        }
        return TierFetch<Object>(null, failStatus: fail);
      } finally {
        _inFlight.remove(key);
      }
    }();
    _inFlight[key] = f;
    return f;
  }

  /// PulseService._query's shape. [stillWanted] lets a search that has been
  /// typed past give up its turn without sending anything.
  Future<_Answer> _query(Map<String, dynamic> body, bool Function()? stillWanted) async {
    await AnilistService.throttle();
    if (stillWanted != null && !stillWanted()) return const _Answer(-1);
    final http.Response response;
    try {
      response = await http
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
    } catch (_) {
      AnilistService.noteStatus(0, 'tierlist');
      return const _Answer(0);
    }
    AnilistService.noteStatus(response.statusCode, 'tierlist');
    AnilistService.noteLimits(response.headers);
    if (response.statusCode == 429) {
      final retryAfter = int.tryParse(response.headers['retry-after'] ?? '') ?? 10;
      AnilistService.backoff(retryAfter);
      return const _Answer(429);
    }
    if (response.statusCode != 200) return _Answer(response.statusCode);
    try {
      final j = jsonDecode(response.body);
      if (j is Map<String, dynamic> && j['data'] is Map<String, dynamic>) {
        return _Answer(200, j['data'] as Map<String, dynamic>);
      }
    } catch (_) {}
    return const _Answer(200);
  }
}
