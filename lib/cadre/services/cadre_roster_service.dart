import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/cadre_affinity.dart';
import '../data/cadre_rankings.dart';
import '../models/cadre_fighter.dart';

/// A search hit, before its cast has been fetched.
class CadreAnimeSummary {
  final int id;
  final String title;
  final String coverUrl;
  final int? seasonYear;

  /// How many characters AniList lists for this anime, or null when the field
  /// came back empty.
  ///
  /// An upper bound, not a promise. The roster fetch caps at 25, and anyone
  /// without usable art is dropped, so the drafted cast is this or smaller —
  /// which is exactly why the picker phrases it as "up to".
  final int? castSize;

  const CadreAnimeSummary({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.seasonYear,
    this.castSize,
  });

  /// Characters that could actually reach a deck, given the fetch cap.
  int? drawableFor(int fetchLimit) =>
      castSize == null ? null : (castSize! < fetchLimit ? castSize : fetchLimit);
}

class CadreRosterException implements Exception {
  final String message;
  const CadreRosterException(this.message);

  @override
  String toString() => message;
}

/// Pulls an anime's cast from AniList and scores it into a draftable roster.
///
/// One network call per anime, then cached in memory for the session. The
/// enrichment pass (Firestore-backed, added in a later step) will layer on top
/// of this without changing the call shape.
class CadreRosterService {
  CadreRosterService._();
  static final CadreRosterService instance = CadreRosterService._();

  static const String _endpoint = 'https://graphql.anilist.co';

  /// How many characters a roster fetch pulls. Also the ceiling on what the
  /// pool picker can promise, since nobody past this point is ever drafted.
  ///
  /// This does not lengthen a match — 22 characters already deal the maximum
  /// eleven cards and ten rounds. It buys variety: at 25 a match deals 22 of
  /// them, so you see almost the whole cast every game.
  static const int defaultCastLimit = _aniListPageCap * _castPages;

  final Map<int, CadreRoster> _memoryCache = <int, CadreRoster>{};

  /// AniList clamps a nested connection to this many per page no matter what
  /// we ask for. Confirmed on device: requesting 50 still returned 25.
  static const int _aniListPageCap = 25;

  /// Pages of cast fetched per anime. Both arrive in a single HTTP call
  /// through GraphQL aliases, so this costs one request and one rate-limit
  /// hit, not two.
  static const int _castPages = 2;

  static const String _query = r'''
fragment Cast on CharacterConnection {
  edges {
    role
    node {
      id
      name { full }
      image { large medium }
      favourites
      gender
    }
  }
}

query ($id: Int, $search: String, $perPage: Int) {
  Media(id: $id, search: $search, type: ANIME) {
    id
    title { romaji english }
    p1: characters(sort: [ROLE, FAVOURITES_DESC], page: 1, perPage: $perPage) {
      ...Cast
    }
    p2: characters(sort: [ROLE, FAVOURITES_DESC], page: 2, perPage: $perPage) {
      ...Cast
    }
  }
}
''';

  /// Fetch by AniList media id.
  Future<CadreRoster> fetchById(int animeId, {int limit = defaultCastLimit}) {
    final cached = _memoryCache[animeId];
    if (cached != null) return Future<CadreRoster>.value(cached);
    return _fetch(
      <String, dynamic>{'id': animeId, 'perPage': _aniListPageCap},
      limit,
    );
  }

  /// Fetch by title. Useful for the dev screen and for a future search field.
  Future<CadreRoster> fetchByTitle(String title, {int limit = defaultCastLimit}) {
    return _fetch(
      <String, dynamic>{'search': title, 'perPage': _aniListPageCap},
      limit,
    );
  }

