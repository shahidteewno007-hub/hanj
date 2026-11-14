// Arcs redesign (2026-11-14): the new Arcs pieces lay out cleanly on the
// CPH2573's 360x792 at 1.0x and 1.3x text, with long names, long titles and
// three-digit episodes, and the schedule maths says what it should.
//
// A release web build doesn't report a RenderFlex overflow; a widget test
// does, as an exception. No cover has a picture here (no network in tests),
// so every print is its placeholder and every field is clear.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/core/theme/app_theme.dart';
import 'package:hanj/features/social/arc_compose_hanko.dart';
import 'package:hanj/features/social/arc_page_hanko.dart';
import 'package:hanj/features/social/arcs_hanko.dart';
import 'package:hanj/services/arcs_service.dart';

final DateTime _now = DateTime(2026, 11, 14, 20);

const _longShow = ArcShow(
  id: '21',
  title: 'Jujutsu Kaisen: Shibuya Incident Arc and the Culling Game, Part 1',
  episodes: 1100,
);

Arc _arc({
  String name = 'Jujutsu Kaisen: Shibuya Incident Arc, a slow rewatch',
  ArcShow? show = _longShow,
  int from = 1,
  int to = 1100,
  int pace = 6,
  DateTime? startsOn,
  List<String> members = const ['me', 'b'],
  int memberCount = 12345,
  String description =
      'A first rewatch for some of us, dub and sub both welcome, no manga spoilers past where we are.',
}) =>
    Arc(
      id: 'a',
      name: name,
      description: description,
      show: show,
      from: from,
      to: to,
      pace: pace,
      startsOn: show == null ? null : (startsOn ?? DateTime(2026, 11, 7)),
      members: members,
      memberCount: memberCount,
      postCount: 3,
      createdBy: 'b',
      creatorName: 'Someone with a remarkably long display name',
    );

ArcPost _post(String id, {int? ep = 104, String author = 'b'}) => ArcPost(
      id: id,
      title: 'What the last scene of episode $ep was really saying about Gojo',
      body: 'A long thought. ' * 30,
      authorId: author,
      authorName: 'Someone with a remarkably long display name',
      likes: const ['me'],
      likeCount: 1234,
      replyCount: 999,
      createdAt: _now.subtract(const Duration(hours: 3)),
      ep: ep,
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
    home: Scaffold(backgroundColor: AppTheme.hankoSumi, body: body),
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
  group('schedule', () {
    test('stops, this week and the end', () {
      final a = _arc(from: 1, to: 28, pace: 4, startsOn: DateTime(2026, 11, 7));
      expect(a.stopCount, 7);
      expect(a.stop(1).episodes, '5–8');
      expect(a.stop(6).last, 28);
      expect(a.stopOn(DateTime(2026, 11, 14, 23)), 1);
      expect(a.stopOn(DateTime(2026, 11, 6)), -1);
      expect(a.phaseOn(DateTime(2026, 12, 26)), ArcPhase.finished);
      expect(arcPhaseLine(a, _now), 'This week: episodes 5–8');
      expect(arcRangeLine(a), 'Episodes 1–28 · 4 a week');
      final odd = _arc(from: 3, to: 10, pace: 3);
      expect(odd.stopCount, 3);
      expect(odd.stop(2).episodes, '9–10');
    });

    test('a post seals past your episode, never for its author', () {
      final p = _post('p', ep: 9);
      expect(p.sealedFor('me', 6), isTrue);
      expect(p.sealedFor('me', 9), isFalse);
      expect(p.sealedFor('b', 0), isFalse);
      expect(_post('q', ep: null).sealedFor('me', 0), isFalse);
    });
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('index boards, ${scale}x text', (tester) async {
      _phone(tester, scale);
      await _show(
        tester,
        ListView(
          padding: const EdgeInsets.all(AppTheme.hankoGutter),
          children: [
            for (final a in [
              _arc(),
              _arc(startsOn: DateTime(2026, 11, 21), members: const ['b']),
              _arc(to: 12, pace: 1, startsOn: DateTime(2026, 6, 1)),
              _arc(show: null, name: 'An arc from before the redesign'),
            ]) ...[
              ArcBoard(arc: a, uid: 'me', now: _now, onTap: () {}),
              const SizedBox(height: 12),
            ],
            ArcAction(label: 'Start an arc', icon: Icons.add_sharp, expand: true, onTap: () {}),
          ],
        ),
      );
      expect(_drain(tester), isEmpty);
      expect(find.text('Joined'), findsWidgets);
      expect(find.text('12345 watching'), findsWidgets);
      await _finish(tester);
    });

    testWidgets('arc page pieces, ${scale}x text', (tester) async {
      _phone(tester, scale);
      final arc = _arc();
      await _show(
        tester,
        SingleChildScrollView(
          child: Column(
          children: [
            ArcHero(arc: arc, now: _now, member: true, busy: false, onJoin: () {}, onLeave: () {}),
            ArcHero(arc: arc, now: _now, member: false, busy: true, onJoin: () {}, onLeave: () {}),
            ArcPostTile(
              post: _post('open'),
              uid: 'me',
              now: _now,
              progress: 200,
              sealed: false,
              onOpenSealed: () {},
              onTap: () {},
              onLike: () {},
            ),
            ArcPostTile(
              post: _post('sealed', ep: 1099),
              uid: 'me',
              now: _now,
              progress: 0,
              sealed: true,
              onOpenSealed: () {},
              onTap: () {},
              onLike: () {},
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
              child: ArcReplyRow(
                reply: ArcReply(
                  id: 'r',
                  body: 'A reply that goes on. ' * 12,
                  authorId: 'b',
                  authorName: 'Someone with a remarkably long display name',
                  createdAt: _now.subtract(const Duration(days: 12)),
                ),
                now: _now,
                menu: const Icon(Icons.more_horiz_sharp),
              ),
            ),
          ],
          ),
        ),
      );
      expect(_drain(tester), isEmpty);
      expect(find.text('Sealed · episode 1099'), findsOneWidget);
      expect(find.text('Open anyway'), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('start sheet for a long show, ${scale}x text', (tester) async {
      _phone(tester, scale);
      await _show(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: ArcStartSheet(uid: 'me', show: _longShow, today: _now),
        ),
      );
      expect(_drain(tester), isEmpty);
      expect(find.text('Start the arc'), findsOneWidget);
      // 1100 episodes at 3 a week.
      expect(find.textContaining('367 stops'), findsOneWidget);
      // _now is a Saturday: "Saturday" would duplicate "In a week".
      expect(find.text('Saturday'), findsNothing);
      expect(find.text('In a week'), findsOneWidget);
      await _finish(tester);
    });
  }
}
