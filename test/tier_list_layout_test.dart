// Tier lists (round seven): every tier-list screen lays out cleanly on the
// CPH2573's 360x792, at 1.0x and 1.3x text (the editor at 2.0x too), with
// the longest tier names and character names the feature will meet.
//
// A release web build doesn't report a RenderFlex overflow; a widget test
// does, as an exception. No portrait has a picture here (no network in
// tests), so every face is drawn as its initials.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/core/theme/app_theme.dart';
import 'package:hanj/features/tier_list/tier_list_editor_screen.dart';
import 'package:hanj/features/tier_list/tier_list_export_screen.dart';
import 'package:hanj/features/tier_list/tier_list_home_screen.dart';
import 'package:hanj/features/tier_list/tier_list_model.dart';
import 'package:hanj/features/tier_list/tier_list_picker_screen.dart';
import 'package:hanj/features/tier_list/tier_list_templates.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A list from [templateId] with fourteen characters, twelve of them placed.
TierList _sample(String templateId) {
  final l = tierTemplateById(templateId)!.create(id: 'sample-$templateId', now: DateTime(2026, 11, 3));
  l.addCharacters([
    for (var i = 1; i <= 14; i++)
      TierCharacter(
        id: i,
        name: i.isEven ? 'Gojo Satoru' : 'Monkey D. Luffy, King of the Pirates',
        mediaId: i % 4,
        mediaTitle: 'Jujutsu Kaisen: Shibuya Incident Arc part ${i % 4}',
        mediaColor: 0xFF5D8FE4,
      ),
  ]);
  for (var i = 1; i <= 12; i++) {
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

/// Takes the tree down and lets any timer the screen started run out, so
/// nothing is left pending when the test ends.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 16));
  _drain(tester);
}

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('start screen with a saved list, ${scale}x text', (tester) async {
      _phone(tester, scale);
      final saved = _sample('anime-dads');
      SharedPreferences.setMockInitialValues({
        'hanj.tierLists.index': [saved.id],
        'hanj.tierList.${saved.id}': jsonEncode(saved.toJson()),
      });
      await _show(tester, const TierListHomeScreen());
      expect(_drain(tester), isEmpty);
      expect(find.text('Best and worst anime dads'), findsOneWidget, reason: 'the saved list is shown');
      // Every shelf, scrolled into view.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 400));
      expect(_drain(tester), isEmpty);
      await _finish(tester);
    });

    testWidgets('picker before a search, ${scale}x text', (tester) async {
      _phone(tester, scale);
      await _show(
        tester,
        TierCharacterPickerScreen(
          alreadyOnList: const {},
          room: TierList.maxCharacters,
          ideas: TierSearchIdeas(
            characters: tierTemplateById('strongest-mc')!.characters,
            anime: tierTemplateById('cast')!.anime,
          ),
        ),
      );
      expect(_drain(tester), isEmpty);
      await _finish(tester);
    });

    testWidgets('export preview, ${scale}x text', (tester) async {
      _phone(tester, scale);
      await _show(tester, TierListExportScreen(list: _sample('strongest-mc')));
      expect(_drain(tester), isEmpty);
      await _finish(tester);
    });
  }

  for (final scale in [1.0, 1.3, 2.0]) {
    for (final id in ['strongest-mc', 'anime-dads', 'cast']) {
      testWidgets('editor, $id, ${scale}x text, and its two sheets', (tester) async {
        _phone(tester, scale);
        final list = _sample(id);
        await _show(tester, TierListEditorScreen(list: list));
        expect(_drain(tester), isEmpty, reason: 'the board');
        // The tiers keep most of the screen at every text size: the tray once
        // took 470 of 792 px at 2.0x, leaving the board 235.
        final board = tester.getRect(find.byType(ListView).first);
        expect(board.height, greaterThan(792 * 0.5), reason: 'the board is ${board.height} px tall');

        // A portrait's sheet: the one waiting in the tray, always on screen.
        await tester.tap(find.bySemanticsLabel(RegExp(r'^Gojo Satoru')).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Place this character'), findsOneWidget);
        expect(_drain(tester), isEmpty, reason: 'the character sheet');
        tester.state<NavigatorState>(find.byType(Navigator).first).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // The top tier's sheet (scrolled into view first: at 2.0x the
        // list's prompt can fill the board's first screen).
        final top = list.tiers.first.label;
        final plate = find.bySemanticsLabel(RegExp('^${RegExp.escape(top)}\\.'), skipOffstage: false).first;
        await tester.ensureVisible(plate);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(plate);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Edit tier'), findsOneWidget);
        expect(_drain(tester), isEmpty, reason: 'the tier sheet');
        await _finish(tester);
      });
    }
  }
}
