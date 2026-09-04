import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/cadre_stats.dart';

/// Local persistence for the Cadre record and the saved pool.
///
/// Deliberately narrow: when Cadre moves onto the Hanj profile this becomes a
/// Firestore read/write behind the same four methods, and nothing calling it
/// has to change.
class CadreStatsService {
  CadreStatsService._();
  static final CadreStatsService instance = CadreStatsService._();

  static const String _statsKey = 'cadre_stats_v1';
  /// Pools are stored per slot: 'solo' holds one anime, 'crossover' holds
  /// two or more. They are independent, so switching modes doesn't cost you
  /// the other one's selection.
  static const String _poolKeyPrefix = 'cadre_pool_v2_';

  /// Which pool slot the lobby was last set to.
  static const String _modeKey = 'cadre_mode_v1';

  CadreStats _cached = CadreStats.empty;
  bool _loaded = false;

  CadreStats get cached => _cached;

  Future<CadreStats> load() async {
    if (_loaded) return _cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_statsKey);
      if (raw != null) {
        _cached = CadreStats.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      _cached = CadreStats.empty;
    }
    _loaded = true;
    return _cached;
  }

  Future<void> save(CadreStats stats) async {
    _cached = stats;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_statsKey, jsonEncode(stats.toJson()));
    } catch (_) {
      // Record stays in memory for this session; not worth interrupting play.
    }
  }

  Future<void> reset() => save(CadreStats.empty);

  Future<String> loadActiveSlot() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_modeKey) ?? 'solo';
    } catch (_) {
      return 'solo';
    }
  }

  Future<void> saveActiveSlot(String slot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, slot);
    } catch (_) {
      // Falls back to solo next launch.
    }
  }

  Future<List<int>> loadPoolIds(String slot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('$_poolKeyPrefix$slot') ??
          const <String>[];
      return <int>[
        for (final s in raw)
          if (int.tryParse(s) != null) int.parse(s),
      ];
    } catch (_) {
      return const <int>[];
    }
  }

  Future<void> savePoolIds(String slot, List<int> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        '$_poolKeyPrefix$slot',
        <String>[for (final id in ids) '$id'],
      );
    } catch (_) {
      // Pool falls back to the default next launch.
    }
  }
}
