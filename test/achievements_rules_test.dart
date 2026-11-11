// Achievements (r9): the rules, on three lists shaped like real ones.
//
// - Shahid's: 170 titles brought in one import on 2 September 2026, 89
//   finished, 4,541 episodes, 82 ratings that came with the import, Founder
//   #1, one Masterpiece, three Favourites, and One-Punch Man finished and
//   sealed in Hanj on 3 November. The design estimated about 12 achievements
//   for it (counting achievements, not marks).
// - A new user: 5 titles added by hand in the first week.
// - A heavy importer: 600 titles in one import.
//
// The rules are pure Dart (lib/models/achievements.dart), so nothing here
// needs Firebase or the network.

import 'package:flutter_test/flutter_test.dart';
import 'package:hanj/models/achievements.dart';

/// A list entry as AchievementsService hands it to the rules: Firestore's
/// fields, with Timestamps already turned into DateTimes.
Map<String, Object?> entry({
  required String title,
  required String status,
  DateTime? addedAt,
  DateTime? lastWatched,
  int? episodes,
  int? current,
  double? rating,
  DateTime? ratedAt,
  int? average,
  List<String> genres = const [],
  List<String>? tags,
  DateTime? tagsUpdatedAt,
  DateTime? favouritedAt,
}) =>
    {
      'title': title,
      'status': status,
      'addedAt': addedAt,
      'lastWatched': lastWatched ?? addedAt,
      'episodes': episodes,
      'currentEpisode': current,
      'userRating': rating,
      'ratedAt': ratedAt,
      'averageScore': average,
      'genres': genres,
      'tags': tags,
      'tagsUpdatedAt': tagsUpdatedAt,
      'favouritedAt': favouritedAt,
    };

const _genreCycle = [
  ['Action', 'Adventure', 'Fantasy'],
  ['Action', 'Comedy', 'Supernatural'],
  ['Action', 'Fantasy', 'Drama'],
  ['Adventure', 'Fantasy', 'Mystery'],
  ['Action', 'Sci-Fi', 'Thriller'],
  ['Romance', 'Slice of Life', 'Comedy'],
  ['Action', 'Adventure', 'Psychological'],
];

final _importAt = DateTime(2026, 9, 2, 10);

/// One import: an entry every 0.4 s, as the importer writes them.
DateTime _imported(int i) => _importAt.add(Duration(milliseconds: 400 * i));

/// Shahid's list, as the design's figures describe it.
class ShahidList {
  final entries = <String, Map<String, Object?>>{};
  final activity = <String, DateTime?>{};
  final facts = <int, ShowFacts>{};

  static const opm = '21087';
  static const fmab = '5114';
  static const bleach = '269';

