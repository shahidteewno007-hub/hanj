// Up next at the top of Home (up-next, 2026-11-14): which show it picks,
// what it says, and that its words lay out cleanly beside the hero print on
// the CPH2573's 360x792 at 1.0x and 1.3x text, with a long title and
// four-digit episodes.
//
// The hero's geometry is Home's _HeroRow at 360 dp: the 20 gutters, the
// words, 24, and the 96 x 136 print 4 down. A release web build doesn't
// report a RenderFlex overflow; a widget test does, as an exception.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/core/theme/app_theme.dart';
import 'package:hanj/features/home/up_next.dart';

final DateTime _now = DateTime(2026, 11, 14, 15, 30);

Map<String, dynamic> _show(String id, String title,
        {int current = 0, int? episodes}) =>
    {
      'animeId': id,
      'title': title,
      'currentEpisode': current,
      'episodes': episodes,
    };

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

/// The hero as Home lays it out at 360 dp, and the tonight line under it.
Widget _hero(UpNext upNext, UpNextTonight? tonight) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: UpNextWords(
                  upNext: upNext,
                  now: _now,
                  sentenceStyle:
                      AppTheme.hankoSerif(fontSize: 20, height: 1.32),
                ),
              ),
              const SizedBox(width: 24),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(width: 96, height: 136),
              ),
            ],
          ),
          if (tonight != null) ...[
            const SizedBox(height: 8),
            UpNextTonightLine(tonight: tonight, onTap: () {}),
          ],
        ],
      ),
    );

