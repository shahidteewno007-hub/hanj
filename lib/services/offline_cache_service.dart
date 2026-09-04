import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/anime_model.dart';
import 'anilist_service.dart';

class OfflineCacheService {
  OfflineCacheService._();
  static final instance = OfflineCacheService._();

  final _anilist = AnilistService();

  static const _ttl = Duration(hours: 1);

  static const _kTrending  = 'cache_trending';
  static const _kPopular   = 'cache_popular';
  static const _kTopRated  = 'cache_top_rated';
  static const _kSeasonal  = 'cache_seasonal';
  static const _kTimestamp = '_ts';

  // ── In-memory layer on top of SharedPreferences ──────────────
  // Avoids disk reads on repeated calls within the same session,
  // and survives widget rebuilds without re-fetching.
  static final Map<String, List<Anime>> _memCache = {};

  Future<List<Anime>> getTrending({bool forceRefresh = false}) =>
      _getOrFetch(_kTrending, forceRefresh, () => _anilist.getTrending());

  Future<List<Anime>> getPopular({bool forceRefresh = false}) =>
      _getOrFetch(_kPopular, forceRefresh, () => _anilist.getPopular());

  Future<List<Anime>> getTopRated({bool forceRefresh = false}) =>
      _getOrFetch(_kTopRated, forceRefresh, () => _anilist.getTopRated());

  Future<List<Anime>> getSeasonal(
    String season,
    int year, {
    bool forceRefresh = false,
  }) {
    final key = '${_kSeasonal}_${season}_$year';
    return _getOrFetch(
        key, forceRefresh, () => _anilist.getSeasonal(season, year));
  }

  Future<void> cacheAnimeDetail(Anime anime) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = 'cache_anime_${anime.id}';
    await prefs.setString(key, jsonEncode(anime.toJson()));
    await prefs.setInt(
        '$key$_kTimestamp', DateTime.now().millisecondsSinceEpoch);
  }

  Future<Anime?> getCachedAnimeDetail(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final key   = 'cache_anime_$id';
    final raw   = prefs.getString(key);
    if (raw == null) return null;
    try {
      return Anime.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearAll() async {
    _memCache.clear();
    final prefs = await SharedPreferences.getInstance();
    final keys  = prefs.getKeys().where((k) => k.startsWith('cache_'));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  Future<bool> get hasCachedHomeData async {
    if (_memCache.containsKey(_kTrending) ||
        _memCache.containsKey(_kPopular) ||
        _memCache.containsKey(_kTopRated)) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_kTrending) ||
        prefs.containsKey(_kPopular) ||
        prefs.containsKey(_kTopRated);
  }

  Future<List<Anime>> _getOrFetch(
    String key,
    bool forceRefresh,
    Future<List<Anime>> Function() fetcher,
  ) async {
    // 1. In-memory cache hit (fastest, no disk read)
    if (!forceRefresh && _memCache.containsKey(key)) {
      return _memCache[key]!;
    }

    final prefs = await SharedPreferences.getInstance();

    // 2. SharedPreferences fresh cache
    if (!forceRefresh) {
      final cached   = prefs.getString(key);
      final tsKey    = '$key$_kTimestamp';
      final cachedAt = prefs.getInt(tsKey);
      final isFresh  = cachedAt != null &&
          DateTime.now().millisecondsSinceEpoch - cachedAt <
              _ttl.inMilliseconds;

      if (cached != null && isFresh) {
        try {
          final list = (jsonDecode(cached) as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .map(Anime.fromJson)
              .toList();
          _memCache[key] = list; // warm memory cache
          return list;
        } catch (_) {
          // Cache corrupt — fall through to fetch
        }
      }
    }

    // 3. Fetch from network
    List<Anime>? staleData;
    try {
      // Keep stale data ready in case fetch fails or returns empty
      final staleRaw = prefs.getString(key);
      if (staleRaw != null) {
        staleData = (jsonDecode(staleRaw) as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(Anime.fromJson)
            .toList();
      }
    } catch (_) {}

    try {
      final results = await fetcher();

      if (results.isNotEmpty) {
        // Persist and warm caches
        _memCache[key] = results;
        try {
          await prefs.setString(
              key, jsonEncode(results.map((a) => a.toJson()).toList()));
          await prefs.setInt(
              '$key$_kTimestamp', DateTime.now().millisecondsSinceEpoch);
        } catch (_) {
          // Serialization failed — still return fresh results
        }
        return results;
      }

      // Network returned empty — use stale rather than showing blank
      if (staleData != null && staleData.isNotEmpty) {
        _memCache[key] = staleData;
        return staleData;
      }
      return [];
    } catch (_) {
      // Network exception — return stale if available
      if (staleData != null && staleData.isNotEmpty) {
        _memCache[key] = staleData;
        return staleData;
      }
      return [];
    }
  }
}