  ShahidList() {
    var i = 0;
    var episodes = 0;
    void add(String id, Map<String, Object?> data, {String? type}) {
      entries[id] = data;
      activity['${type ?? data['status']}_$id'] = data['addedAt'] as DateTime?;
    }

    // 88 finished shows came with the import; 82 of them rated, lowest 7.
    for (var n = 0; n < 88; n++) {
      final id = n == 0 ? fmab : (n == 1 ? bleach : '${1000 + n}');
      final eps = n == 1 ? 366 : (n == 0 ? 64 : 12 + n % 14);
      episodes += eps;
      final at = _imported(i++);
      add(id, entry(
        title: n == 0
            ? 'Fullmetal Alchemist: Brotherhood'
            : (n == 1 ? 'Bleach' : 'Show $n'),
        status: 'COMPLETED',
        addedAt: at,
        episodes: eps,
        current: eps,
        rating: n < 82 ? 7 + (n % 7) * 0.5 : null,
        average: 80,
        genres: _genreCycle[n % _genreCycle.length],
        tags: n == 0 ? ['Masterpiece'] : null,
        tagsUpdatedAt: n == 0 ? DateTime(2026, 11, 4, 20) : null,
      ));
      // Decades from the 2000s on; a film, an OVA and a web series among
      // them; seasons from two of a year's four only.
      final year = n == 1 ? 2004 : (n == 0 ? 2009 : 2012 + n % 13);
      facts[int.parse(id)] = ShowFacts(
        id: int.parse(id),
        format: switch (n) { 2 => 'MOVIE', 3 => 'OVA', 4 => 'ONA', _ => 'TV' },
        season: n.isEven ? 'SPRING' : 'FALL',
        seasonYear: year,
        status: 'FINISHED',
        startDate: year * 10000 + 401,
        endDate: year * 10000 + 625,
      );
    }
    // 14 watching, 63 on the watchlist, 4 dropped.
    for (var n = 0; n < 14; n++) {
      final at = _imported(i++);
      episodes += 5;
      add('${3000 + n}', entry(
          title: 'Watching $n', status: 'WATCHING', addedAt: at, episodes: 24, current: 5,
          genres: const ['Action']));
    }
    for (var n = 0; n < 63; n++) {
      add('${4000 + n}', entry(
          title: 'Saved $n', status: 'PLAN_TO_WATCH', addedAt: _imported(i++), episodes: 12));
    }
    for (var n = 0; n < 4; n++) {
      episodes += 2;
      add('${5000 + n}', entry(
          title: 'Dropped $n', status: 'DROPPED', addedAt: _imported(i++), episodes: 12,
          current: 2));
    }
    // One-Punch Man: on Watching since the import, finished in Hanj on 3
    // November and sealed half an hour later.
    final finishedAt = DateTime(2026, 11, 3, 21);
    episodes += 12;
    entries[opm] = entry(
      title: 'One-Punch Man',
      status: 'COMPLETED',
      addedAt: _imported(i++),
      lastWatched: finishedAt,
      episodes: 12,
      current: 12,
      rating: 8.5,
      ratedAt: finishedAt.add(const Duration(minutes: 30)),
      average: 83,
      genres: const ['Action', 'Comedy', 'Sci-Fi', 'Supernatural'],
    );
    activity['WATCHING_$opm'] = entries[opm]!['addedAt'] as DateTime;
    facts[int.parse(opm)] = const ShowFacts(
      id: 21087, format: 'TV', season: 'FALL', seasonYear: 2015,
      status: 'FINISHED', startDate: 20151005, endDate: 20151221);
    // Three Favourites, marked on 6 November.
    for (final id in ['1010', '1011', '1012']) {
      entries[id] = {
        ...entries[id]!,
        'tags': ['Favourites'],
        'tagsUpdatedAt': DateTime(2026, 11, 6, 19),
        'favouritedAt': DateTime(2026, 11, 6, 19, id.codeUnitAt(3)),
      };
    }
    // Make the total Profile's 4,541: the last watching show takes the rest.
    final rest = 4541 - episodes + 5;
    entries['3013'] = {...entries['3013']!, 'currentEpisode': rest, 'episodes': 500};
  }

  AchievementInputs inputs({
    Map<String, DateTime?>? cards,
    bool withFacts = true,
    bool withActivity = true,
  }) =>
      AchievementInputs(
        entries: entries,
        now: DateTime(2026, 11, 10, 12),
        activity: withActivity ? activity : null,
        facts: withFacts ? facts : const {},
        isFounder: true,
        founderNumber: 1,
        founderJoinedAt: DateTime(2026, 8, 20, 9),
        tierLists: const [],
        cards: cards,
      );
}

/// A new user: 5 titles added by hand over the first week.
Map<String, Map<String, Object?>> newUserList() {
  final day = DateTime(2026, 11, 1, 18);
  return {
    // Finished by +1 on day 3, sealed the same night.
    '1': entry(
        title: 'Frieren', status: 'COMPLETED', addedAt: day,
        lastWatched: day.add(const Duration(days: 2)), episodes: 12, current: 12,
        rating: 10, ratedAt: day.add(const Duration(days: 2, hours: 1)), average: 90,
        genres: const ['Adventure', 'Drama', 'Fantasy']),
    // Finished with the sheet on day 4, sealed the day after.
    '2': entry(
        title: 'Mushishi', status: 'COMPLETED', addedAt: day.add(const Duration(hours: 1)),
        lastWatched: day.add(const Duration(days: 3)), episodes: 12, current: 12,
        rating: 9, ratedAt: day.add(const Duration(days: 4)), average: 86,
        genres: const ['Adventure', 'Mystery', 'Slice of Life', 'Supernatural']),
    '3': entry(
        title: 'DAN DA DAN', status: 'WATCHING', addedAt: day.add(const Duration(hours: 2)),
        episodes: 12, current: 3),
    '4': entry(title: 'Monster', status: 'PLAN_TO_WATCH', addedAt: day.add(const Duration(hours: 3))),
    '5': entry(title: 'Akira', status: 'PLAN_TO_WATCH', addedAt: day.add(const Duration(hours: 4))),
  };
}

