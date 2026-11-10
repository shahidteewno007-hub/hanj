// Tier lists, round nine: the board opens first and a tier is where you
// add; the picker for one tier, with its quick picks; Edit tiers; the
// Gauntlet's board and picture. Every screen is laid out on the CPH2573's
// 360x792 at 1.0x, 1.3x and 2.0x text, as tier_list_layout_test.dart does
// for round seven's, and the new moves are walked through once.
//
// A release web build doesn't report a RenderFlex overflow; a widget test
// does, as an exception. No portrait has a picture here (no network in
// tests), so every face is drawn as its initials.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/core/theme/app_theme.dart';
import 'package:hanj/features/tier_list/tier_list_anilist.dart';
import 'package:hanj/features/tier_list/tier_list_editor_screen.dart';
import 'package:hanj/features/tier_list/tier_list_export_screen.dart';
import 'package:hanj/features/tier_list/tier_list_gauntlet.dart';
import 'package:hanj/features/tier_list/tier_list_home_screen.dart';
import 'package:hanj/features/tier_list/tier_list_model.dart';
import 'package:hanj/features/tier_list/tier_list_picker_screen.dart';
import 'package:hanj/features/tier_list/tier_list_store.dart';
import 'package:hanj/features/tier_list/tier_list_templates.dart';
import 'package:hanj/features/tier_list/tier_list_widgets.dart';
import 'package:hanj/widgets/hanko_seal.dart';
import 'package:shared_preferences/shared_preferences.dart';

TierCharacter _who(int i) => TierCharacter(
      id: i,
      name: i.isEven ? 'Gojo Satoru' : 'Monkey D. Luffy, King of the Pirates',
      mediaId: i % 3,
      mediaTitle: 'Jujutsu Kaisen: Shibuya Incident Arc part ${i % 3}',
      mediaColor: 0xFF5D8FE4,
    );

/// A list from [templateId] with [n] characters, [placed] of them in tiers.
TierList _sample(String templateId, {int n = 14, int placed = 12}) {
  final l = tierTemplateById(templateId)!.create(id: 'r9-$templateId', now: DateTime(2026, 11, 10));
  l.addCharacters([for (var i = 1; i <= n; i++) _who(i)]);
  for (var i = 1; i <= placed; i++) {
    l.move(i, toTierId: l.tiers[i % l.tiers.length].id);
  }
  return l;
}

List<String> _drain(WidgetTester tester) {
  final out = <String>[];
  for (Object? e = tester.takeException(); e != null; e = tester.takeException()) {
    out.add(e.toString().split('\n').first.trim());
  }
  return out;
}

void _phone(WidgetTester tester, double textScale) {
  tester.view.physicalSize = const Size(1440, 3168);
  tester.view.devicePixelRatio = 4.0;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(theme: AppTheme.darkTheme, home: screen));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

/// Takes the tree down and lets any timer the screen started run out.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 16));
  _drain(tester);
}

