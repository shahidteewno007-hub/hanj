// Tier lists: saving them on this device.
//
// Each list is one SharedPreferences entry (`hanj.tierList.<id>`), with an
// index of ids beside them, so an autosave rewrites one list, not all of
// them. On web that is the browser's localStorage for this site.
//
// Device only, on purpose: a Firestore collection for these would need a
// new rule in firestore.rules and a rules deploy, which is Shahid's step.
// Until then a list lives where it was made, and clearing the app's data
// (or the browser's site data) clears it.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tier_list_model.dart';

class TierListStore {
  TierListStore._();
  static final instance = TierListStore._();

  static const _indexKey = 'hanj.tierLists.index';
  static const _listPrefix = 'hanj.tierList.';

  /// The most lists kept. Saving one more past this refuses, rather than
  /// quietly dropping someone's oldest list.
  static const maxLists = 60;

  /// Lists as last saved, newest first; null until [loadAll] has run.
  List<TierList>? _lists;

  // Writes run one at a time, in order, so a quick run of autosaves can't
  // finish out of order and leave an older version on disk.
  Future<void> _queue = Future.value();

  static final _rand = math.Random();

  // Saves and deletes asked for and not yet finished.
  int _pending = 0;

  /// Completes once every save and delete asked for so far has finished:
  /// at once when none is running.
  Future<void> get idle => _pending == 0 ? Future<void>.value() : _queue;

  /// Tests only: forget what was loaded, so the next [loadAll] reads the
  /// (mock) preferences again.
  @visibleForTesting
  void forgetLoaded() => _lists = null;

  /// A new list id: time plus a little randomness, base 36.
  static String freshId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_rand.nextInt(1 << 20).toRadixString(36)}';

  /// Every saved list, most recently edited first. Never throws: an
  /// unreadable entry is skipped and logged.
  Future<List<TierList>> loadAll() async {
    final cached = _lists;
    if (cached != null) return List.of(cached);
    final out = <TierList>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in _index(prefs)) {
        final raw = prefs.getString('$_listPrefix$id');
        if (raw == null) continue;
        try {
          final list = TierList.fromJson(jsonDecode(raw));
          if (list != null) out.add(list);
        } catch (e) {
          debugPrint('Tier list $id unreadable: $e');
        }
      }
    } catch (e) {
      debugPrint('Tier lists could not load: $e');
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _lists = out;
    return List.of(out);
  }

  /// Saves [list], adding it if it's new. Returns false when it couldn't be
  /// written, or when it's new and [maxLists] are already saved.
  Future<bool> save(TierList list) => _enqueue(() => _save(list));

  Future<bool> _enqueue(Future<bool> Function() job) {
    _pending++;
    final done = _queue.then((_) => job()).whenComplete(() => _pending--);
    _queue = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<bool> _save(TierList list) async {
    try {
      final all = await loadAll();
      final isNew = !all.any((l) => l.id == list.id);
      if (isNew && all.length >= maxLists) return false;
      final prefs = await SharedPreferences.getInstance();
      final ok = await prefs.setString('$_listPrefix${list.id}', jsonEncode(list.toJson()));
      if (!ok) return false;
      if (isNew) {
        final ids = _index(prefs)..add(list.id);
        await prefs.setStringList(_indexKey, ids);
      }
      final kept = _lists ?? [];
      kept.removeWhere((l) => l.id == list.id);
      kept.insert(0, list);
      _lists = kept;
      return true;
    } catch (e) {
      debugPrint('Tier list save failed: $e');
      return false;
    }
  }

  /// Deletes the list with [id]. Returns false when it couldn't be removed.
  Future<bool> delete(String id) => _enqueue(() => _delete(id));

  Future<bool> _delete(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_listPrefix$id');
      final ids = _index(prefs)..remove(id);
      await prefs.setStringList(_indexKey, ids);
      _lists?.removeWhere((l) => l.id == id);
      return true;
    } catch (e) {
      debugPrint('Tier list delete failed: $e');
      return false;
    }
  }

  /// Characters on the other saved lists (every list but [exceptId]),
  /// leaving out [skip]: those on the most lists first, then those from the
  /// most recently edited (round nine's quick picks). Reads only what's
  /// saved on the device; never throws.
  Future<List<TierCharacter>> charactersElsewhere(String exceptId,
      {Set<int> skip = const {}, int max = 18}) async {
    final lists = await loadAll();
    final uses = <int, int>{};
    final seen = <int, TierCharacter>{}; // most recently edited list first
    for (final l in lists) {
      if (l.id == exceptId) continue;
      for (final c in l.characters.values) {
        if (skip.contains(c.id)) continue;
        uses[c.id] = (uses[c.id] ?? 0) + 1;
        seen.putIfAbsent(c.id, () => c);
      }
    }
    final ids = seen.keys.toList();
    final order = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    ids.sort((a, b) {
      final d = uses[b]!.compareTo(uses[a]!);
      return d != 0 ? d : order[a]!.compareTo(order[b]!);
    });
    return [for (final id in ids.take(max)) seen[id]!];
  }

  List<String> _index(SharedPreferences prefs) =>
      List.of(prefs.getStringList(_indexKey) ?? const <String>[]);
}
