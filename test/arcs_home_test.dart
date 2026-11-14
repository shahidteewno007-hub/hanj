// Arcs on Home (arcs-home, 2026-11-14): "Your arcs this week" lays out
// cleanly on the CPH2573's 360x792 at 1.0x and 1.3x text, with long names
// and three-digit episodes, shows only running arcs, and draws nothing at
// all when there are none.
//
// A release web build doesn't report a RenderFlex overflow; a widget test
// does, as an exception. No cover has a picture here (no network in tests),
// so every print is its placeholder and every field is clear.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/core/theme/app_theme.dart';
import 'package:hanj/features/home/arcs_this_week.dart';
import 'package:hanj/services/arcs_service.dart';

final DateTime _now = DateTime(2026, 11, 14, 20);

const _longShow = ArcShow(
  id: '21',
  title: 'Jujutsu Kaisen: Shibuya Incident Arc and the Culling Game, Part 1',
  episodes: 1100,
);

Arc _arc(
  String id, {
  String name = 'Jujutsu Kaisen: Shibuya Incident Arc, a slow rewatch with friends',
  ArcShow? show = _longShow,
  int from = 1,
  int to = 1100,
  int pace = 6,
  DateTime? startsOn,
}) =>
    Arc(
      id: id,
      name: name,
      description: '',
      show: show,
      from: from,
      to: to,
      pace: pace,
      startsOn: show == null ? null : (startsOn ?? DateTime(2026, 8, 1)),
      members: const ['me'],
      memberCount: 3,
      postCount: 0,
      createdBy: 'me',
      creatorName: 'Me',
    );

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

Future<void> _show(WidgetTester tester, Widget body) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      body: ListView(children: [body]),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 16));
  _drain(tester);
}

void main() {
  // Started 1 Aug at 6 a week: 15 weeks on, this week is stop 15,
  // episodes 91–96. The others: one starting next week, one finished,
  // one from before the redesign, and two more running.
  final arcs = [
    _arc('starting', startsOn: DateTime(2026, 11, 21)),
    _arc('finished', to: 12, startsOn: DateTime(2026, 9, 1)),
    _arc('old', show: null, name: 'One Piece Lore'),
    _arc('long'),
    _arc('frieren',
        name: 'Frieren, episodes 1–28',
        show: const ArcShow(id: '154587', title: 'Frieren', episodes: 28),
        to: 28,
        pace: 4,
        startsOn: DateTime(2026, 11, 7)),
    _arc('vinland',
        name: 'Vinland Saga, the farm',
        show: const ArcShow(id: '136430', title: 'Vinland Saga Season 2'),
        to: 24,
        pace: 3,
        startsOn: DateTime(2026, 11, 2)),
  ];

  test('only running arcs, the week closing soonest first', () {
    final running = ArcsThisWeekList.runningOn(arcs, _now);
    expect(running.map((a) => a.id), ['vinland', 'frieren', 'long']);
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('three running arcs at 360 dp, ${scale}x text', (tester) async {
      _phone(tester, scale);
      await _show(
        tester,
        ArcsThisWeekList(
          arcs: arcs,
          now: _now,
          progress: (id) => id == '154587' ? 3 : null,
          more: const Text('All arcs'),
          onOpen: (_) {},
        ),
      );
      expect(_drain(tester), isEmpty);
      expect(find.text('Your arcs this week'), findsOneWidget);
      expect(find.text('This week: episodes 91–96'), findsOneWidget);
      expect(find.text('This week: episodes 5–8'), findsOneWidget);
      expect(find.text('You’re on episode 3'), findsOneWidget);
      expect(find.byType(ArcWeekRow), findsNWidgets(3));
      expect(find.text('One Piece Lore'), findsNothing);
      await _finish(tester);
    });
  }

  testWidgets('no running arcs: nothing at all', (tester) async {
    _phone(tester, 1.0);
    await _show(
      tester,
      ArcsThisWeekList(
        arcs: [arcs[0], arcs[1], arcs[2]],
        now: _now,
        onOpen: (_) {},
      ),
    );
    expect(find.text('Your arcs this week'), findsNothing);
    expect(tester.getSize(find.byType(ArcsThisWeekList, skipOffstage: false)), const Size(360, 0));
    await _finish(tester);
  });

  testWidgets('a tap opens that arc', (tester) async {
    _phone(tester, 1.0);
    Arc? opened;
    await _show(
      tester,
      ArcsThisWeekList(
        arcs: [arcs[4]],
        now: _now,
        onOpen: (a) => opened = a,
      ),
    );
    await tester.tap(find.byType(ArcWeekRow));
    expect(opened?.id, 'frieren');
    await _finish(tester);
  });
}
