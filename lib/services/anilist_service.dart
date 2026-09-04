import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/anime_model.dart';

class AnilistService {
  static const String _apiUrl = 'https://graphql.anilist.co';

  // ── Adaptive reservation-based throttle ─────────────────────
  // Normally allows a brisk 350ms gap (~170/min). After a 429, it
  // backs off to a 2s gap (30/min) for a cooldown window, then
  // recovers. This keeps the app fast when AniList is healthy and
  // only slows down when we're actually being rate-limited.
  static DateTime _nextSlotTime = DateTime(2000);
  static DateTime _slowUntil = DateTime(2000);
  static const _fastGap = Duration(milliseconds: 350);
  static const _slowGap = Duration(milliseconds: 2000);
  static const _cooldown = Duration(seconds: 60);

  static Duration get _minGap =>
      DateTime.now().isBefore(_slowUntil) ? _slowGap : _fastGap;

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

  /// POST with throttle + up to 2 retries on 429, respecting Retry-After.
  Future<http.Response> _post(Map<String, dynamic> body) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await _reserveSlot();
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'Hanj/1.0',
        },
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

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

  Future<Map<String, dynamic>?> getAnimeStaff(String animeId) async {
    const String query = '''
    query (\$id: Int) {
      Media(id: \$id, type: ANIME) {
        studios(isMain: true) {
          nodes { name id }
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

  String? _extractTrailerUrl(Map<String, dynamic>? trailer) {
    if (trailer == null) return null;
    final id   = trailer['id'] as String?;
    final site = trailer['site'] as String?;
    if (id == null || id.isEmpty) return null;
    if (site == 'youtube') return 'https://www.youtube.com/watch?v=$id';
    return null;
  }
}
