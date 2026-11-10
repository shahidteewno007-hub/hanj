// Tier lists (round seven): the list's rules, the templates and the tier
// colours.
//
// The model promises that every character on a list sits in exactly one
// place (a tier or the unranked tray), once, whatever edits are made, and
// that a saved list always reads back, repaired if it has to be. The
// templates must make lists the editor can show, and every tier colour must
// print its label legibly and stay clear of the seal's coral.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/core/theme/app_theme.dart';
import 'package:hanj/features/tier_list/tier_list_model.dart';
import 'package:hanj/features/tier_list/tier_list_templates.dart';
import 'package:hanj/features/tier_list/tier_list_widgets.dart';

TierCharacter _c(int id) => TierCharacter(id: id, name: 'Character $id', mediaId: id % 3, mediaTitle: 'Anime ${id % 3}');

TierList _list({int tiers = 3}) => TierList(
      id: 'l',
      title: 'Test',
      tiers: [for (var i = 0; i < tiers; i++) Tier(id: 't$i', label: 'T$i', pigment: i)],
      createdAt: DateTime(2026, 11, 3),
    );

/// Every character appears exactly once across the tiers and the tray, and
/// nowhere else.
void _expectConsistent(TierList l) {
  final placed = [for (final t in l.tiers) ...t.characterIds, ...l.unranked];
  expect(placed.toSet().length, placed.length, reason: 'someone is in two places');
  expect(placed.toSet(), l.characters.keys.toSet(), reason: 'places and characters disagree');
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('adding', () {
    test('new picks wait in the tray, duplicates are skipped', () {
      final l = _list();
      expect(l.addCharacters([_c(1), _c(2), _c(1)]), 2);
      expect(l.unranked, [1, 2]);
      expect(l.addCharacters([_c(2), _c(3)]), 1);
      expect(l.unranked, [1, 2, 3]);
      _expectConsistent(l);
    });

    test('stops at the most a list holds', () {
      final l = _list();
      final added = l.addCharacters([for (var i = 0; i < TierList.maxCharacters + 5; i++) _c(i)]);
      expect(added, TierList.maxCharacters);
      expect(l.isFull, isTrue);
      expect(l.addCharacters([_c(9999)]), 0);
      _expectConsistent(l);
    });
  });

  group('moving', () {
    test('into a tier, to its end or at an index', () {
      final l = _list()..addCharacters([_c(1), _c(2), _c(3)]);
      expect(l.move(1, toTierId: 't0'), isTrue);
      expect(l.move(2, toTierId: 't0'), isTrue);
      expect(l.move(3, toTierId: 't0', index: 0), isTrue);
      expect(l.tiers[0].characterIds, [3, 1, 2]);
      expect(l.unranked, isEmpty);
      _expectConsistent(l);
    });

    test('within a tier, the index counts after taking them out', () {
      final l = _list()..addCharacters([_c(1), _c(2), _c(3), _c(4)]);
      for (final id in [1, 2, 3, 4]) {
        l.move(id, toTierId: 't1');
      }
      // 1 to the place after 3: [2, 3, 1, 4].
      expect(l.move(1, toTierId: 't1', index: 2), isTrue);
      expect(l.tiers[1].characterIds, [2, 3, 1, 4]);
      // Same place again is no move.
      expect(l.move(1, toTierId: 't1', index: 2), isFalse);
      _expectConsistent(l);
    });

    test('back to the tray, and unknown targets refused', () {
      final l = _list()..addCharacters([_c(1)]);
      l.move(1, toTierId: 't2');
      expect(l.move(1), isTrue);
      expect(l.unranked, [1]);
      expect(l.move(1, toTierId: 'nope'), isFalse);
      expect(l.move(42, toTierId: 't0'), isFalse);
      _expectConsistent(l);
    });

    test('nudge steps along a tier and stops at the ends', () {
      final l = _list()..addCharacters([_c(1), _c(2), _c(3)]);
      for (final id in [1, 2, 3]) {
        l.move(id, toTierId: 't0');
      }
      expect(l.nudge(1, -1), isFalse);
      expect(l.nudge(1, 1), isTrue);
      expect(l.tiers[0].characterIds, [2, 1, 3]);
      expect(l.nudge(3, 1), isFalse);
      _expectConsistent(l);
    });

    test('shift: the tray is the row below the bottom tier', () {
      final l = _list()..addCharacters([_c(1)]);
      // Up from the tray lands in the bottom tier.
      expect(l.shift(1, -1), isTrue);
      expect(l.tierOf(1)?.id, 't2');
      expect(l.shift(1, -1), isTrue);
      expect(l.shift(1, -1), isTrue);
      expect(l.tierOf(1)?.id, 't0');
      // Nothing above the top tier.
      expect(l.shift(1, -1), isFalse);
      // Down from the bottom tier goes back to the tray, and no further.
      l.move(1, toTierId: 't2');
      expect(l.shift(1, 1), isTrue);
      expect(l.unranked, [1]);
      expect(l.shift(1, 1), isFalse);
      _expectConsistent(l);
    });

    test('shift keeps about the same place in the row', () {
      final l = _list()..addCharacters([_c(1), _c(2), _c(3), _c(4)]);
      for (final id in [1, 2, 3]) {
        l.move(id, toTierId: 't1');
      }
      l.move(4, toTierId: 't0');
      expect(l.shift(3, -1), isTrue); // from index 2 of t1
      expect(l.tiers[0].characterIds, [4, 3]); // clamped to t0's end
      _expectConsistent(l);
    });
  });

  group('removing', () {
    test('a character leaves every place', () {
      final l = _list()..addCharacters([_c(1), _c(2)]);
      l.move(1, toTierId: 't0');
      expect(l.remove(1), isTrue);
      expect(l.remove(1), isFalse);
      expect(l.contains(1), isFalse);
      _expectConsistent(l);
    });

    test('unrankAll keeps the tiers and fills the tray', () {
      final l = _list()..addCharacters([_c(1), _c(2), _c(3)]);
      l.move(1, toTierId: 't0');
      l.move(2, toTierId: 't2');
      l.unrankAll();
      expect(l.rankedCount, 0);
      expect(l.unranked.toSet(), {1, 2, 3});
      expect(l.tiers.length, 3);
      _expectConsistent(l);
    });
  });

  group('the anime on a list', () {
    test('counted all together, or only where the picture shows them', () {
      // _c gives ids 1 and 4 anime 1, and id 2 anime 2.
      final l = _list()..addCharacters([_c(1), _c(2), _c(4)]);
      l.move(1, toTierId: 't0');
      expect(l.mediaByUse().map((e) => e.key), [1, 2], reason: 'anime 1 has two, so it comes first');
      expect(l.mediaByUse(rankedOnly: true).map((e) => e.key), [1]);
      l.move(1);
      expect(l.mediaByUse(rankedOnly: true), isEmpty);
    });
  });

  group('tiers', () {
    test('deleting one sends its characters to the tray, in order; the last stays', () {
      final l = _list(tiers: 2)..addCharacters([_c(1), _c(2), _c(3)]);
      l.move(2, toTierId: 't0');
      l.move(3, toTierId: 't0');
      expect(l.removeTier('t0'), isTrue);
      expect(l.unranked, [1, 2, 3]);
      expect(l.removeTier('t1'), isFalse, reason: 'a list keeps at least one tier');
      _expectConsistent(l);
    });

    test('adding below a tier, up to the most a list holds, with fresh ids', () {
      final l = _list(tiers: 2);
      final t = l.addTier(afterTierId: 't0', label: 'New', pigment: 3);
      expect(t, isNotNull);
      expect(l.tiers.map((t) => t.label), ['T0', 'New', 'T1']);
      while (l.tiers.length < TierList.maxTiers) {
        l.addTier(label: '', pigment: 0);
      }
      expect(l.addTier(label: 'one too many', pigment: 0), isNull);
      expect(l.tiers.map((t) => t.id).toSet().length, l.tiers.length);
    });

    test('moving and renaming', () {
      final l = _list();
      expect(l.moveTier('t0', -1), isFalse);
      expect(l.moveTier('t0', 1), isTrue);
      expect(l.tiers.map((t) => t.id), ['t1', 't0', 't2']);
      l.renameTier('t1', '   God tier   ');
      expect(l.tierById('t1')!.label, 'God tier');
      l.renameTier('t1', 'x' * 40);
      expect(l.tierById('t1')!.label.length, TierList.maxLabelLength);
    });
  });

  group('saving', () {
    test('round-trips through JSON', () {
      final l = _list()..addCharacters([_c(1), _c(2), _c(3)]);
      l.move(1, toTierId: 't0');
      l.move(3, toTierId: 't0', index: 0);
      final back = TierList.fromJson(jsonDecode(jsonEncode(l.toJson())))!;
      expect(back.title, 'Test');
      expect(back.tiers.map((t) => t.characterIds), [
        [3, 1],
        <int>[],
        <int>[],
      ]);
      expect(back.unranked, [2]);
      expect(back.characters[1]!.mediaTitle, 'Anime 1');
      _expectConsistent(back);
    });

    test('a damaged save is repaired, not refused', () {
      final json = {
        'id': 'x',
        'title': 'Damaged',
        'tiers': [
          {'id': 'a', 'label': 'A', 'pigment': 0, 'characters': [1, 2, 99]},
          {'id': 'b', 'label': 'B', 'pigment': 1, 'characters': [2, 3]},
          'not a tier',
        ],
        'unranked': [3, 'x', 1],
        'characters': [
          {'id': 1, 'name': 'One'},
          {'id': 2, 'name': 'Two'},
          {'id': 3, 'name': 'Three'},
          {'id': 4, 'name': 'Four'},
          {'name': 'no id'},
        ],
      };
      final l = TierList.fromJson(json)!;
      expect(l.tiers.map((t) => t.characterIds), [
        [1, 2],
        [3],
      ]);
      // 4 had no place at all, so it waits in the tray.
      expect(l.unranked, [4]);
      _expectConsistent(l);
    });

    test('junk reads as nothing', () {
      expect(TierList.fromJson(null), isNull);
      expect(TierList.fromJson('a string'), isNull);
      expect(TierList.fromJson({'id': 'x', 'tiers': []}), isNull);
    });
  });

  group('templates', () {
    test('every template makes a list the editor can show', () {
      final ids = <String>{};
      for (final t in kTierTemplates) {
        expect(ids.add(t.id), isTrue, reason: 'duplicate template id ${t.id}');
        expect(t.tiers.length, inInclusiveRange(TierList.minTiers, TierList.maxTiers), reason: t.id);
        for (final label in t.tiers) {
          expect(label.length, lessThanOrEqualTo(TierList.maxLabelLength), reason: '${t.id}: $label');
        }
        final p = t.pigmentsOrRamp;
        expect(p.length, t.tiers.length, reason: '${t.id}: one colour per tier');
        for (final i in p) {
          expect(i, inInclusiveRange(0, TierPigment.all.length - 1), reason: t.id);
        }
        final l = t.create(id: 'x');
        expect(l.tiers.length, t.tiers.length);
        expect(l.title.length, lessThanOrEqualTo(TierList.maxTitleLength), reason: t.id);
        expect(tierTemplateById(t.id), same(t));
      }
    });

    test('every suggested tier name fits a tier', () {
      for (final scheme in kTierNameSchemes.entries) {
        for (final name in scheme.value) {
          expect(name.length, lessThanOrEqualTo(TierList.maxLabelLength), reason: '${scheme.key}: $name');
        }
      }
    });

    test('ramps give one colour per tier for every size a list can be', () {
      for (var n = 1; n <= TierList.maxTiers; n++) {
        expect(TierPigment.ramp(n).length, n);
      }
    });
  });

  group('round nine: filling a tier you tapped', () {
    test('new picks and ones waiting in the tray land at the tier’s end; placed ones stay', () {
      final l = _list()..addCharacters([_c(1), _c(2)]);
      l.move(2, toTierId: 't1');
      expect(l.addTo('t0', [_c(3), _c(1), _c(2), _c(4)]), 3);
      expect(l.tiers[0].characterIds, [3, 1, 4], reason: '2 is in t1 already, so it stays there');
      expect(l.tiers[1].characterIds, [2]);
      expect(l.unranked, isEmpty);
      expect(l.addTo('nope', [_c(5)]), 0);
      _expectConsistent(l);
    });

    test('stops adding new characters at the most a list holds, but still moves waiting ones', () {
      final l = _list()..addCharacters([for (var i = 0; i < TierList.maxCharacters; i++) _c(i)]);
      expect(l.addTo('t0', [_c(9999), _c(0)]), 1);
      expect(l.contains(9999), isFalse);
      expect(l.tiers[0].characterIds, [0]);
      _expectConsistent(l);
    });
  });

  group('round nine: a gauntlet’s slots and verdict', () {
    test('a slot holds one: the one it held leaves the list', () {
      final l = _list();
      expect(l.setSlot('t1', _c(1)), isTrue);
      expect(l.setSlot('t1', _c(1)), isFalse, reason: 'already there');
      expect(l.setSlot('t1', _c(2)), isTrue);
      expect(l.tiers[1].characterIds, [2]);
      expect(l.contains(1), isFalse);
      _expectConsistent(l);
    });

    test('someone already in another slot moves, and that slot empties', () {
      final l = _list()
        ..setSlot('t0', _c(1))
        ..setSlot('t1', _c(2));
      expect(l.setSlot('t2', _c(1)), isTrue);
      expect(l.tiers[0].characterIds, isEmpty);
      expect(l.tiers[2].characterIds, [1]);
      _expectConsistent(l);
    });

    test('the verdict stays with its slot when its opponent changes, and goes when the slot empties', () {
      final l = _list()
        ..setSlot('t0', _c(1))
        ..setSlot('t1', _c(2))
        ..setSlot('t2', _c(3));
      l.verdict = 't2';
      l.setSlot('t2', _c(4));
      expect(l.verdict, 't2');
      // Moving t2's opponent into t1 empties t2.
      l.setSlot('t1', _c(4));
      expect(l.verdict, isNull);
      l.verdict = 't1';
      expect(l.clearTier('t1'), 1);
      expect(l.verdict, isNull);
      l.verdict = TierList.verdictClear;
      l.remove(1);
      expect(l.verdict, TierList.verdictClear, reason: 'clearing every phase isn’t tied to one slot');
      _expectConsistent(l);
    });

    test('removing the verdict’s tier drops the verdict', () {
      final l = _list()..setSlot('t1', _c(1));
      l.verdict = 't1';
      expect(l.removeTier('t1'), isTrue);
      expect(l.verdict, isNull);
      _expectConsistent(l);
    });
  });

  group('round nine: undo, names and saves', () {
    test('restoreFrom undoes a tier’s removal exactly', () {
      final l = _list()..addCharacters([_c(1), _c(2), _c(3)]);
      l.move(1, toTierId: 't0');
      l.move(2, toTierId: 't0');
      l.move(3, toTierId: 't2');
      final before = jsonEncode(l.toJson()..remove('updatedAt'));
      final snapshot = TierList.fromJson(jsonDecode(jsonEncode(l.toJson())))!;
      l.removeTier('t0');
      expect(l.unranked, [1, 2]);
      l.restoreFrom(snapshot);
      expect(jsonEncode(l.toJson()..remove('updatedAt')), before);
      _expectConsistent(l);
    });

    test('an unnamed tier is called by its place', () {
      final l = _list()..renameTier('t1', '   ');
      expect(l.displayName(l.tiers[1]), 'Tier 2');
      expect(l.displayName(l.tiers[0]), 'T0');
    });

    test('a list without a verdict saves exactly as before round nine', () {
      final l = _list()..addCharacters([_c(1)]);
      final json = l.toJson();
      expect(json.containsKey('verdict'), isFalse);
      expect(json.keys, ['v', 'id', 'title', 'prompt', 'template', 'tiers', 'unranked', 'characters', 'createdAt', 'updatedAt']);
    });

    test('verdicts round-trip, and one naming a missing or empty tier is dropped', () {
      final l = _list()..setSlot('t1', _c(1));
      l.verdict = 't1';
      expect(TierList.fromJson(jsonDecode(jsonEncode(l.toJson())))!.verdict, 't1');
      l.verdict = TierList.verdictClear;
      expect(TierList.fromJson(jsonDecode(jsonEncode(l.toJson())))!.verdict, TierList.verdictClear);
      final json = jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>;
      expect(TierList.fromJson({...json, 'verdict': 't2'})!.verdict, isNull, reason: 't2 is empty');
      expect(TierList.fromJson({...json, 'verdict': 'gone'})!.verdict, isNull);
      expect(TierList.fromJson({...json, 'verdict': 7})!.verdict, isNull);
      expect(TierList.fromJson(json..remove('verdict'))!.verdict, isNull, reason: 'a save from before round nine');
    });

    test('the gauntlet template: a challenger and five phases, one colour each', () {
      final t = kGauntletTemplate;
      expect(t.tiers, ['Challenger', 'Phase 1', 'Phase 2', 'Phase 3', 'Phase 4', 'Phase 5']);
      expect(t.pigmentsOrRamp.length, t.tiers.length);
      expect(kTierTemplates.any((x) => x.id == t.id), isFalse, reason: 'it has its own card, not a shelf');
      final l = t.create(id: 'g');
      expect(l.tiers.length, 6);
      expect(l.verdict, isNull);
      if (TierListSwitches.gauntlet) expect(tierTemplateById(t.id), same(t));
    });
  });

  group('tier colours', () {
    test('every label prints at 4.5:1 or better on its colour', () {
      for (final p in TierPigment.all) {
        expect(_contrast(p.color, p.ink), greaterThanOrEqualTo(4.5), reason: p.name);
      }
    });

    test('no coloured tier sits within 25 degrees of the seal’s coral', () {
      final seal = HSVColor.fromColor(AppTheme.hankoCoral).hue;
      for (final p in TierPigment.all) {
        final hsv = HSVColor.fromColor(p.color);
        if (hsv.saturation < 0.2) continue; // ash and ink are greys, not hues
        final d = (hsv.hue - seal).abs();
        expect(d > 180 ? 360 - d : d, greaterThan(AppTheme.hankoTintHueGuard), reason: p.name);
      }
    });
  });
}
