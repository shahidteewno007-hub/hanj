import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime_model.dart';

class AnilistService {
  static const String _apiUrl = 'https://graphql.anilist.co';

  // ── Adaptive reservation-based throttle ─────────────────────
  // The gap between requests follows AniList's own rate-limit headers
  // (see noteLimits below). After a 429 it still backs off to at least
  // a 2s gap (30/min) for a cooldown window, then recovers.
  static DateTime _nextSlotTime = DateTime(2000);
  static DateTime _slowUntil = DateTime(2000);
  static const _fastGap = Duration(milliseconds: 350);
  static const _slowGap = Duration(milliseconds: 2000);
  static const _cooldown = Duration(seconds: 60);

  static Duration get _minGap =>
      DateTime.now().isBefore(_slowUntil) && _slowGap > _paceGap
          ? _slowGap
          : _paceGap;

  // ── Header-driven pacing ────────────────────────────────────
  // Every AniList response carries X-RateLimit-Limit (requests/minute for
  // this IP) and X-RateLimit-Remaining. The gap is 60s ÷ Limit, so Hanj
  // paces to what AniList says rather than to a guess — the old fixed
  // 350ms gap was ~171/min against a published 90/min.
  //
  // Remaining matters as well as Limit: it counts traffic this device
  // can't see, such as another phone on the same Wi-Fi sharing the IP.
  // Once it is down to _paceReserve, the gap stretches to spread what is
  // left over a full minute (60s ÷ (Remaining + 1)), reaching 60s at zero.
  //
  // Until the first response arrives the gap is 2s, AniList's current
  // 30/min limit. _fastGap is now only a floor, so a header claiming a huge
  // limit can't take pacing below 350ms. The 429 / Retry-After path is
  // unchanged and still wins whenever it is slower.
  static Duration _paceGap = _slowGap;
  static const _paceReserve = 3;

  /// One-line opt-in, next to noteStatus: pass every AniList response's
  /// headers. Headers without a usable Limit leave pacing as it was.
  static void noteLimits(Map<String, String> headers) {
    final limit = int.tryParse(headers['x-ratelimit-limit'] ?? '');
    if (limit == null || limit <= 0) return;
    final remaining = int.tryParse(headers['x-ratelimit-remaining'] ?? '');
    var gapMs = (60000 + limit - 1) ~/ limit; // round up: never over Limit
    if (remaining != null && remaining <= _paceReserve) {
      final stretched = 60000 ~/ (remaining < 0 ? 1 : remaining + 1);
      if (stretched > gapMs) gapMs = stretched;
    }
    if (gapMs < _fastGap.inMilliseconds) gapMs = _fastGap.inMilliseconds;
    _paceGap = Duration(milliseconds: gapMs);
  }

  static Future<void> _reserveSlot() async {
    final now  = DateTime.now();
    final gap  = _minGap;
    final wait = _nextSlotTime.difference(now);
    _nextSlotTime = (wait.isNegative ? now : _nextSlotTime).add(gap);
    if (wait > Duration.zero) {
      await Future.delayed(wait);
    }
  }

  /// Public throttle — call before any direct http.post that bypasses
  /// AnilistService so all requests share the same queue.
  static Future<void> throttle() => _reserveSlot();

  /// Back off after a 429. Enters slow mode for the cooldown window
  /// and pushes the shared slot out by [seconds].
  static void backoff(int seconds) {
    _slowUntil = DateTime.now().add(_cooldown);
    final pushTo = DateTime.now().add(Duration(seconds: seconds));
    if (pushTo.isAfter(_nextSlotTime)) _nextSlotTime = pushTo;
  }

  // ── Availability signal ─────────────────────────────────────
  // Same shape as throttle()/backoff() above: static, service-owned,
  // and opted into with one line by the nine call sites that issue
  // their own http.post. It records the last outcome so a surface can
  // tell an upstream failure apart from a query that legitimately came
  // back empty — today those are indistinguishable, which is why an
  // AniList outage reads as "the app fetches nothing".
  //
  // Deliberately does NOT throw. OfflineCacheService:148-150 and
  // discovery_screen.dart:644/:659 all use an empty return to trigger
  // their stale fallback; throwing would bypass those and make the app
  // less useful during exactly the outage this exists for.
  static int? _lastFailStatus;
  static DateTime? _lastOkAt;

  // Listenable view of the same state, for a widget that has to redraw
  // when it changes rather than only when its screen happens to rebuild.
  // Holds lastFailStatus: null while AniList is answering, 0 for no
  // response, otherwise the HTTP status. A ValueNotifier only notifies on
  // an actual change, so a run of identical failures costs nothing.
  static final ValueNotifier<int?> _failStatus = ValueNotifier<int?>(null);
  static ValueListenable<int?> get failStatus => _failStatus;

