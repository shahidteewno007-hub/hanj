import 'dart:math' as math;

import '../data/cadre_rankings.dart';

/// Cast role as reported by AniList for a given anime.
enum CadreRole { main, supporting, background }

extension CadreRoleLabel on CadreRole {
  String get label {
    switch (this) {
      case CadreRole.main:
        return 'MAIN';
      case CadreRole.supporting:
        return 'SUPPORTING';
      case CadreRole.background:
        return 'BACKGROUND';
    }
  }

  static CadreRole fromApi(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'MAIN':
        return CadreRole.main;
      case 'BACKGROUND':
        return CadreRole.background;
      default:
        return CadreRole.supporting;
    }
  }
}

/// Squad slot keys. Kept as plain strings so the enrichment payload
/// coming back from the Cloud Function can key straight into them.
class CadreSlots {
  static const captain = 'captain';
  static const vice = 'vice';
  static const tank = 'tank';
  static const healer = 'healer';
  static const support = 'support';

  static const all = <String>[captain, vice, tank, healer, support];

  static const labels = <String, String>{
    captain: 'Captain',
    vice: 'Vice',
    tank: 'Tank',
    healer: 'Healer',
    support: 'Support',
  };
}

/// One drafted character.
///
/// [power] is filled in by [CadreFighter.withLocalPower] from AniList
/// favourites, and later overwritten by the enrichment pass. [roleAffinity]
/// and [tags] stay at their neutral defaults until enrichment runs, so Squad
/// mode still works before any AI call has ever happened.
class CadreFighter {
  final int id;
  final String name;
  final String imageUrl;
  final int favourites;
  final CadreRole role;
  final String? gender;

  final int power;
  final List<String> tags;
  final Map<String, double> roleAffinity;
  final String? oneLiner;

  /// True once the roster has been through the enrichment pass.
  final bool enriched;

  const CadreFighter({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.favourites,
    required this.role,
    this.gender,
    this.power = 0,
    this.tags = const <String>[],
    this.roleAffinity = defaultAffinity,
    this.oneLiner,
    this.enriched = false,
  });

  /// Neutral affinity used before enrichment. Every slot is equally viable,
  /// so a pre-enrichment Squad match still resolves sensibly.
  static const Map<String, double> defaultAffinity = <String, double>{
    CadreSlots.captain: 0.75,
    CadreSlots.vice: 0.75,
    CadreSlots.tank: 0.75,
    CadreSlots.healer: 0.75,
    CadreSlots.support: 0.75,
  };

  factory CadreFighter.fromAniListEdge(Map<String, dynamic> edge) {
    final node = (edge['node'] as Map<String, dynamic>?) ?? const {};
    final name = (node['name'] as Map<String, dynamic>?) ?? const {};
    final image = (node['image'] as Map<String, dynamic>?) ?? const {};

    return CadreFighter(
      id: (node['id'] as num?)?.toInt() ?? -1,
      name: (name['full'] as String?)?.trim().isNotEmpty == true
          ? (name['full'] as String).trim()
          : 'Unknown',
      imageUrl: (image['large'] as String?) ?? (image['medium'] as String?) ?? '',
      favourites: (node['favourites'] as num?)?.toInt() ?? 0,
      role: CadreRoleLabel.fromApi(edge['role'] as String?),
      gender: node['gender'] as String?,
    );
  }

  CadreFighter copyWith({
    int? power,
    List<String>? tags,
    Map<String, double>? roleAffinity,
    String? oneLiner,
    bool? enriched,
  }) {
    return CadreFighter(
      id: id,
      name: name,
      imageUrl: imageUrl,
      favourites: favourites,
      role: role,
      gender: gender,
      power: power ?? this.power,
      tags: tags ?? this.tags,
      roleAffinity: roleAffinity ?? this.roleAffinity,
      oneLiner: oneLiner ?? this.oneLiner,
      enriched: enriched ?? this.enriched,
    );
  }

  /// Effective power in a given Squad slot.
  double powerInSlot(String slot) {
    final affinity = roleAffinity[slot] ?? 0.5;
    return power * affinity;
  }

