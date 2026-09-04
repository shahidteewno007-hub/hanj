import 'cadre_fighter.dart';

/// One or more anime casts drafted from together.
///
/// Power is normalised inside each [CadreRoster] before it ever reaches a
/// pool, so a crossover doesn't let one franchise's favourite counts flatten
/// another's cast. Every anime brings its own full spread.
class CadrePool {
  final List<CadreRoster> rosters;

  const CadrePool(this.rosters);

  const CadrePool.empty() : rosters = const <CadreRoster>[];

  factory CadrePool.single(CadreRoster roster) => CadrePool(<CadreRoster>[roster]);

  List<CadreFighter> get fighters =>
      <CadreFighter>[for (final r in rosters) ...r.fighters];

  int get length => rosters.fold<int>(0, (sum, r) => sum + r.length);

  bool get isEmpty => rosters.isEmpty;
  bool get isNotEmpty => rosters.isNotEmpty;
  bool get isCrossover => rosters.length > 1;

  List<int> get animeIds => <int>[for (final r in rosters) r.animeId];

  String get title {
    if (rosters.isEmpty) return 'Empty pool';
    if (rosters.length == 1) return rosters.first.title;
    if (rosters.length == 2) {
      return '${rosters[0].title} \u00D7 ${rosters[1].title}';
    }
    return '${rosters.length}-anime crossover';
  }

  bool contains(int animeId) => rosters.any((r) => r.animeId == animeId);

  CadrePool add(CadreRoster roster) {
    if (contains(roster.animeId)) return this;
    return CadrePool(<CadreRoster>[...rosters, roster]);
  }

  CadrePool remove(int animeId) => CadrePool(
        <CadreRoster>[for (final r in rosters) if (r.animeId != animeId) r],
      );
}
