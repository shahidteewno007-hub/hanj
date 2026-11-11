import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/achievements.dart';
import 'anilist_service.dart';

/// AniList's facts about the shows you've finished (format, season, year,
/// air dates), which five achievements need and list entries don't store:
/// Decades, Every form, A full year, As it aired and On the day.
///
/// Asked for in batches of 50 (`Page(media(id_in))`), so Shahid's 89
/// finished shows are 2 requests and a heavy user's 430 are 9, once per
/// phone. Every request joins AniList's shared queue as PulseService._query
/// does: throttle, noteStatus, noteLimits, backoff on a 429, a 15 s
/// timeout, and nothing ever thrown.
///
/// Kept on this device only (SharedPreferences), never in Firestore: storing
/// AniList's media data there is the open question under AniList's terms
/// ("no data storage service"), which waits on Shahid's contact with them.
/// A finished show's facts never change, so they're kept for good; a show
/// still airing is asked again a day later, and one AniList didn't return a
/// week later.
class MediaFacts {
  MediaFacts._();
  static final instance = MediaFacts._();

  static const _apiUrl = 'https://graphql.anilist.co';
  static const _key = 'hanj.mediaFacts.v1';
  static const _perRequest = 50;

  /// How long until a show not yet final is asked again.
  static const _airingAgain = Duration(days: 1);
  static const _missingAgain = Duration(days: 7);

  static const String _query = r'''
  query ($ids: [Int], $perPage: Int) {
    Page(page: 1, perPage: $perPage) {
      media(id_in: $ids, type: ANIME) {
        id format season seasonYear status
        startDate { year month day }
        endDate { year month day }
      }
    }
  }
  ''';

  final Map<int, ShowFacts> _facts = {};

  /// When each show's facts were last asked for.
  final Map<int, DateTime> _askedAt = {};

  Future<void>? _restored;

  // Look-ups run one after another, so two callers never ask for the same
  // shows at once.
  Future<void> _queue = Future.value();

  /// What this phone already knows, with no request.
  Future<Map<int, ShowFacts>> known() async {
    await (_restored ??= _restore());
    return Map.of(_facts);
  }

  /// The facts for [ids]: those known, after asking AniList for the ones
  /// unknown or due again. A failed request leaves its shows unknown; it
  /// never throws.
  Future<Map<int, ShowFacts>> lookUp(Iterable<int> ids) {
    final wanted = ids.toSet();
    final done = _queue.then((_) => _lookUp(wanted));
    _queue = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<Map<int, ShowFacts>> _lookUp(Set<int> wanted) async {
    try {
      await (_restored ??= _restore());
      final now = DateTime.now();
      final due = [for (final id in wanted) if (_isDue(id, now)) id];
      var learned = false;
      for (var i = 0; i < due.length; i += _perRequest) {
        final chunk = due.sublist(i, (i + _perRequest).clamp(0, due.length));
        final media = await _ask(chunk);
        if (media == null) continue;
        final at = DateTime.now();
        final seen = <int>{};
        for (final m in media) {
          final facts = _fromMedia(m);
          if (facts == null) continue;
          _facts[facts.id] = facts;
          _askedAt[facts.id] = at;
          seen.add(facts.id);
        }
        // A show AniList didn't send back (removed, or not an anime) is
        // kept with no facts, so it counts as known and isn't asked for on
        // every visit.
        for (final id in chunk) {
          if (seen.contains(id)) continue;
          _facts[id] = ShowFacts(id: id);
          _askedAt[id] = at;
        }
        learned = true;
      }
      if (learned) await _store();
    } catch (_) {
      // Nothing here may reach Crashlytics as a fatal: what's known stands.
    }
    return {
      for (final id in wanted)
        if (_facts[id] case final ShowFacts f) id: f,
    };
  }

  bool _isDue(int id, DateTime now) {
    final facts = _facts[id];
    final asked = _askedAt[id];
    if (facts == null || asked == null) return true;
    if (_isFinal(facts)) return false;
    final again = facts.status == null ? _missingAgain : _airingAgain;
    return now.difference(asked) >= again;
  }

  static bool _isFinal(ShowFacts f) =>
      f.status == 'FINISHED' || f.status == 'CANCELLED';

  /// One request, through AniList's shared queue (PulseService._query's
  /// pattern). Null when it failed.
  Future<List<Object?>?> _ask(List<int> ids) async {
    await AnilistService.throttle();
    try {
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
              body: jsonEncode({
                'query': _query,
                'variables': {'ids': ids, 'perPage': ids.length},
              }),
            )
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        AnilistService.noteStatus(0, 'media facts');
        rethrow;
      }
      AnilistService.noteStatus(response.statusCode, 'media facts');
      AnilistService.noteLimits(response.headers);
      if (response.statusCode == 429) {
        final retryAfter =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 10;
        AnilistService.backoff(retryAfter);
        return null;
      }
      if (response.statusCode == 200) {
        final media = jsonDecode(response.body)['data']?['Page']?['media'];
        if (media is List) return media;
      }
    } catch (_) {}
    return null;
  }

  static ShowFacts? _fromMedia(Object? m) {
    if (m is! Map) return null;
    final id = m['id'];
    if (id is! int) return null;
    return ShowFacts(
      id: id,
      format: m['format'] is String ? m['format'] as String : null,
      season: m['season'] is String ? m['season'] as String : null,
      seasonYear: m['seasonYear'] is int ? m['seasonYear'] as int : null,
      status: m['status'] is String ? m['status'] as String : null,
      startDate: _yyyymmdd(m['startDate']),
      endDate: _yyyymmdd(m['endDate']),
    );
  }

  /// AniList's FuzzyDate as yyyymmdd, 00 for an unknown month or day; null
  /// with no year.
  static int? _yyyymmdd(Object? date) {
    if (date is! Map) return null;
    final y = date['year'], m = date['month'], d = date['day'];
    if (y is! int) return null;
    return y * 10000 + (m is int ? m : 0) * 100 + (d is int ? d : 0);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final stored = jsonDecode(raw);
      if (stored is! Map) return;
      for (final e in stored.entries) {
        final id = int.tryParse('${e.key}');
        final v = e.value;
        if (id == null || v is! Map || v['t'] is! int) continue;
        String? text(String k) => v[k] is String ? v[k] as String : null;
        int? number(String k) => v[k] is int ? v[k] as int : null;
        _facts.putIfAbsent(
          id,
          () => ShowFacts(
            id: id,
            format: text('f'),
            season: text('s'),
            seasonYear: number('y'),
            status: text('st'),
            startDate: number('sd'),
            endDate: number('ed'),
          ),
        );
        _askedAt.putIfAbsent(id, () => DateTime.fromMillisecondsSinceEpoch(v['t'] as int));
      }
    } catch (_) {}
  }

  /// Keeps every show's facts on the device, about 60 bytes a show.
  Future<void> _store() async {
    try {
      final out = <String, Object?>{
        for (final f in _facts.values)
          '${f.id}': {
            'f': ?f.format,
            's': ?f.season,
            'y': ?f.seasonYear,
            'st': ?f.status,
            'sd': ?f.startDate,
            'ed': ?f.endDate,
            't': (_askedAt[f.id] ?? DateTime.now()).millisecondsSinceEpoch,
          },
      };
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(out));
    } catch (_) {}
  }
}