  /// Assigns [power] across a pool.
  ///
  /// Favourites are log-scaled (a 40,000-favourite lead over 4,000 should not
  /// be ten cards' worth of gap) then normalised inside this pool, so a cast of
  /// obscure characters still spreads across the full range instead of all
  /// landing at the bottom.
  ///
  /// Cast role deliberately does *not* adjust the result any more. It used to
  /// add 9 to leads and take 6 from background characters, on the theory that
  /// leads outperform their popularity. The theory was backwards: a character
  /// is billed as a lead *because* they are popular, so the two signals are
  /// the same one counted twice. On a real One Piece cast it put Chopper and
  /// Usopp in Apex while Whitebeard, Kaido, Roger and Garp sat in Elite.
  static List<CadreFighter> withLocalPower(List<CadreFighter> pool) {
    if (pool.isEmpty) return pool;

    final scores = pool.map((f) => math.log(f.favourites + 1)).toList();
    final minScore = scores.reduce(math.min);
    final maxScore = scores.reduce(math.max);
    final span = maxScore - minScore;

    return <CadreFighter>[
      for (var i = 0; i < pool.length; i++)
        pool[i].copyWith(
          power: _scoreFor(
            span < 0.0001 ? 0.5 : (scores[i] - minScore) / span,
          ),
        ),
    ];
  }

  /// Lowest and highest power any character can be scored at.
  ///
  /// The span used to stop at 90, which made Apex (90+) unreachable without
  /// the lead bonus — so the top tier was in practice reserved for main cast.
  /// A real 45-99 range lets a well-known supporting character earn it.
  static const double minPower = 45.0;
  static const double maxPower = 99.0;

  static int _scoreFor(double normalised) {
    final value = minPower + ((maxPower - minPower) * normalised);
    return value.clamp(minPower, maxPower).round();
  }

  /// Overlays hand-ranked power onto a scored pool.
  ///
  /// A character found in [ranked] takes that value and is marked enriched;
  /// everyone else keeps the favourites-derived score they came in with. The
  /// two live on the same 45-99 scale on purpose, so a partly ranked cast is
  /// still internally comparable rather than two scales stapled together.
  static List<CadreFighter> withRankedPower(
    List<CadreFighter> pool,
    Map<String, int>? ranked,
  ) {
    if (ranked == null || ranked.isEmpty) return pool;

    return <CadreFighter>[
      for (final fighter in pool)
        () {
          final override = ranked[CadreRankings.normalise(fighter.name)];
          if (override == null) return fighter;
          return fighter.copyWith(power: override, enriched: true);
        }(),
    ];
  }

  /// Overlays hand-assigned role fit onto a pool.
  ///
  /// Runs after [withRankedPower] and is independent of it: a character can be
  /// ranked without being typed, or typed without being ranked. Anyone missing
  /// from [affinity] keeps the flat default, which
  /// [CadreSquadMatch.contribution] reads as "no fit data" and skips, so an
  /// untyped character plays exactly as they did before this table existed.
  ///
  /// Note this does *not* set `enriched`. That flag means "has a hand-ranked
  /// power value" and belongs to [withRankedPower] alone — conflating the two
  /// is what made Squad quietly tax every ranked character.
  static List<CadreFighter> withRoleAffinity(
    List<CadreFighter> pool,
    Map<String, Map<String, double>>? affinity,
  ) {
    if (affinity == null || affinity.isEmpty) return pool;

    return <CadreFighter>[
      for (final fighter in pool)
        () {
          final slots = affinity[CadreRankings.normalise(fighter.name)];
          if (slots == null) return fighter;
          return fighter.copyWith(roleAffinity: slots);
        }(),
    ];
  }

  @override
  String toString() => 'CadreFighter($name, power: $power, ${role.label})';
}

/// A pool of fighters drawn from one anime.
class CadreRoster {
  final int animeId;
  final String title;
  final List<CadreFighter> fighters;
  final bool enriched;

  const CadreRoster({
    required this.animeId,
    required this.title,
    required this.fighters,
    this.enriched = false,
  });

  bool get isEmpty => fighters.isEmpty;
  int get length => fighters.length;
}