/// A heavy importer: 600 titles from AniList in one import.
AchievementInputs heavyImporter() {
  final entries = <String, Map<String, Object?>>{};
  final facts = <int, ShowFacts>{};
  const seasons = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
  for (var n = 0; n < 600; n++) {
    final id = 10000 + n;
    final status = n < 430
        ? 'COMPLETED'
        : n < 470
            ? 'WATCHING'
            : n < 570
                ? 'PLAN_TO_WATCH'
                : 'DROPPED';
    entries['$id'] = entry(
      title: 'Show $n',
      status: status,
      addedAt: _importAt.add(Duration(milliseconds: 300 * n)),
      episodes: 16 + n % 10,
      current: status == 'COMPLETED' ? 16 + n % 10 : 4,
      rating: n < 400 ? 3 + (n % 15) * 0.5 : null,
      average: 75,
      genres: _genreCycle[n % _genreCycle.length],
    );
    // Seasonal since the 1980s: four shows a year, one from each season.
    final year = 1985 + (n ~/ 4) % 40;
    facts[id] = ShowFacts(
      id: id,
      format: 'TV',
      season: seasons[n % 4],
      seasonYear: year,
      status: 'FINISHED',
      startDate: year * 10000 + 101,
    );
  }
  return AchievementInputs(
    entries: entries,
    now: DateTime(2026, 11, 10),
    facts: facts,
    activity: const {},
  );
}