Future<void> _pump(WidgetTester tester, Widget body) async {
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

String _plain(String s) => s.replaceAll(' ', ' ').replaceAll('⁠', '');

void main() {
  final frieren = _show('154587', 'Frieren', current: 8, episodes: 28);
  final firefly = _show('2', 'Firefly Wedding', current: 7, episodes: 12);
  final bebop = _show('1', 'Cowboy Bebop', current: 11, episodes: 26);
  final tonightAt = DateTime(2026, 11, 14, 21, 30);
  final thursday = DateTime(2026, 11, 19, 18, 0);

  group('pick', () {
    test('before the airing batch: Continue’s first', () {
      final u = UpNext.pick([frieren, firefly],
          airedFor: (_) => null, nextAiringFor: (_) => null)!;
      expect(u.entry, same(frieren));
      expect(u.caughtUp, isFalse);
    });

    test('caught up on the newest: the next show with an episode out', () {
      final aired = {'154587': 8, '2': 8};
      final u = UpNext.pick([frieren, firefly],
          airedFor: (e) => aired[e['animeId']],
          nextAiringFor: (e) => (episode: 9, at: thursday))!;
      expect(u.entry, same(firefly));
      expect(_plain(u.sentence()), 'Episode 8 of Firefly Wedding is next');
      expect(_plain(u.meta(_now)!), 'Out now · 7 of 12');
    });

    test('a finished show (the batch knows nothing) is watchable', () {
      final u = UpNext.pick([bebop],
          airedFor: (_) => null, nextAiringFor: (_) => null)!;
      expect(_plain(u.sentence()), 'Episode 12 of Cowboy Bebop is next');
      expect(_plain(u.meta(_now)!), '11 of 26 · 15 to go');
    });

    test('caught up on everything: the soonest to air', () {
      final next = {
        '154587': (episode: 9, at: thursday),
        '2': (episode: 8, at: tonightAt),
      };
      final u = UpNext.pick([frieren, _show('2', 'Firefly Wedding', current: 7)],
          airedFor: (e) => e['animeId'] == '154587' ? 8 : 7,
          nextAiringFor: (e) => next[e['animeId']])!;
      expect(u.caughtUp, isTrue);
      expect(_plain(u.sentence()), 'You’re caught up on Firefly Wedding');
      expect(_plain(u.meta(_now)!), 'Episode 8 airs tonight at 21:30');
    });

    test('nothing on Continue: no hero', () {
      expect(
          UpNext.pick([], airedFor: (_) => null, nextAiringFor: (_) => null),
          isNull);
    });
  });

  group('words', () {
    test('several out, the finale, a film', () {
      expect(
          _plain(UpNext(entry: firefly, caughtUp: false, aired: 10).meta(_now)!),
          '3 new episodes out · 7 of 12');
      expect(
          _plain(UpNext(entry: _show('3', 'Dandadan', current: 11, episodes: 12),
                  caughtUp: false)
              .sentence()),
          'The finale of Dandadan is next');
      expect(
          _plain(UpNext(entry: _show('3', 'Dandadan', current: 11, episodes: 12),
                  caughtUp: false)
              .meta(_now)!),
          '11 of 12 · one to go');
      expect(
          _plain(UpNext(entry: _show('4', 'Your Name', episodes: 1),
                  caughtUp: false)
              .sentence()),
          'Your Name is next');
    });

    test('when it airs', () {
      expect(_plain(airsWhen(DateTime(2026, 11, 14, 13), _now)), 'today at 13:00');
      expect(_plain(airsWhen(tonightAt, _now)), 'tonight at 21:30');
      expect(_plain(airsWhen(DateTime(2026, 11, 15, 1), _now)), 'tomorrow at 01:00');
      expect(_plain(airsWhen(thursday, _now)), 'on Thursday at 18:00');
      expect(_plain(airsWhen(DateTime(2026, 12, 3, 18), _now)), 'on 3 December');
    });

    test('tonight: later today only, never the hero’s show', () {
      final next = {
        '154587': (episode: 9, at: tonightAt),
        '2': (episode: 8, at: DateTime(2026, 11, 14, 10)), // already aired
        '1': (episode: 12, at: DateTime(2026, 11, 15, 0, 30)), // tomorrow
      };
      final t = UpNextTonight.pick([frieren, firefly, bebop],
          except: firefly, nextAiringFor: (e) => next[e['animeId']], now: _now)!;
      expect(t.entry, same(frieren));
      expect(_plain(t.spoken()), 'Tonight: Frieren, episode 9 at 21:30');
      expect(
          UpNextTonight.pick([frieren],
              except: frieren,
              nextAiringFor: (e) => next[e['animeId']],
              now: _now),
          isNull);
    });
  });

  final long = _show(
    '21',
    'Jujutsu Kaisen: Shibuya Incident Arc and the Culling Game, Part 1',
    current: 1119,
    episodes: 1200,
  );
  final heroes = <String, (UpNext, UpNextTonight?)>{
    'out now, with tonight': (
      UpNext(entry: long, caughtUp: false, aired: 1124),
      UpNextTonight(
          entry: _show('9', 'The Apothecary Diaries Season 3', current: 4),
          airing: (episode: 1005, at: tonightAt)),
    ),
    'caught up': (
      UpNext(
          entry: long,
          caughtUp: true,
          aired: 1119,
          nextAiring: (episode: 1120, at: thursday)),
      null,
    ),
  };

  for (final scale in [1.0, 1.3]) {
    for (final MapEntry(key: name, value: (upNext, tonight)) in heroes.entries) {
      testWidgets('$name at 360 dp, ${scale}x text', (tester) async {
        _phone(tester, scale);
        await _pump(tester, _hero(upNext, tonight));
        expect(_drain(tester), isEmpty);
        expect(find.text(upNext.sentence()), findsOneWidget);
        expect(find.text(upNext.meta(_now)!), findsOneWidget);
        expect(find.byType(UpNextTonightLine),
            tonight == null ? findsNothing : findsOneWidget);
        await _finish(tester);
      });
    }
  }

  testWidgets('the tonight line is one button that opens its show',
      (tester) async {
    _phone(tester, 1.0);
    var opened = 0;
    await _pump(
      tester,
      UpNextTonightLine(
        tonight: UpNextTonight(entry: frieren, airing: (episode: 9, at: tonightAt)),
        onTap: () => opened++,
      ),
    );
    final handle = tester.ensureSemantics();
    expect(
        find.bySemanticsLabel('Tonight: Frieren, episode 9 at 21:30'),
        findsOneWidget);
    await tester.tap(find.byType(UpNextTonightLine));
    expect(opened, 1);
    handle.dispose();
    await _finish(tester);
  });
}