  /// True when the most recent AniList request failed and none has
  /// succeeded since.
  static bool get isUnavailable => _lastFailStatus != null;

  /// The last non-200 seen, or null if the last request succeeded.
  /// 0 means no response at all: the request threw (no network, DNS
  /// failure, timeout) before AniList could answer.
  static int? get lastFailStatus => _lastFailStatus;

  /// When AniList last answered successfully — for a "saved data" note.
  static DateTime? get lastOkAt => _lastOkAt;

  /// A per-status message, in the shape cadre_roster_service.dart:212-224
  /// already uses. Null while AniList is answering, so a surface can tell
  /// "unavailable" apart from "this query legitimately returned nothing" —
  /// today both render the same empty state.
  ///
  /// Three lines: no response (0), rate limited (429), and one line for
  /// every other status that names no cause and no status code — the app
  /// sees a status, not the reason behind it. The 2026-09 403 read as an
  /// outage and was a suspension.
  static String? get unavailableMessage => messageFor(_lastFailStatus);

  /// The same mapping for a status a surface kept itself — the outcome of
  /// its own last fetch — rather than the app-wide last one above, which
  /// any other screen's request can set or clear in the meantime.
  static String? messageFor(int? code) {
    if (code == null) return null;
    if (code == 0) return 'Can\'t connect right now. Try again shortly.';
    if (code == 429) return 'AniList is rate limiting. Try again shortly.';
    return 'Fresh data can\'t load right now. Try again shortly.';
  }

  /// One-line opt-in for call sites that post directly. [source] only
  /// tags the log line, so a failure can be traced to a surface.
  ///
  /// Statuses: 200 clears the signal; any other HTTP status records an
  /// upstream failure; 0 records "no response" — pass it from a catch
  /// around the request itself, then rethrow, so the caller's existing
  /// stale fallback still runs. Offline, the request throws instead of
  /// returning a status, so without 0 the most common failure of all
  /// would never reach this signal.
  static void noteStatus(int statusCode, String source) {
    if (statusCode == 200) {
      _lastFailStatus = null;
      _lastOkAt = DateTime.now();
      _failStatus.value = null;
      return;
    }
    _lastFailStatus = statusCode;
    _failStatus.value = statusCode;
    debugPrint('AniList HTTP $statusCode ($source)');
  }