  /// Accepts either a numeric AniList id or a title.
  Future<CadreRoster> fetchByQuery(String raw, {int limit = defaultCastLimit}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const CadreRosterException('Enter an anime title or AniList id.');
    }
    final asId = int.tryParse(trimmed);
    return asId != null
        ? fetchById(asId, limit: limit)
        : fetchByTitle(trimmed, limit: limit);
  }

  static const String _searchQuery = r'''
query ($search: String, $perPage: Int) {
  Page(page: 1, perPage: $perPage) {
    media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
      id
      seasonYear
      title { romaji english }
      coverImage { large medium }
      characters(perPage: 1) { pageInfo { total } }
    }
  }
}
''';

  /// Browse anime to add to a pool. Returns titles, not casts.
  Future<List<CadreAnimeSummary>> searchAnime(
    String query, {
    int limit = 12,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <CadreAnimeSummary>[];

    final decoded = await _post(<String, dynamic>{
      'query': _searchQuery,
      'variables': <String, dynamic>{'search': trimmed, 'perPage': limit},
    });

    final list = ((decoded['data'] as Map<String, dynamic>?)?['Page']
            as Map<String, dynamic>?)?['media'] as List<dynamic>?;
    if (list == null) return const <CadreAnimeSummary>[];

    final out = <CadreAnimeSummary>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final titleMap = (item['title'] as Map<String, dynamic>?) ?? const {};
      final cover = (item['coverImage'] as Map<String, dynamic>?) ?? const {};
      final title = (titleMap['english'] as String?)?.trim().isNotEmpty == true
          ? (titleMap['english'] as String).trim()
          : ((titleMap['romaji'] as String?) ?? '').trim();
      if (title.isEmpty) continue;

      final pageInfo = ((item['characters'] as Map<String, dynamic>?)?[
          'pageInfo'] as Map<String, dynamic>?);
      final total = (pageInfo?['total'] as num?)?.toInt();

      out.add(
        CadreAnimeSummary(
          id: (item['id'] as num?)?.toInt() ?? -1,
          title: title,
          coverUrl: (cover['large'] as String?) ??
              (cover['medium'] as String?) ??
              '',
          seasonYear: (item['seasonYear'] as num?)?.toInt(),
          castSize: (total != null && total > 0) ? total : null,
        ),
      );
    }
    return out;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_endpoint),
            headers: const <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const CadreRosterException(
        'Could not reach AniList. Check the connection and try again.',
      );
    }

    if (response.statusCode == 429) {
      throw const CadreRosterException(
        'AniList is rate limiting. Wait a moment and try again.',
      );
    }
    if (response.statusCode == 404) {
      throw const CadreRosterException('No anime matched that search.');
    }
    if (response.statusCode != 200) {
      throw CadreRosterException(
        'AniList returned ${response.statusCode}. Try again.',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;

    // AniList answers 200 even when the query itself was rejected — a bad
    // field name comes back as {"data": null, "errors": [...]}. Without this
    // that surfaces as "no results", which sends you looking in the wrong
    // place. Partial responses that still carry data are left alone.
    if (decoded['data'] == null) {
      final errors = decoded['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        final message =
            first is Map<String, dynamic> ? first['message'] as String? : null;
        throw CadreRosterException(
          message == null || message.isEmpty
              ? 'AniList rejected the request.'
              : 'AniList: $message',
        );
      }
    }

    return decoded;
  }

  /// Flattens one aliased page of the cast query into its edge list.
  static List<dynamic> _edgesOf(dynamic connection) {
    if (connection is! Map<String, dynamic>) return const <dynamic>[];
    final edges = connection['edges'];
    return edges is List<dynamic> ? edges : const <dynamic>[];
  }

  Future<CadreRoster> _fetch(
    Map<String, dynamic> variables,
    int limit,
  ) async {
    final decoded = await _post(<String, dynamic>{
      'query': _query,
      'variables': variables,
    });

    final media = (decoded['data'] as Map<String, dynamic>?)?['Media']
        as Map<String, dynamic>?;

    if (media == null) {
      throw const CadreRosterException('No anime matched that search.');
    }

    final titleMap = (media['title'] as Map<String, dynamic>?) ?? const {};
    final title = (titleMap['english'] as String?)?.trim().isNotEmpty == true
        ? (titleMap['english'] as String).trim()
        : ((titleMap['romaji'] as String?) ?? 'Unknown anime');

    // Page 1 then page 2, in that order, so the [ROLE, FAVOURITES_DESC] sort
    // carries across the join: main cast first, background last.
    final edges = <dynamic>[
      ..._edgesOf(media['p1']),
      ..._edgesOf(media['p2']),
    ];

    final seen = <int>{};
    final fighters = <CadreFighter>[];
    for (final edge in edges) {
      if (edge is! Map<String, dynamic>) continue;
      final fighter = CadreFighter.fromAniListEdge(edge);
      if (fighter.id < 0) continue;
      if (fighter.imageUrl.isEmpty) continue;
      if (!seen.add(fighter.id)) continue;
      fighters.add(fighter);
    }

    if (fighters.isEmpty) {
      throw CadreRosterException(
        '$title has no usable character art on AniList. Try another anime.',
      );
    }

    // Trim before scoring, not after — withLocalPower normalises across the
    // list it is handed, so the population it sees has to be the population
    // that ends up in the deck.
    final capped =
        fighters.length > limit ? fighters.sublist(0, limit) : fighters;

    // Favourites first, then the hand-ranked table overrides whoever it
    // knows about. Anything unranked keeps its favourites score, so adding an
    // anime to the table can only improve a cast, never break one.
    final scored = CadreFighter.withLocalPower(capped);
    final ranked = CadreFighter.withRankedPower(
      scored,
      CadreRankings.forTitle(title),
    );

    // Role fit last, and separately: power says how strong someone is, this
    // says what they are for. The two tables cover different casts on purpose
    // and neither depends on the other.
    final placed = CadreFighter.withRoleAffinity(
      ranked,
      CadreAffinity.forTitle(title),
    );

    final roster = CadreRoster(
      animeId: (media['id'] as num?)?.toInt() ?? -1,
      title: title,
      fighters: placed,
    );

    if (roster.animeId > 0) {
      _memoryCache[roster.animeId] = roster;
    }
    return roster;
  }

  void clearCache() => _memoryCache.clear();
}