void main() {
  group('batches (D3)', () {
    final t0 = DateTime(2026, 9, 2, 10);
    List<DateTime> run(int n, Duration gap) =>
        [for (var i = 0; i < n; i++) t0.add(gap * i)];

    test('five times within a minute of each other are a batch', () {
      final spans = Achievements.batchesOf(run(5, const Duration(seconds: 59)));
      expect(spans, hasLength(1));
      expect(spans.single.size, 5);
      expect(spans.single.start, t0);
      // First to last, plus a minute.
      expect(spans.single.end, t0.add(const Duration(seconds: 59 * 4 + 60)));
    });

    test('four are not, and a gap over a minute breaks a run', () {
      expect(Achievements.batchesOf(run(4, const Duration(seconds: 1))), isEmpty);
      expect(Achievements.batchesOf(run(10, const Duration(seconds: 61))), isEmpty);
      final split = [
        ...run(5, const Duration(seconds: 1)),
        ...run(5, const Duration(seconds: 1)).map((t) => t.add(const Duration(hours: 1))),
      ];
      expect(Achievements.batchesOf(split), hasLength(2));
    });

    test('order of the times does not matter', () {
      final times = run(6, const Duration(seconds: 2)).reversed;
      expect(Achievements.batchesOf(times).single.size, 6);
    });
  });

  group('the catalogue', () {
    test('22 entries, 2 unlisted, 20 listed, in six groups', () {
      expect(Achievements.catalogue, hasLength(22));
      expect(Achievements.catalogue.where((a) => a.unlisted).map((a) => a.id),
          unorderedEquals(['against_crowd', 'on_the_day']));
      expect(Achievements.listedTotal(isFounder: true), 20);
      // Founder shows on the page only for founders (decision f).
      expect(Achievements.listedTotal(isFounder: false), 19);
      expect(AchievementGroup.values.map((g) => g.heading), [
        'Milestones', 'Taste', 'Range', 'Staying with it', 'Your picks', 'Founder',
      ]);
    });

    test('36 marks counting levels, the ladders as drawn', () {
      final marks = Achievements.catalogue.fold<int>(0, (n, a) => n + a.steps.length);
      expect(marks, 36);
      List<int> ladder(String id) =>
          [for (final s in Achievements.byId(id)!.steps) s.threshold];
      expect(ladder('finished'), [1, 10, 50, 100, 250, 500]);
      expect(ladder('episodes'), [100, 1000, 5000, 10000]);
      expect(ladder('sealed'), [1, 10, 100]);
      expect(ladder('finished_sealed'), [1, 10, 100]);
      expect(ladder('genres'), [8, 16]);
      expect(ladder('decades'), [3, 5]);
    });

    test('Finished carves 1, 2, 2, 3, 4, 4 (decision d)', () {
      expect([for (final s in Achievements.byId('finished')!.steps) s.carving],
          [1, 2, 2, 3, 4, 4]);
      for (final a in Achievements.catalogue) {
        for (final s in a.steps) {
          expect(s.carving, inInclusiveRange(1, 4), reason: a.id);
        }
      }
    });

    test('keys parse back to their entry, level and parameter', () {
      expect(Achievements.parse('finished:100')!.title, '100 finished');
      expect(Achievements.parse('finished:100')!.carving, 3);
      expect(Achievements.parse('deep:Slice of Life')!.title, 'Deep in Slice of Life');
      expect(Achievements.parse('year:2025')!.title, '2025 in four seasons');
      expect(Achievements.parse('founder')!.achievement.group, AchievementGroup.founder);
      expect(Achievements.parse('finished:200'), isNull);
      expect(Achievements.parse('finished'), isNull);
      expect(Achievements.parse('nonsense'), isNull);
    });

    test('the screen counts achievements, never marks', () {
      expect(
          Achievements.countAchievements(
              ['finished:1', 'finished:10', 'deep:Action', 'deep:Drama', 'year:2020', 'founder']),
          4);
    });

    test('the switch replaces Hanj Cards', () {
      expect(Achievements.replaceCards, isTrue);
    });
  });

  group("Shahid's list", () {
    final list = ShahidList();
    final result = Achievements.evaluate(list.inputs());
    final marks = result.marks;

    test('its counts agree with Profile', () {
      expect(list.entries, hasLength(170));
      expect(result.totals.finished, 89);
      expect(result.totals.episodes, 4541);
      expect(result.totals.sealed, 83);
      expect(result.factsComplete, isTrue);
    });

    test('about 12 achievements on day one', () {
      final count = Achievements.countAchievements(marks.keys);
      expect(count, 12);
      expect(
          {for (final k in marks.keys) Achievements.parse(k)!.achievement.id},
          {
            'finished', 'episodes', 'genres', 'decades', 'forms', 'long_haul',
            'deep_genre', 'masterpiece', 'favourite', 'sealed',
            'finished_sealed', 'founder',
          });
    });

    test('the counting marks came with the list and name no show', () {
      for (final key in [
        'finished:1', 'finished:10', 'finished:50', 'episodes:100', 'episodes:1000',
        'genres:8', 'sealed:1', 'sealed:10', 'decades:3', 'forms', 'long_haul', 'deep:Action',
      ]) {
        expect(marks[key], isNotNull, reason: key);
        expect(marks[key]!.mark.how, MarkHow.withList, reason: key);
        expect(marks[key]!.mark.show, isNull, reason: key);
        expect(Achievements.dateLine(marks[key]!.mark), 'Came with your list, 2 September 2026',
            reason: key);
      }
      expect(marks.containsKey('finished:100'), isFalse);
      expect(marks.containsKey('episodes:5000'), isFalse);
      expect(marks.containsKey('sealed:100'), isFalse);
    });

    test('what Hanj saw happen is dated that day, with its show', () {
      final fs = marks['finished_sealed:1']!.mark;
      expect(fs.how, MarkHow.onDay);
      expect(fs.show, ShahidList.opm);
      expect(Achievements.dateLine(fs), '3 November 2026');
      expect(
          Achievements.line('finished_sealed:1', fs,
              show: (id) => const ShowNote(title: 'One-Punch Man', rating: 8.5)),
          'Finished and sealed the same night: One-Punch Man, 8.5.');

      final mp = marks['masterpiece']!.mark;
      expect((mp.how, mp.show), (MarkHow.onDay, ShahidList.fmab));
      expect(mp.at, DateTime(2026, 11, 4, 20));

      // The first of the three Favourites marked.
      final fav = marks['favourite']!;
      expect(fav.mark.how, MarkHow.onDay);
      expect(fav.decidedBy, '1010');

      final founder = marks['founder']!.mark;
      expect((founder.how, founder.n), (MarkHow.onDay, 1));
      expect(Achievements.line('founder', founder),
          'Founder #1, one of the first 50 people on Hanj.');
    });

    test('nothing the data cannot prove', () {
      // Lowest seal 7: the ruler isn't whole. No drop came back, nothing
      // waited six months, nothing finished as it aired, no full year.
      for (final key in ['whole_ruler', 'second_chance', 'off_watchlist', 'as_it_aired',
          'against_crowd', 'on_the_day', 'top9', 'tier_list', 'hidden_gem']) {
        expect(marks.containsKey(key), isFalse, reason: key);
      }
      expect(marks.keys.where((k) => k.startsWith('year:')), isEmpty);
    });

    test('next steps are plain lines, nearest first (decision a)', () {
      final next = Achievements.nextSteps(result.totals, marks.keys.toSet());
      final finished = next.firstWhere((n) => n.ref.achievement.id == 'finished');
      expect(finished.need, 100);
      expect(finished.line, '89 now, 11 to go.');
      final episodes = next.firstWhere((n) => n.ref.achievement.id == 'episodes');
      expect(episodes.line, '4,541 now, 459 to go.');
      expect(next.first.have / next.first.need,
          greaterThanOrEqualTo(next.last.have / next.last.need));
    });

    test('without facts the five fact rules wait, the rest stand', () {
      final noFacts = Achievements.evaluate(list.inputs(withFacts: false));
      expect(noFacts.factsComplete, isFalse);
      expect(noFacts.marks.keys.where((k) => k.startsWith('decades') || k == 'forms'), isEmpty);
      expect(Achievements.countAchievements(noFacts.marks.keys), 10);
    });

    test('the import is recognised from the activity log alone too', () {
      // Every entry touched again by hand since: addedAt no longer batches,
      // but the import's activity docs still do.
      final touched = <String, Map<String, Object?>>{};
      var k = 0;
      for (final e in list.entries.entries) {
        touched[e.key] = {
          ...e.value,
          'addedAt': DateTime(2026, 10, 1).add(Duration(minutes: 2 * k++)),
        };
      }
      final r = Achievements.evaluate(AchievementInputs(
        entries: touched,
        now: DateTime(2026, 11, 10),
        activity: list.activity,
        facts: list.facts,
      ));
      expect(r.marks['finished:50']!.mark.how, MarkHow.withList);
    });
  });

  group('a new user', () {
    final entries = newUserList();
    final result = Achievements.evaluate(
        AchievementInputs(entries: entries, now: DateTime(2026, 11, 8), activity: const {}));

    test('3 achievements, all on their days, with their shows', () {
      expect(result.marks.keys,
          unorderedEquals(['finished:1', 'sealed:1', 'finished_sealed:1']));
      for (final m in result.marks.values) {
        expect(m.mark.how, MarkHow.onDay, reason: m.key);
        expect(m.mark.show, '1', reason: m.key);
      }
      expect(result.marks['finished:1']!.mark.at, DateTime(2026, 11, 3, 18));
      expect(
          Achievements.line('sealed:1', result.marks['sealed:1']!.mark,
              show: (id) => const ShowNote(title: 'Frieren', rating: 10)),
          'Your first seal: 10 for Frieren.');
      // Sealed a day after finishing: not "the same night".
      expect(result.totals.finishedSealed, 1);
      expect(result.totals.episodes, 27);
    });

    test('episodes are dated "by", and name the show only when live', () {
      final more = {
        ...entries,
        '3': {...entries['3']!, 'currentEpisode': 76, 'lastWatched': DateTime(2026, 11, 9)},
      };
      final quiet = Achievements.evaluate(
          AchievementInputs(entries: more, now: DateTime(2026, 11, 9)));
      final mark = quiet.marks['episodes:100']!.mark;
      expect((mark.how, mark.show), (MarkHow.by, null));
      expect(Achievements.dateLine(mark), 'By 9 November 2026');

      final live = Achievements.evaluate(
          AchievementInputs(entries: more, now: DateTime(2026, 11, 9), live: {'3'}));
      final earned = live.marks['episodes:100']!;
      expect((earned.mark.how, earned.mark.show, earned.decidedBy), (MarkHow.onDay, '3', '3'));
      expect(
          Achievements.line('episodes:100', earned.mark,
              show: (id) => const ShowNote(title: 'DAN DA DAN')),
          '100 episodes. The hundredth came during DAN DA DAN.');
    });

    test('a pending server timestamp waits for its date', () {
      final pending = {
        ...entries,
        '3': {...entries['3']!, 'status': 'COMPLETED', 'lastWatched': null, 'addedAt': null},
      };
      final r = Achievements.evaluate(AchievementInputs(entries: pending, now: DateTime(2026, 11, 9)));
      expect(r.totals.finished, 3);
      // Two finished with dates; the third isn't placed yet.
      expect(r.marks['finished:1']!.decidedBy, '1');
    });
  });

  group('a heavy importer', () {
    final result = Achievements.evaluate(heavyImporter());
    final marks = result.marks;

    test('starts rich in counts, all of them with the list', () {
      for (final key in [
        'finished:1', 'finished:10', 'finished:50', 'finished:100', 'finished:250',
        'episodes:100', 'episodes:1000', 'episodes:5000', 'sealed:1', 'sealed:10',
        'sealed:100', 'genres:8', 'decades:3', 'decades:5', 'whole_ruler', 'deep:Action',
      ]) {
        expect(marks[key], isNotNull, reason: key);
        expect(marks[key]!.mark.how, MarkHow.withList, reason: key);
        expect(marks[key]!.mark.show, isNull, reason: key);
      }
      expect(marks.containsKey('finished:500'), isFalse);
      expect(result.totals.finished, 430);
      expect(marks.keys.where((k) => k.startsWith('year:')), isNotEmpty);
    });

    test('but the craft is still ahead: no Hanj moment comes from an import', () {
      for (final key in ['finished_sealed:1', 'against_crowd', 'on_the_day', 'as_it_aired',
          'masterpiece', 'favourite', 'top9', 'tier_list']) {
        expect(marks.containsKey(key), isFalse, reason: key);
      }
    });
  });

  group('the rules one by one', () {
    final day = DateTime(2026, 3, 1, 20);
    Map<String, Map<String, Object?>> finishedOn(List<(String, DateTime)> shows) => {
          for (final (id, at) in shows)
            id: entry(title: 'Show $id', status: 'COMPLETED', addedAt: at, episodes: 12),
        };

    test('second chance and off the watchlist read the activity log', () {
      final entries = finishedOn([('1', day), ('2', day.add(const Duration(days: 3)))]);
      final r = Achievements.evaluate(AchievementInputs(
        entries: entries,
        now: day.add(const Duration(days: 10)),
        activity: {
          'DROPPED_1': day.subtract(const Duration(days: 30)),
          'PLAN_TO_WATCH_2': day.subtract(const Duration(days: 200)),
        },
      ));
      expect(r.marks['second_chance']!.mark.show, '1');
      expect(r.marks['off_watchlist']!.mark.show, '2');
      // Unread log: the three rules wait.
      final unread = Achievements.evaluate(AchievementInputs(entries: entries, now: day));
      expect(unread.marks.containsKey('second_chance'), isFalse);
    });

    test('as it aired: started before the finale, finished within two weeks', () {
      final entries = {
        '7': entry(
            title: 'Frieren', status: 'COMPLETED', addedAt: DateTime(2026, 1, 5, 12),
            lastWatched: DateTime(2026, 3, 25, 22), episodes: 28),
      };
      AchievementInputs inputs(int endDate, Map<String, DateTime?> activity) =>
          AchievementInputs(
            entries: entries,
            now: DateTime(2026, 4, 1),
            activity: activity,
            facts: {7: ShowFacts(id: 7, endDate: endDate, status: 'FINISHED')},
          );
      // Finished by +1: no Completed in the log, so addedAt is the start.
      expect(Achievements.evaluate(inputs(20260322, const {})).marks['as_it_aired'], isNotNull);
      // A finale more than 14 days before the finish doesn't count.
      expect(Achievements.evaluate(inputs(20260301, const {})).marks['as_it_aired'], isNull);
      // Straight to Completed with the sheet, never on Watching: no.
      expect(
          Achievements.evaluate(inputs(20260322, {'COMPLETED_7': DateTime(2026, 3, 25, 22)}))
              .marks['as_it_aired'],
          isNull);
    });

    test('a full year, every form, decades and on the day read the facts', () {
      final shows = <(String, DateTime)>[
        for (var i = 1; i <= 6; i++) ('$i', day.add(Duration(days: i))),
      ];
      final entries = finishedOn(shows);
      final r = Achievements.evaluate(AchievementInputs(
        entries: entries,
        now: day.add(const Duration(days: 10)),
        facts: {
          1: const ShowFacts(id: 1, format: 'TV', season: 'WINTER', seasonYear: 1998),
          2: const ShowFacts(id: 2, format: 'MOVIE', season: 'SPRING', seasonYear: 1998),
          3: const ShowFacts(id: 3, format: 'OVA', season: 'SUMMER', seasonYear: 1998),
          // First aired 5 March 2018; finished 5 March 2026 (day + 4).
          4: const ShowFacts(id: 4, format: 'ONA', season: 'FALL', seasonYear: 1998,
              startDate: 20180305),
          5: const ShowFacts(id: 5, format: 'TV', seasonYear: 2008),
          // No season year: its start's year counts.
          6: const ShowFacts(id: 6, format: 'MOVIE', startDate: 19880716),
        },
      ));
      expect(r.marks['year:1998']!.mark.show, '4');
      expect(r.marks['forms']!.mark.show, '4');
      expect(r.marks['decades:3']!.decidedBy, '6');
      expect(r.marks.containsKey('decades:5'), isFalse);
      expect(r.marks['on_the_day']!.mark.show, '4');
      expect(
          Achievements.line('on_the_day', r.marks['on_the_day']!.mark,
              show: (id) => const ShowNote(title: 'Cowboy Bebop', startYear: 2018)),
          'You finished Cowboy Bebop on 5 March, 8 years to the day after it first aired.');
    });

    test('against the crowd needs a seal given in Hanj', () {
      final entries = {
        '9': entry(title: 'Devilman Crybaby', status: 'COMPLETED', addedAt: day,
            rating: 10, ratedAt: day, average: 70),
        '10': entry(title: 'Imported', status: 'COMPLETED', addedAt: day,
            rating: 2, average: 80),
      };
      final r = Achievements.evaluate(AchievementInputs(entries: entries, now: day));
      expect(r.marks['against_crowd']!.mark.show, '9');
      expect(Achievements.parse('against_crowd')!.achievement.unlisted, isTrue);
      expect(
          Achievements.line('against_crowd', r.marks['against_crowd']!.mark,
              show: (id) => const ShowNote(title: 'Devilman Crybaby', rating: 10, crowd: 76)),
          'You sealed Devilman Crybaby at 10. The crowd gives it 7.6.');
    });

    test('a rating off the ruler is no seal (D5)', () {
      final entries = {
        '1': entry(title: 'A', status: 'COMPLETED', addedAt: day, rating: 85),
      };
      final r = Achievements.evaluate(AchievementInputs(entries: entries, now: day));
      expect(r.totals.sealed, 0);
      expect(r.marks.containsKey('sealed:1'), isFalse);
    });

    test('top 9 and tier lists', () {
      final ids = [for (var i = 1; i <= 9; i++) '$i'];
      final dated = Achievements.evaluate(AchievementInputs(
        entries: const {},
        now: day,
        top9: ids,
        top9At: day.subtract(const Duration(days: 1)),
        tierLists: [
          TierListFact(id: 'a', createdAt: day, ranked: 4),
          TierListFact(id: 'b', createdAt: day.add(const Duration(hours: 1)), ranked: 14),
        ],
      ));
      expect((dated.marks['top9']!.mark.how, dated.marks['top9']!.mark.show), (MarkHow.onDay, '1'));
      expect(dated.marks['tier_list']!.decidedBy, 'tier:b');
      expect(Achievements.line('tier_list', dated.marks['tier_list']!.mark),
          'Your first tier list: 14 characters, ranked.');
      final undated = Achievements.evaluate(
          AchievementInputs(entries: const {}, now: day, top9: ids));
      expect(undated.marks['top9']!.mark.how, MarkHow.by);
      expect(Achievements.evaluate(
              AchievementInputs(entries: const {}, now: day, top9: ids.sublist(1)))
          .marks['top9'], isNull);
    });
  });

  group('written once, like ink', () {
    test('a removed show never removes a mark, and a mark never moves', () {
      final list = ShahidList();
      final first = Achievements.evaluate(list.inputs());
      final record = {for (final m in first.marks.values) m.key: m.mark};

      // Remove One-Punch Man, and re-rate a show later.
      list.entries.remove(ShahidList.opm);
      final again = Achievements.evaluate(list.inputs());
      expect(again.marks.containsKey('finished_sealed:1'), isFalse);
      expect(Achievements.newOnly(record, again.marks), isEmpty);
      // The record still holds it, as written.
      expect(record['finished_sealed:1']!.show, ShahidList.opm);
    });

    test('only marks not yet in the record are new', () {
      final existing = {
        'finished:1': RecordMark(at: DateTime(2026, 1, 1), how: MarkHow.onDay, show: '5'),
      };
      final found = {
        'finished:1': FoundMark('finished:1',
            RecordMark(at: DateTime(2026, 2, 1), how: MarkHow.withList), '6'),
        'sealed:1': FoundMark('sealed:1',
            RecordMark(at: DateTime(2026, 2, 1), how: MarkHow.onDay, show: '6'), '6'),
      };
      expect(Achievements.newOnly(existing, found).keys, ['sealed:1']);
    });

    test('a mark survives the round trip through its stored shape', () {
      final mark = RecordMark(
          at: DateTime(2026, 11, 3, 21), how: MarkHow.onDay, show: '21087', card: true, n: 3);
      final stored = mark.toMap((at) => at.millisecondsSinceEpoch);
      expect(stored, {
        'at': DateTime(2026, 11, 3, 21).millisecondsSinceEpoch,
        'how': 'on',
        'show': '21087',
        'card': true,
        'n': 3,
      });
      final back = RecordMark.fromMap(
          stored, (v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null)!;
      expect((back.at, back.how, back.show, back.card, back.n),
          (mark.at, mark.how, mark.show, mark.card, mark.n));
      expect(
          RecordMark(at: DateTime(2026), how: MarkHow.withList).toMap((at) => 0).keys,
          ['at', 'how']);
    });

    test('day one, and what is new since you last looked', () {
      final since = DateTime(2026, 11, 10, 12);
      final dayOne = AchievementRecord(since: since, marks: {
        'finished:50': RecordMark(at: DateTime(2026, 9, 2), how: MarkHow.withList),
        'founder': RecordMark(at: DateTime(2026, 8, 20), how: MarkHow.onDay, n: 1),
      });
      expect(dayOne.dayOne, isTrue);
      expect(dayOne.newKeys, isEmpty);
      expect(dayOne.count, 2);

      final later = dayOne.copyWith(marks: {
        ...dayOne.marks,
        'finished:100': RecordMark(at: since.add(const Duration(days: 3)), how: MarkHow.onDay),
      });
      expect(later.dayOne, isFalse);
      expect(later.newKeys, {'finished:100'});
      expect(later.copyWith(seen: since.add(const Duration(days: 4))).newKeys, isEmpty);
      expect(AchievementRecord.empty.started, isFalse);
    });
  });

  group('Hanj Cards carried over (decision e)', () {
    test('a matching card keeps its earlier date; the rest stay unshown', () {
      final list = ShahidList();
      final cardDay = DateTime(2026, 8, 25, 9);
      final r = Achievements.evaluate(list.inputs(cards: {
        // Earlier than the import: its date wins.
        'the_50_club': cardDay,
        // 200 isn't on the ladder; it carries to 100, which the phone lacks.
        'the_200_club': cardDay,
        // Later than the phone's own date: the phone's stands.
        'rated': DateTime(2026, 11, 9),
        // Retired cards carry nothing.
        'dropout': cardDay,
        'binge_mode': cardDay,
        'summer_2026_watcher': cardDay,
      }));
      final fifty = r.marks['finished:50']!.mark;
      expect((fifty.at, fifty.how, fifty.card), (cardDay, MarkHow.onDay, true));
      expect(Achievements.dateLine(fifty), 'Earned as a Hanj Card on 25 August 2026');
      expect(r.marks['finished:100']!.mark.card, isTrue);
      expect(r.marks['finished:100']!.decidedBy, 'card:the_200_club');
      expect(r.marks['sealed:1']!.mark.card, isFalse);
      expect(r.marks['sealed:1']!.mark.how, MarkHow.withList);
      // Retired cards add no mark: the same 12 achievements as without cards.
      expect(Achievements.countAchievements(r.marks.keys), 12);
    });

    test('a card dated inside the import came with the list', () {
      final list = ShahidList();
      final r = Achievements.evaluate(list.inputs(cards: {'first_pull': _imported(3)}));
      final mark = r.marks['finished:1']!.mark;
      // The phone's own date (the first finished entry) is earlier: kept.
      expect(mark.card, isFalse);
      final late = Achievements.evaluate(list.inputs(
          withFacts: false, cards: {'decade_hopper': _imported(3)}));
      // The phone can't tell decades without facts; the card carries it.
      expect(late.marks['decades:3']!.mark.how, MarkHow.withList);
      expect(late.marks['decades:3']!.mark.card, isTrue);
    });

    test('every carried card points at a real mark', () {
      for (final key in Achievements.cardCarry.values) {
        expect(Achievements.parse(key), isNotNull, reason: key);
      }
    });
  });

  group('words', () {
    test('numbers, ordinals, seals and dates', () {
      expect(Achievements.number(4541), '4,541');
      expect(Achievements.number(10000), '10,000');
      expect(Achievements.number(100), '100');
      expect(Achievements.ordinal(100), '100th');
      expect(Achievements.ordinal(1), '1st');
      expect(Achievements.ordinal(22), '22nd');
      expect(Achievements.ordinal(13), '13th');
      expect(Achievements.sealText(8.5), '8.5');
      expect(Achievements.sealText(9), '9');
      expect(Achievements.date(DateTime(2026, 11, 3)), '3 November 2026');
    });

    test('lines in the journal voice', () {
      final on = RecordMark(at: DateTime(2027, 3, 12), how: MarkHow.onDay, show: '1');
      ShowNote frieren(String id) => const ShowNote(title: 'Frieren', episodes: 28);
      expect(Achievements.line('finished:100', on, show: frieren),
          'Your 100th finished show: Frieren.');
      expect(Achievements.line('finished:50', RecordMark(at: DateTime(2026), how: MarkHow.withList)),
          'Your 50th finished show came with your list.');
      expect(Achievements.line('deep:Drama', on, show: frieren),
          'Deep in Drama: 25 finished. The 25th: Frieren.');
      expect(Achievements.line('year:2025', on), '2025 in four seasons: a show from each, finished.');
      expect(Achievements.line('genres:8', on), 'Finished shows in 8 of Hanj’s 16 genres.');
      expect(Achievements.line('second_chance', on, show: frieren),
          'You dropped Frieren, came back, and finished it.');
      // A show no longer on the list is left unnamed.
      expect(Achievements.line('masterpiece', on, show: (id) => null), 'Your first Masterpiece.');
    });
  });
}