  /// POST with throttle + up to 2 retries on 429, respecting Retry-After.
  Future<http.Response> _post(Map<String, dynamic> body) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await _reserveSlot();
      final http.Response response;
      try {
        response = await http.post(
          Uri.parse(_apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'Hanj/1.0',
          },
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 15));
      } catch (_) {
        noteStatus(0, 'service');
        rethrow;
      }

      noteStatus(response.statusCode, 'service');
      noteLimits(response.headers);
      if (response.statusCode != 429) return response;

      // Rate limited — honor Retry-After header, else exponential backoff
      final retryAfter = int.tryParse(
              response.headers['retry-after'] ?? '') ??
          (3 * (attempt + 1)); // 3s, 6s, 9s
      backoff(retryAfter);
      if (attempt == 2) return response; // give up, return the 429
    }
    // Unreachable, but satisfies the analyzer
    throw Exception('AniList request failed');
  }

  Future<List<Anime>> searchAnime(
    String query, {
    String? genre,
    int? year,
    String? format,
    String? season,
    String? sort,
  }) async {
    final hasSearch   = query.isNotEmpty;
    final hasGenre    = genre != null;
    final hasYear     = year != null;
    final hasFormat   = format != null;
    final hasSeason   = season != null;
    final hasYearOnly = hasYear && !hasSeason;

    final paramDefs = [
      if (hasSearch)   r'$search: String',
      r'$sort: [MediaSort]',
      r'$isAdult: Boolean',
      if (hasGenre)    r'$genre: String',
      if (hasSeason)   r'$season: MediaSeason',
      if (hasSeason)   r'$seasonYear: Int',
      if (hasYearOnly) r'$startDate_greater: FuzzyDateInt',
      if (hasYearOnly) r'$startDate_lesser: FuzzyDateInt',
      if (hasFormat)   r'$format: MediaFormat',
    ].join(', ');

    final mediaArgs = [
      if (hasSearch)   r'search: $search',
      r'sort: $sort',
      'type: ANIME',
      r'isAdult: $isAdult',
      if (hasGenre)    r'genre: $genre',
      if (hasSeason)   r'season: $season',
      if (hasSeason)   r'seasonYear: $seasonYear',
      if (hasYearOnly) r'startDate_greater: $startDate_greater',
      if (hasYearOnly) r'startDate_lesser: $startDate_lesser',
      if (hasFormat)   r'format: $format',
    ].join(', ');

    final graphqlQuery = '''
    query ($paramDefs) {
      Page(page: 1, perPage: 20) {
        media($mediaArgs) {
          id
          title { romaji english }
          coverImage { large }
          averageScore
          episodes
          status
          seasonYear
          season
          format
          genres
          description
          trailer { id site }
        }
      }
    }
    ''';

    final variables = <String, dynamic>{
      'sort': [sort ?? 'POPULARITY_DESC'],
      'isAdult': false,
    };
    if (hasSearch)   variables['search']            = query;
    if (hasGenre)    variables['genre']             = genre;
    if (hasSeason)   variables['season']            = season;
    if (hasSeason)   variables['seasonYear']        = year;
    if (hasYearOnly) variables['startDate_greater'] = year! * 10000;
    if (hasYearOnly) variables['startDate_lesser']  = (year + 1) * 10000;
    if (hasFormat)   variables['format']            = format;

    try {
      final response = await _post({'query': graphqlQuery, 'variables': variables});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] == null || data['data']['Page'] == null) {
          print('AniList no data: ${data['errors']}');
          return [];
        }
        final mediaList = data['data']['Page']['media'] as List? ?? [];
        return mediaList.map((item) => Anime(
          id: item['id'].toString(),
          title: item['title']['romaji'] ?? 'Unknown',
          titleEnglish: item['title']['english'],
          imageUrl: item['coverImage']?['large'],
          averageScore: item['averageScore'] != null
              ? (item['averageScore'] as num).toDouble()
              : null,
          episodes: item['episodes'] as int?,
          status: item['status'],
          seasonYear: item['seasonYear'],
          season: item['season'],
          format: item['format'],
          genres: item['genres'] != null
              ? List<String>.from(item['genres'])
              : [],
          description: item['description'],
          trailerUrl: _extractTrailerUrl(item['trailer']),
        )).toList();
      } else {
        print('AniList HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('AniList error: $e');
      return [];
    }
  }

  Future<List<Anime>> searchByStudio(String studioName) async {
    const String graphqlQuery = '''
    query (\$studio: String) {
      Page(page: 1, perPage: 50) {
        studios(search: \$studio) {
          name
          media(sort: SCORE_DESC) {
            nodes {
              id
              title { romaji english }
              coverImage { large }
              averageScore
              episodes
              status
              seasonYear
              season
              format
              genres
              description
            }
          }
        }
      }
    }
    ''';
    try {
      final response = await _post({
        'query': graphqlQuery,
        'variables': {'studio': studioName},
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] == null || data['data']['Page'] == null) return [];
        final studios = data['data']['Page']['studios'] as List? ?? [];
        if (studios.isEmpty) return [];
        final mediaList = studios[0]['media']['nodes'] as List? ?? [];
        return mediaList.map((item) => Anime(
          id: item['id'].toString(),
          title: item['title']['romaji'] ?? 'Unknown',
          titleEnglish: item['title']['english'],
          imageUrl: item['coverImage']?['large'],
          averageScore: item['averageScore'] != null
              ? (item['averageScore'] as num).toDouble()
              : null,
          episodes: item['episodes'] as int?,
          status: item['status'],
          seasonYear: item['seasonYear'],
          season: item['season'],
          format: item['format'],
          genres: item['genres'] != null
              ? List<String>.from(item['genres'])
              : [],
          description: item['description'],
        )).toList();
      }
      return [];
    } catch (e) {
      print('AniList studio error: $e');
      return [];
    }
  }

  /// Detail's one request per open (stage 1c). Besides the studio, staff and
  /// cast, it carries what Detail used to fetch in three more requests: the
  /// sharp cover and the banner (the gallery), the next airing episode (the
  /// countdown) and AniList's recommendations (You May Like). It also asks
  /// for Hanko's print (the native title and the cover's colour), the
  /// episode length, the score distribution and the official links. Each
  /// recommendation carries searchAnime's fields, so tapping one opens a full
  /// entry with no request of its own; see [recommendationsFrom].
  ///
  /// `directors` is the first six staff by AniList's relevance, where the
  /// series director sits; in the default order `staff` can miss them (25
  /// edges of Frieren's held four kinds of director, not the Director).
  /// `staff` keeps its own order, which the Cast tab shows.
  ///
  /// It also carries the show's own season facts and its relations (round
  /// seven), so the Seasons strip knows the show's neighbours at no extra
  /// request; see [noteSeasons].
  Future<Map<String, dynamic>?> getAnimeStaff(String animeId) async {
    const String query = '''
    query (\$id: Int) {
      Media(id: \$id, type: ANIME) {
        $_seasonFields
        relations { edges { relationType node { $_seasonFields } } }
        title { romaji english native }
        coverImage { large extraLarge color }
        bannerImage
        duration
        nextAiringEpisode { airingAt episode }
        stats { scoreDistribution { score amount } }
        externalLinks { site url type }
        recommendations(sort: RATING_DESC, perPage: 6) {
          nodes {
            mediaRecommendation {
              id
              type
              isAdult
              title { romaji english }
              coverImage { large }
              averageScore
              episodes
              status
              seasonYear
              season
              format
              genres
              description
              trailer { id site }
            }
          }
        }
        studios(isMain: true) {
          nodes { name id }
        }
        directors: staff(sort: [RELEVANCE, ID], perPage: 6) {
          edges {
            role
            node {
              id
              name { full }
            }
          }
        }
        staff {
          edges {
            role
            node {
              id
              name { full }
              image { medium }
            }
          }
        }
        characters(sort: ROLE, perPage: 10) {
          edges {
            role
            voiceActors(language: JAPANESE) {
              id
              name { full }
              image { medium }
            }
            node {
              name { full }
              image { medium }
            }
          }
        }
      }
    }
    ''';
    try {
      final response = await _post({
        'query': query,
        'variables': {'id': int.parse(animeId)},
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']?['Media'];
      }
      return null;
    } catch (e) {
      print('AniList staff error: $e');
      return null;
    }
  }

  /// The recommendations in a [getAnimeStaff] response, as entries Detail can
  /// open directly. Kept to what searchAnime itself returns: anime only, and
  /// nothing marked adult. A recommendation AniList has since removed comes
  /// back as null and is skipped.
  List<Anime> recommendationsFrom(Map<String, dynamic>? media) {
    final nodes = media?['recommendations']?['nodes'] as List? ?? const [];
    final out = <Anime>[];
    for (final node in nodes) {
      final item = (node as Map?)?['mediaRecommendation'];
      if (item is! Map<String, dynamic>) continue;
      if (item['type'] != 'ANIME' || item['isAdult'] == true) continue;
      out.add(Anime(
        id: item['id'].toString(),
        title: item['title']?['romaji'] ?? 'Unknown',
        titleEnglish: item['title']?['english'],
        imageUrl: item['coverImage']?['large'],
        averageScore: item['averageScore'] != null
            ? (item['averageScore'] as num).toDouble()
            : null,
        episodes: item['episodes'] as int?,
        status: item['status'],
        seasonYear: item['seasonYear'],
        season: item['season'],
        format: item['format'],
        genres: item['genres'] != null
            ? List<String>.from(item['genres'])
            : [],
        description: item['description'],
        trailerUrl: _extractTrailerUrl(item['trailer']),
      ));
    }
    return out;
  }

  Future<Map<String, dynamic>?> getStaffDetails(int staffId) async {
    const String query = '''
    query (\$id: Int) {
      Staff(id: \$id) {
        id
        name { full native }
        image { large }
        description
        dateOfBirth { year month day }
        age
        homeTown
        bloodType
        staffMedia(sort: START_DATE_DESC, perPage: 50) {
          edges {
            staffRole
            node {
              id
              title { romaji english }
              coverImage { large }
              averageScore
              format
              startDate { year }
            }
          }
        }
        characterMedia(sort: START_DATE_DESC, perPage: 50) {
          edges {
            characterRole
            characterName
            node {
              id
              title { romaji english }
              coverImage { large }
              averageScore
              format
              startDate { year }
            }
          }
        }
      }
    }
    ''';
    try {
      final response = await _post({
        'query': query,
        'variables': {'id': staffId},
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']?['Staff'];
      }
      return null;
    } catch (e) {
      print('AniList staff details error: $e');
      return null;
    }
  }

  Future<List<Anime>> getRecommendedAnime(String animeId, List<String> genres) async {
    if (genres.isEmpty) return [];
    try {
      final results = await searchAnime('', genre: genres.first, sort: 'SCORE_DESC');
      return results.where((a) => a.id != animeId).take(6).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Anime>> getTrending()  => searchAnime('', sort: 'TRENDING_DESC');
  Future<List<Anime>> getPopular()   => searchAnime('', sort: 'POPULARITY_DESC');
  Future<List<Anime>> getTopRated()  => searchAnime('', sort: 'SCORE_DESC');
  Future<List<Anime>> getSeasonal(String season, int year) =>
      searchAnime('', season: season, year: year);

  Future<Anime?> getAnimeById(String id) async {
    const String query = '''
    query (\$id: Int) {
      Media(id: \$id, type: ANIME) {
        id
        title { romaji english }
        coverImage { large }
        averageScore
        episodes
        status
        seasonYear
        season
        format
        genres
        description
        trailer { id site }
      }
    }
    ''';
    try {
      final response = await _post({
        'query': query,
        'variables': {'id': int.parse(id)},
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final item = data['data']?['Media'];
        if (item == null) return null;
        return Anime(
          id: item['id'].toString(),
          title: item['title']['romaji'] ?? 'Unknown',
          titleEnglish: item['title']['english'],
          imageUrl: item['coverImage']?['large'],
          averageScore: item['averageScore'] != null
              ? (item['averageScore'] as num).toDouble()
              : null,
          episodes: item['episodes'] as int?,
          status: item['status'],
          seasonYear: item['seasonYear'],
          season: item['season'],
          format: item['format'],
          genres: item['genres'] != null
              ? List<String>.from(item['genres'])
              : [],
          description: item['description'],
          trailerUrl: _extractTrailerUrl(item['trailer']),
        );
      }
      return null;
    } catch (e) {
      print('AniList getById error: $e');
      return null;
    }
  }

  // ── Seasons (round seven) ───────────────────────────────────
  // Detail's Seasons strip: a show's chain of PREQUEL and SEQUEL relations
  // on AniList, walked a step at a time. getAnimeStaff carries the open
  // show's own relations, so its neighbours cost nothing. Each further step
  // is one request for every show at the edge of what's known (id_in), made
  // through _post, so it queues on the throttle, notes the rate-limit
  // headers and backs off on a 429. What a step learns is kept per show: in
  // memory for the app's run, and on the device for a few days, so a season
  // opened from the strip, or a show opened again, asks for nothing already
  // known.
  //
  // Seasons are the TV, TV_SHORT and ONA entries. A film, special or OVA in
  // the chain is walked through, never shown, and only one at a time: past
  // one the walk goes on only to a season, so a run of films (a film series)
  // is never followed.

  /// AniList formats that count as a season.
  static const seasonFormats = {'TV', 'TV_SHORT', 'ONA'};

  /// What the strip needs of a show, for the open show and each relation.
  static const String _seasonFields = '''
          id
          type
          isAdult
          format
          status
          episodes
          season
          seasonYear
          startDate { year month day }
          title { romaji english }
          coverImage { large color }
          nextAiringEpisode { episode }
  ''';

  /// One step of the walk: these shows, with their relations.
  static const String _seasonQuery = '''
    query (\$ids: [Int], \$perPage: Int) {
      Page(page: 1, perPage: \$perPage) {
        media(id_in: \$ids, type: ANIME) {
          $_seasonFields
          relations { edges { relationType node { $_seasonFields } } }
        }
      }
    }
  ''';

  static final Map<int, _SeasonNode> _seasonNodes = {};
  static final Map<int, Future<void>> _seasonReads = {};
  static Future<void>? _seasonsRestored;
  static const _seasonsKey = 'anilist_seasons_v1';

  /// Relations read within this long aren't read again.
  static const _seasonsFresh = Duration(days: 3);

  /// Shows not seen for this long are dropped from the device.
  static const _seasonsKept = Duration(days: 14);
  static const _seasonsMaxStored = 400;

  /// One walk reads at most this many steps, reaches at most this many
  /// shows, and asks for at most this many shows in one step.
  static const _seasonsMaxSteps = 8;
  static const _seasonsMaxShows = 40;
  static const _seasonsMaxBatch = 25;

  /// Keeps the open show's season facts and relations from its
  /// [getAnimeStaff] answer.
  static void noteSeasons(Map<String, dynamic>? media) {
    if (media != null) _keepSeason(media, DateTime.now());
  }

  /// What is known of [animeId]'s seasons now, from memory, with no request:
  /// a season opened from the strip shows the strip in its first frame.
  static SeasonChain? knownSeasons(int animeId) =>
      _seasonChainFrom(animeId, DateTime.now()).$1;

  /// Walks [animeId]'s seasons, reporting what is known to [onChain] at the
  /// start and after each step, until nothing is left to read or [alive]
  /// says the screen has gone. A step that fails ends the walk with what was
  /// known, marked [SeasonChain.failed]. Never throws.
  Future<void> walkSeasons(
    int animeId, {
    required bool Function() alive,
    required void Function(SeasonChain chain) onChain,
  }) async {
    var learned = false;
    try {
      await (_seasonsRestored ??= _restoreSeasons());
      for (var step = 0;; step++) {
        final (chain, toRead) = _seasonChainFrom(animeId, DateTime.now());
        if (chain == null || !alive()) return;
        if (toRead.isEmpty || step >= _seasonsMaxSteps) {
          // Done, or as far as one walk goes: nothing more is coming.
          onChain(chain._with(moreBefore: false, moreAfter: false));
          return;
        }
        onChain(chain);
        try {
          await _readSeasons(toRead.take(_seasonsMaxBatch).toList());
          learned = true;
        } catch (_) {
          final known = _seasonChainFrom(animeId, DateTime.now()).$1;
          if (known != null && alive()) onChain(known._with(failed: true));
          return;
        }
      }
    } catch (_) {
      // Nothing here may reach Crashlytics as a fatal; the strip keeps what
      // it showed.
    } finally {
      // Once per walk, not per step: it writes every show kept.
      if (learned) unawaited(_storeSeasons());
    }
  }

  /// Keeps a Media entry's season facts and, when it carries its relations,
  /// its PREQUEL and SEQUEL neighbours: anime only, nothing marked adult.
  /// Returns its id, or null when it isn't a usable entry.
  static int? _keepSeason(Map<String, dynamic> media, DateTime now) {
    final season = AnimeSeason._fromMedia(media);
    if (season == null) return null;
    final node = _seasonNodes.putIfAbsent(season.id, () => _SeasonNode(season, now))
      ..season = season
      ..seenAt = now;
    final edges = media['relations']?['edges'];
    if (edges is! List) return season.id;
    final before = <int>[], after = <int>[];
    for (final edge in edges) {
      if (edge is! Map) continue;
      final kind = edge['relationType'];
      final other = edge['node'];
      if (kind != 'PREQUEL' && kind != 'SEQUEL') continue;
      if (other is! Map<String, dynamic>) continue;
      if (other['type'] != 'ANIME' || other['isAdult'] == true) continue;
      final neighbour = AnimeSeason._fromMedia(other);
      if (neighbour == null) continue;
      _seasonNodes.putIfAbsent(neighbour.id, () => _SeasonNode(neighbour, now))
        ..season = neighbour
        ..seenAt = now;
      (kind == 'PREQUEL' ? before : after).add(neighbour.id);
    }
    node
      ..prequels = before
      ..sequels = after
      ..readAt = now;
    return season.id;
  }

  /// The chain from [startId] as known now, and the shows whose relations
  /// the next step reads: those never read, then those read too long ago.
  /// Null when nothing is known of [startId].
  static (SeasonChain?, List<int>) _seasonChainFrom(int startId, DateTime now) {
    if (!_seasonNodes.containsKey(startId)) return (null, const []);
    // Places along the chain: the start at 0, prequels before, sequels after.
    final place = <int, int>{startId: 0};
    final queue = <int>[startId];
    final unread = <int>[], stale = <int>[];
    for (var q = 0; q < queue.length; q++) {
      final id = queue[q];
      final node = _seasonNodes[id]!;
      final readAt = node.readAt;
      if (readAt == null) {
        unread.add(id);
        continue;
      }
      if (now.difference(readAt) > _seasonsFresh) stale.add(id);
      final steps = [
        for (final p in node.prequels!) (p, -1),
        for (final s in node.sequels!) (s, 1),
      ];
      for (final (next, step) in steps) {
        if (place.containsKey(next) || place.length >= _seasonsMaxShows) continue;
        final to = _seasonNodes[next];
        // Past a film, special or OVA, only to a season.
        if (to == null || !(to.season.isSeason || node.season.isSeason)) continue;
        place[next] = place[id]! + step;
        queue.add(next);
      }
    }
    final seasons = [
      for (final id in queue)
        if (_seasonNodes[id]!.season.isSeason) _seasonNodes[id]!.season,
    ]..sort((a, b) {
        final byPlace = place[a.id]!.compareTo(place[b.id]!);
        if (byPlace != 0) return byPlace;
        // Two at one place (a show with two sequels): the earlier first,
        // undated ones last.
        final byDate = (a.startDate ?? 99999999).compareTo(b.startDate ?? 99999999);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    final first = seasons.isEmpty ? 0 : place[seasons.first.id]!;
    final last = seasons.isEmpty ? 0 : place[seasons.last.id]!;
    final chain = SeasonChain(
      seasons: seasons,
      currentId: startId,
      // A show whose relations are unread may lead to more seasons on its
      // side of the chain.
      moreBefore: unread.any((id) => place[id]! <= first),
      moreAfter: unread.any((id) => place[id]! >= last),
    );
    return (chain, [...unread, ...stale]);
  }

  /// Reads these shows' relations, sharing a read already under way for
  /// any of them.
  Future<void> _readSeasons(List<int> ids) async {
    final waits = <Future<void>>{};
    final fresh = <int>[];
    for (final id in ids) {
      final pending = _seasonReads[id];
      if (pending != null) {
        waits.add(pending);
      } else {
        fresh.add(id);
      }
    }
    if (fresh.isNotEmpty) {
      final read = _fetchSeasons(fresh);
      for (final id in fresh) {
        _seasonReads[id] = read;
      }
      read.whenComplete(() {
        for (final id in fresh) {
          if (identical(_seasonReads[id], read)) _seasonReads.remove(id);
        }
      }).ignore();
      waits.add(read);
    }
    await Future.wait(waits);
  }

  Future<void> _fetchSeasons(List<int> ids) async {
    final response = await _post({
      'query': _seasonQuery,
      'variables': {'ids': ids, 'perPage': ids.length},
    });
    if (response.statusCode != 200) {
      throw StateError('AniList ${response.statusCode} (seasons)');
    }
    final media = jsonDecode(response.body)['data']?['Page']?['media'];
    if (media is! List) throw const FormatException('no media (seasons)');
    final now = DateTime.now();
    final seen = <int>{};
    for (final m in media) {
      if (m is! Map<String, dynamic>) continue;
      final id = _keepSeason(m, now);
      if (id != null) seen.add(id);
    }
    // A show AniList didn't send back (removed, or not an anime) has
    // nothing more to give: it counts as read, with no neighbours, so no
    // walk asks for it again.
    for (final id in ids) {
      if (seen.contains(id)) continue;
      _seasonNodes[id]
        ?..prequels = const []
        ..sequels = const []
        ..readAt = now;
    }
  }

  /// Loads what earlier runs kept on the device, under what this run
  /// already knows.
  static Future<void> _restoreSeasons() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_seasonsKey);
      if (raw == null) return;
      final stored = jsonDecode(raw);
      if (stored is! Map) return;
      final now = DateTime.now();
      for (final value in stored.values) {
        if (value is! Map) continue;
        final season = AnimeSeason._fromJson(value['s']);
        final seen = value['a'];
        if (season == null || seen is! int) continue;
        final seenAt = DateTime.fromMillisecondsSinceEpoch(seen);
        if (now.difference(seenAt) > _seasonsKept) continue;
        if (_seasonNodes.containsKey(season.id)) continue;
        final node = _SeasonNode(season, seenAt);
        final read = value['t'], before = value['p'], after = value['q'];
        if (read is int && before is List && after is List) {
          node
            ..prequels = [for (final x in before) if (x is int) x]
            ..sequels = [for (final x in after) if (x is int) x]
            ..readAt = DateTime.fromMillisecondsSinceEpoch(read);
        }
        _seasonNodes[season.id] = node;
      }
    } catch (_) {}
  }

  /// Keeps the shows seen lately on the device, newest first.
  static Future<void> _storeSeasons() async {
    try {
      final now = DateTime.now();
      final nodes = _seasonNodes.values
          .where((n) => now.difference(n.seenAt) <= _seasonsKept)
          .toList()
        ..sort((a, b) => b.seenAt.compareTo(a.seenAt));
      final out = <String, Object?>{
        for (final n in nodes.take(_seasonsMaxStored))
          '${n.season.id}': {
            's': n.season._toJson(),
            'a': n.seenAt.millisecondsSinceEpoch,
            if (n.readAt != null) ...{
              't': n.readAt!.millisecondsSinceEpoch,
              'p': n.prequels,
              'q': n.sequels,
            },
          },
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seasonsKey, jsonEncode(out));
    } catch (_) {}
  }

  String? _extractTrailerUrl(Map<String, dynamic>? trailer) {
    if (trailer == null) return null;
    final id   = trailer['id'] as String?;
    final site = trailer['site'] as String?;
    if (id == null || id.isEmpty) return null;
    if (site == 'youtube') return 'https://www.youtube.com/watch?v=$id';
    return null;
  }
}

/// One season of a show on AniList, as Detail's Seasons strip shows it
/// (round seven).
class AnimeSeason {
  const AnimeSeason({
    required this.id,
    required this.title,
    this.titleEnglish,
    this.format,
    this.status,
    this.episodes,
    this.season,
    this.seasonYear,
    this.startDate,
    this.coverUrl,
    this.coverColor,
    this.nextEpisode,
  });

  final int id;

  /// AniList's romaji title, and its English one when it has one.
  final String title;
  final String? titleEnglish;

  /// AniList's MediaFormat. TV, TV_SHORT and ONA count as seasons.
  final String? format;

  /// AniList's MediaStatus: FINISHED, RELEASING, NOT_YET_RELEASED …
  final String? status;
  final int? episodes;
  final String? season;
  final int? seasonYear;

  /// When it started, as yyyymmdd, with 00 for an unknown month or day.
  final int? startDate;

  /// coverImage.large, and coverImage.color ("#e4a15d").
  final String? coverUrl;
  final String? coverColor;

  /// The next episode to air, while it airs.
  final int? nextEpisode;

  bool get isSeason => AnilistService.seasonFormats.contains(format);

  /// The year it started.
  int? get year => seasonYear ?? (startDate == null ? null : startDate! ~/ 10000);

  /// An entry Detail can open. It has no score, so Detail treats it as a
  /// list row's stub and fetches the rest, synopsis and all, as it does for
  /// a row of My List.
  Anime toAnime() => Anime(
        id: '$id',
        title: title,
        titleEnglish: titleEnglish,
        imageUrl: coverUrl,
        episodes: episodes,
        status: status,
        season: season,
        seasonYear: seasonYear,
        format: format,
      );

  static AnimeSeason? _fromMedia(Map<String, dynamic> media) {
    final id = media['id'];
    final title = media['title'];
    if (id is! int || title is! Map) return null;
    final english = title['english'] as String?;
    final date = media['startDate'];
    final year = date is Map ? date['year'] : null;
    return AnimeSeason(
      id: id,
      title: title['romaji'] as String? ?? english ?? 'Unknown',
      titleEnglish: english,
      format: media['format'] as String?,
      status: media['status'] as String?,
      episodes: media['episodes'] as int?,
      season: media['season'] as String?,
      seasonYear: media['seasonYear'] as int?,
      startDate: year is int
          ? year * 10000 + ((date['month'] as int?) ?? 0) * 100 + ((date['day'] as int?) ?? 0)
          : null,
      coverUrl: media['coverImage']?['large'] as String?,
      coverColor: media['coverImage']?['color'] as String?,
      nextEpisode: media['nextAiringEpisode']?['episode'] as int?,
    );
  }

  Map<String, Object?> _toJson() => {
        'id': id,
        'title': title,
        'titleEnglish': titleEnglish,
        'format': format,
        'status': status,
        'episodes': episodes,
        'season': season,
        'seasonYear': seasonYear,
        'startDate': startDate,
        'coverUrl': coverUrl,
        'coverColor': coverColor,
        'nextEpisode': nextEpisode,
      };

  static AnimeSeason? _fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    if (id is! int || title is! String) return null;
    return AnimeSeason(
      id: id,
      title: title,
      titleEnglish: json['titleEnglish'] as String?,
      format: json['format'] as String?,
      status: json['status'] as String?,
      episodes: json['episodes'] as int?,
      season: json['season'] as String?,
      seasonYear: json['seasonYear'] as int?,
      startDate: json['startDate'] as int?,
      coverUrl: json['coverUrl'] as String?,
      coverColor: json['coverColor'] as String?,
      nextEpisode: json['nextEpisode'] as int?,
    );
  }
}

/// A show's seasons in order, as far as they are known (round seven).
class SeasonChain {
  const SeasonChain({
    required this.seasons,
    required this.currentId,
    this.moreBefore = false,
    this.moreAfter = false,
    this.failed = false,
  });

  /// The seasons (TV, TV_SHORT and ONA entries), first to last.
  final List<AnimeSeason> seasons;

  /// The show the chain was walked from. A film or a special isn't among
  /// [seasons] itself.
  final int currentId;

  /// More seasons may still turn up before the first known one, or after
  /// the last: a show on that side has relations not yet read.
  final bool moreBefore;
  final bool moreAfter;

  /// The last read failed, so those won't turn up without another try.
  final bool failed;

  SeasonChain _with({bool? moreBefore, bool? moreAfter, bool? failed}) => SeasonChain(
        seasons: seasons,
        currentId: currentId,
        moreBefore: moreBefore ?? this.moreBefore,
        moreAfter: moreAfter ?? this.moreAfter,
        failed: failed ?? this.failed,
      );
}

/// A show the season walk knows, with its neighbours once its relations
/// are read.
class _SeasonNode {
  _SeasonNode(this.season, this.seenAt);

  AnimeSeason season;

  /// When it was last seen, its own entry or as a neighbour.
  DateTime seenAt;

  /// Its PREQUEL and SEQUEL neighbours: null until its relations are read.
  List<int>? prequels;
  List<int>? sequels;
  DateTime? readAt;
}