/// A full gauntlet: a challenger and five opponents, one with a long name
/// and every anime title long. [verdict]: null (open), 'falls' (Phase 3) or
/// 'clear'.
TierList _gauntlet({String? verdict}) {
  final g = kGauntletTemplate.create(id: 'g-${verdict ?? 'open'}', now: DateTime(2026, 11, 10));
  const names = ['Naruto Uzumaki', 'Yuuji Itadori', 'Luffy Monkey', 'Satoru Gojou, the Strongest Sorcerer of Today', 'Gokuu Son', 'Saitama'];
  for (var i = 0; i < g.tiers.length; i++) {
    g.setSlot(
      g.tiers[i].id,
      TierCharacter(
        id: 100 + i,
        name: names[i],
        mediaId: i,
        mediaTitle: 'A long anime title: The Final Season, part $i',
        mediaColor: 0xFF5D8FE4,
      ),
    );
  }
  g.title = gauntletTitleFor(g.challenger);
  if (verdict == 'falls') g.setVerdict(g.phases[2].id);
  if (verdict == 'clear') g.setVerdict(TierList.verdictClear);
  return g;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TierListStore.instance.forgetLoaded();
  });

  if (TierListSwitches.gauntlet) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('the gauntlet board, empty and with each answer, ${scale}x text', (tester) async {
        _phone(tester, scale);
        await _show(tester, TierGauntletScreen(list: kGauntletTemplate.create(id: 'g-new', now: DateTime(2026, 11, 10))));
        expect(_drain(tester), isEmpty, reason: 'a new gauntlet');
        expect(find.text('Pick the challenger'), findsOneWidget);
        for (final v in [null, 'falls', 'clear']) {
          await _show(tester, TierGauntletScreen(key: ValueKey(v), list: _gauntlet(verdict: v)));
          expect(_drain(tester), isEmpty, reason: 'a full gauntlet, answer $v');
        }
        await _finish(tester);
      });
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('the gauntlet picture, with each answer, ${scale}x text', (tester) async {
        _phone(tester, scale);
        for (final v in [null, 'falls', 'clear']) {
          await _show(tester, TierListExportScreen(key: ValueKey(v), list: _gauntlet(verdict: v)));
          expect(find.text('Share your gauntlet'), findsOneWidget);
          expect(find.text('Names under faces'), findsNothing, reason: 'a gauntlet always prints its names');
          expect(_drain(tester), isEmpty, reason: 'the picture, answer $v');
        }
        await _finish(tester);
      });

      testWidgets('the start screen with the Gauntlet card and a saved gauntlet, ${scale}x text', (tester) async {
        _phone(tester, scale);
        final saved = _gauntlet(verdict: 'falls');
        SharedPreferences.setMockInitialValues({
          'hanj.tierLists.index': [saved.id],
          'hanj.tierList.${saved.id}': jsonEncode(saved.toJson()),
        });
        await _show(tester, const TierListHomeScreen());
        expect(_drain(tester), isEmpty);
        expect(find.text('How far does Naruto Uzumaki go?'), findsOneWidget);
        expect(find.textContaining('Falls at Phase 3'), findsOneWidget);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('How far does your pick go?', skipOffstage: false), findsOneWidget);
        expect(_drain(tester), isEmpty, reason: 'the Gauntlet card');
        await _finish(tester);
      });
    }

    for (final reduce in [false, true]) {
      testWidgets('marking a phase ${reduce ? 'with Remove animations: the seal just appears' : 'presses the seal in'}',
          (tester) async {
        _phone(tester, 1.0);
        final g = _gauntlet();
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: TierGauntletScreen(list: g),
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 400));
        final box = find.bySemanticsLabel(RegExp(r'^Phase 3: open'));
        await tester.ensureVisible(box);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(box);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));
        double scale() => tester
            .widget<ScaleTransition>(find
                .ancestor(
                  of: find.byWidgetPredicate((w) => w is HankoSeal && w.label == 'Falls'),
                  matching: find.byType(ScaleTransition),
                )
                .first)
            .scale
            .value;
        if (reduce) {
          expect(scale(), 1.0, reason: 'no motion: at rest at once');
        } else {
          expect(scale(), greaterThan(1.05), reason: '30 ms in, the seal is still falling onto the paper');
        }
        await tester.pump(const Duration(milliseconds: 400));
        expect(scale(), 1.0, reason: 'pressed in');
        expect(_drain(tester), isEmpty);
        await _finish(tester);
      });
    }

    testWidgets('a gauntlet: pick the challenger, then mark where they fall, open it again, clear them all',
        (tester) async {
      _phone(tester, 1.0);
      // Another saved list gives the picker faces to pick from, no search.
      final other = _sample('strongest-mc');
      SharedPreferences.setMockInitialValues({
        'hanj.tierLists.index': [other.id],
        'hanj.tierList.${other.id}': jsonEncode(other.toJson()),
      });
      final g = _gauntlet();
      g.clearTier(g.challengerTier!.id);
      g.title = gauntletTitleFor(null);
      await _show(tester, TierGauntletScreen(list: g));

      await tester.tap(find.bySemanticsLabel('Challenger: pick one'));
      await _settle(tester);
      expect(find.bySemanticsLabel('Pick for Challenger'), findsOneWidget);
      final gojo = find.bySemanticsLabel(RegExp(r'^Gojo Satoru, .*not picked$'), skipOffstage: false).first;
      await tester.ensureVisible(gojo);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(gojo);
      await _settle(tester);
      expect(g.challenger?.name, 'Gojo Satoru');
      expect(g.title, 'How far does Gojo Satoru go?', reason: 'the gauntlet names itself after its challenger');

      final third = g.phases[2];
      final box = find.bySemanticsLabel(RegExp(r'^Phase 3: open'));
      await tester.ensureVisible(box);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(box);
      await _settle(tester);
      expect(g.verdict, third.id);
      expect(g.markOf(2), GauntletMark.beats);
      expect(g.markOf(4), GauntletMark.notReached);
      expect(find.text('Falls at Phase 3'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Clears all five: not reached'), skipOffstage: false), findsOneWidget,
          reason: 'past the fall, the finish is never reached');

      await tester.tap(find.bySemanticsLabel(RegExp(r'^Phase 3: Gojo Satoru falls here')));
      await _settle(tester);
      expect(g.verdict, isNull, reason: 'a second tap leaves it open');

      final finish = find.bySemanticsLabel(RegExp(r'^Clears all five: open'));
      await tester.ensureVisible(finish);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(finish);
      await _settle(tester);
      expect(g.clearsAll, isTrue);
      expect(_drain(tester), isEmpty);
      await _finish(tester);
    });
  }

  // The board at 2.0x too. Pickers stop at 1.3x, as round seven's test does: the test font is
  // about twice Jost's width, so at 2.0x their Anime | Characters tabs overrun 360 dp in the test
  // and not on a phone.
  for (final scale in [1.0, 1.3, 2.0]) {
    if (TierListSwitches.tapToFill) {
      testWidgets('a new list opens on its board, every tier with its add slot, ${scale}x text', (tester) async {
        _phone(tester, scale);
        final list = tierTemplateById('strongest-mc')!.create(id: 'fresh', now: DateTime(2026, 11, 10));
        await _show(tester, TierListEditorScreen(list: list));
        expect(_drain(tester), isEmpty, reason: 'the empty board');
        expect(find.text('Add characters'), findsWidgets, reason: 'the board, not the picker');
        expect(find.textContaining('Add to Multiverse level', skipOffstage: false), findsOneWidget);
        await _finish(tester);
      });
    }

    if (TierListSwitches.editTiers) {
      testWidgets('Edit tiers: remove a tier and Undo it, move one, ${scale}x text', (tester) async {
        _phone(tester, scale);
        final list = _sample('anime-dads');
        String places() => [for (final t in list.tiers) '${t.id}:${t.characterIds.join(",")}'].join(' ');
        final before = places();
        final topId = list.tiers.first.id;
        final second = list.tiers[1];
        await _show(tester, TierListEditorScreen(list: list));
        // From the top bar's menu (the button under the board is off screen
        // at large text).
        await tester.tap(find.byTooltip('More'));
        await _settle(tester);
        await tester.tap(find.text('Edit tiers').last);
        await _settle(tester);
        expect(find.text('Done'), findsOneWidget, reason: 'the top bar says Edit tiers, with Done');
        expect(_drain(tester), isEmpty, reason: 'Edit tiers');

        // Remove the second tier: its characters go to unranked.
        final had = second.characterIds.length;
        expect(had, greaterThan(0));
        await tester.tap(find.byTooltip('Remove ${second.label}'));
        await _settle(tester);
        expect(list.tierById(second.id), isNull);
        expect(list.unranked.length, 2 + had);
        expect(find.text('Undo'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await _settle(tester);
        expect(places(), before, reason: 'Undo puts every place back');

        // Move the top tier down one.
        await tester.tap(find.byTooltip('Move ${list.tiers.first.label} down'));
        await _settle(tester);
        expect(list.tiers[1].id, topId);
        expect(_drain(tester), isEmpty, reason: 'after the moves');

        await tester.tap(find.text('Done'));
        await _settle(tester);
        expect(find.text('Done'), findsNothing);
        await _finish(tester);
      });

      testWidgets('the tier sheet saves as you type, and swiping it away keeps the name, ${scale}x text',
          (tester) async {
        _phone(tester, scale);
        final list = _sample('blank', n: 2, placed: 0);
        await _show(tester, TierListEditorScreen(list: list));
        // An unnamed tier's plate opens its sheet, to name it.
        final plate = find.bySemanticsLabel(RegExp(r'^Tier 1, unnamed\.'), skipOffstage: false).first;
        await tester.ensureVisible(plate);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(plate);
        await _settle(tester);
        expect(find.text('Edit tier'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Peak');
        await tester.pump();
        expect(list.tiers.first.label, 'Peak', reason: 'saved before Done');
        // Dismiss the sheet without Done.
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await _settle(tester);
        expect(list.tiers.first.label, 'Peak');
        expect(_drain(tester), isEmpty);
        await _finish(tester);
      });
    }
  }

  for (final scale in [1.0, 1.3]) {
    if (TierListSwitches.tapToFill) {
      testWidgets('tapping a tier opens the picker for it; picks land in that tier, ${scale}x text', (tester) async {
        _phone(tester, scale);
        final list = _sample('strongest-mc');
        final top = list.tiers.first;
        expect(list.unranked, [13, 14]);
        await _show(tester, TierListEditorScreen(list: list));
        final plate = find.bySemanticsLabel(RegExp('^${RegExp.escape(top.label)}\\.'), skipOffstage: false).first;
        await tester.ensureVisible(plate);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(plate);
        await _settle(tester);
        expect(find.bySemanticsLabel('Add to ${top.label}'), findsOneWidget, reason: 'the picker names its tier');
        expect(find.text('WAITING IN UNRANKED  ·  2', skipOffstage: false), findsOneWidget);
        expect(find.text('ANIME ON THIS LIST', skipOffstage: false), findsOneWidget);
        expect(_drain(tester), isEmpty, reason: 'the picker for a tier');
        // Pick the one waiting at the end of the tray, then Add.
        final gojo = find.bySemanticsLabel(RegExp(r'^Gojo Satoru, .*not picked$'), skipOffstage: false).first;
        await tester.ensureVisible(gojo);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(gojo);
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('Add 1'));
        await _settle(tester);
        expect(list.tierById(top.id)!.characterIds.last, 14, reason: 'Gojo is at the end of the tapped tier');
        expect(list.unranked, [13]);
        expect(_drain(tester), isEmpty, reason: 'back on the board');
        await _finish(tester);
      });
    }

    testWidgets('the picker for one tier, with every quick pick, ${scale}x text', (tester) async {
      _phone(tester, scale);
      await _show(
        tester,
        TierCharacterPickerScreen(
          alreadyOnList: const {1},
          room: 40,
          ideas: TierSearchIdeas(characters: tierTemplateById('strongest-mc')!.characters),
          target: TierPickTarget(label: 'Bury him under the jail', pigment: TierPigment.at(8)),
          waiting: [for (var i = 2; i <= 6; i++) _who(i)],
          listAnime: const [
            TierAnime(id: 113415, title: 'JUJUTSU KAISEN Season 2: Shibuya Incident and more'),
            TierAnime(id: 21, title: 'ONE PIECE'),
          ],
          fromOtherLists: [for (var i = 7; i <= 20; i++) _who(i)],
        ),
      );
      expect(_drain(tester), isEmpty);
      expect(find.bySemanticsLabel('Add to Bury him under the jail'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('one pick for a slot, with who holds it now, ${scale}x text', (tester) async {
      _phone(tester, scale);
      await _show(
        tester,
        TierCharacterPickerScreen(
          alreadyOnList: const {1, 2},
          room: 1,
          target: TierPickTarget(label: 'Phase 3', pigment: TierPigment.at(3)),
          single: true,
          current: _who(1),
          fromOtherLists: [for (var i = 7; i <= 12; i++) _who(i)],
        ),
      );
      expect(_drain(tester), isEmpty);
      expect(find.bySemanticsLabel('Pick for Phase 3'), findsOneWidget);
      expect(find.text('Now: Monkey D. Luffy, King of the Pirates'), findsOneWidget);
      expect(find.bySemanticsLabel('Remove'), findsOneWidget);
      await _finish(tester);
    });
  }
}
