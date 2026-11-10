// Achievements (r9, approved by Shahid 2026-11-10: "Yes, build it"): what
// Hanj records in place of Hanj Cards.
//
// A record of watching, not a reward loop: 22 entries in six groups, each
// written once, like ink, with the show that earned it and a date only as
// sure as the data can prove. Everything here is plain Dart: the catalogue,
// the rules (D1–D10 of the design's catalogue), batch detection, dating and
// the card carry-over. AchievementsService (lib/services/) feeds it the list,
// the activity log, the user document's facts and AniList's media facts, and
// keeps what it finds on users/{uid}.achievements. Nothing here reads
// Firestore or the network, so the rules are tested without Firebase
// (test/achievements_rules_test.dart).
//
// Settled in the design, and not to be "improved" here:
// - no points, rarities, streaks, deadlines or progress meters: a next step
//   is a plain line ("89 now, 11 to go");
// - the screen counts achievements, one per entry, never marks (levels);
// - an imported list counts, dated "came with your list", and names no show
//   inside an import, because nobody knows the order it was watched in;
// - two entries are unlisted: never shown until they happen.

import 'hanj_shelves.dart';

/// Achievements are locked for everyone, owner included, until Hanj+ ships
/// (Shahid, 2026-11-11: "lock behind Hanj+ which we will work on later").
///
/// Compile-time on purpose, as kLokiEnabled is: with it off,
/// AchievementsService reads and writes nothing (no record, no badge, no
/// AniList facts, no live earns), Profile has no Achievements row and no
/// corner badge, a card_unlock push shows and opens nothing, and no slip
/// waits for an earn. Every hook in Home, Detail and Ranking Cards stays
/// where it is and returns at once. Hanj Cards stay removed (Achievements.replaceCards). True gives the whole
/// feature back exactly as built (c769dc5). No Hanj+ check yet: Hanj+
/// isn't scoped.
const bool kAchievementsEnabled = false;

/// The groups, in the order the Achievements page shows them (decision j):
/// the ones most people fill early first, so the page opens lit.
enum AchievementGroup {
  milestones('Milestones'),
  taste('Taste'),
  range('Range'),
  stayingWithIt('Staying with it'),
  yourPicks('Your picks'),
  founder('Founder');

  const AchievementGroup(this.heading);

  /// The page's heading for the group.
  final String heading;
}

/// One level of an entry: its threshold (0 for an entry with one level),
/// its title, and its carving (decision d): 1 a first act, 2 a habit, 3 a
/// feat or a full set, 4 the end of a long ladder. The badge draws the
/// carving; words always carry the exact level, so no badge holds a number.
class AchievementStep {
  const AchievementStep(this.threshold, this.title, this.carving);

  final int threshold;
  final String title;
  final int carving;
}

/// One entry of the catalogue.
class Achievement {
  const Achievement({
    required this.id,
    required this.name,
    required this.group,
    required this.what,
    required this.steps,
    this.keyPrefix,
    this.unlisted = false,
  });

  /// The design's id, which is also the emblem's id.
  final String id;

  /// The name on its space in the stamp book.
  final String name;
  final AchievementGroup group;

  /// What it records, in a few words ("How many shows you've finished").
  final String what;

  /// Its levels, lowest first. One step for an entry with no levels.
  final List<AchievementStep> steps;

  /// For the two entries that repeat with a parameter instead of levels:
  /// 'deep' ('deep:Drama', one per genre) and 'year' ('year:2025', one per
  /// year). Null for every other entry.
  final String? keyPrefix;

  /// Never shown until it happens, and never as a locked space: listing it
  /// would bend what people do (Goodhart's law).
  final bool unlisted;

  String get emblem => id;
  bool get tiered => steps.length > 1;
  bool get repeats => keyPrefix != null;

  /// The mark key for [step] (tiered entries) or the entry itself.
  String keyFor(AchievementStep step) =>
      tiered ? '$id:${step.threshold}' : id;
}

/// What an earned mark refers to: its entry, its level and, for the two
/// repeating entries, the genre or year.
class MarkRef {
  const MarkRef(this.achievement, this.step, [this.param]);

  final Achievement achievement;
  final AchievementStep step;
  final String? param;

  /// The level's own title: "100 finished", "Deep in Drama", "2025 in four
  /// seasons", "Named a masterpiece".
  String get title => switch (achievement.keyPrefix) {
        'deep' => 'Deep in $param',
        'year' => '$param in four seasons',
        _ => step.title,
      };

  int get carving => step.carving;
}

/// How sure a mark's date is (the design's three date forms).
enum MarkHow {
  /// It happened in Hanj that day: "3 November 2026".
  onDay('on'),

  /// On or before that day, the exact day unknown: "By 7 November 2026".
  by('by'),

  /// It came in an import: "Came with your list, 2 September 2026".
  withList('list');

  const MarkHow(this.code);

  /// As stored in `how`.
  final String code;

  static MarkHow? fromCode(Object? code) {
    for (final how in values) {
      if (how.code == code) return how;
    }
    return null;
  }
}

/// One mark as the record keeps it: `{ at, how, show?, card?, n? }`.
/// [show] is an AniList id (the list entry's id), ids only, named only when
/// the date is [MarkHow.onDay]. [card] says it was carried from a Hanj Card
/// with the card's date. [n] is Founder's number, or a tier list's count of
/// ranked characters.
class RecordMark {
  const RecordMark({
    required this.at,
    required this.how,
    this.show,
    this.card = false,
    this.n,
  });

  final DateTime at;
  final MarkHow how;
  final String? show;
  final bool card;
  final int? n;

  /// The stored shape, with [at] as given by [date] (a Firestore Timestamp
  /// for the user document, milliseconds for the phone's copy).
  Map<String, Object?> toMap(Object Function(DateTime at) date) => {
        'at': date(at),
        'how': how.code,
        'show': ?show,
        if (card) 'card': true,
        'n': ?n,
      };

  /// A stored mark, or null when it's unreadable. [date] turns the stored
  /// `at` into a DateTime.
  static RecordMark? fromMap(Object? map, DateTime? Function(Object? at) date) {
    if (map is! Map) return null;
    final at = date(map['at']);
    final how = MarkHow.fromCode(map['how']);
    if (at == null || how == null) return null;
    final show = map['show'];
    final n = map['n'];
    return RecordMark(
      at: at,
      how: how,
      show: show is String ? show : (show is num ? '${show.toInt()}' : null),
      card: map['card'] == true,
      n: n is num ? n.toInt() : null,
    );
  }
}

/// A mark the rules found, with the entry that decided it (D10). The
/// deciding entry is never stored: it tells a live earn (the entry you just
/// changed) from history. Ids that aren't list entries say what decided it:
/// `user:top9`, `user:founder`, `tier:<list id>`, `card:<card id>`.
class FoundMark {
  const FoundMark(this.key, this.mark, this.decidedBy);

  final String key;
  final RecordMark mark;
  final String? decidedBy;
}

/// The record as kept on users/{uid}.achievements: when it began ([since],
/// day one), whether Hanj Cards were carried over ([cards]), when you last
/// looked at the page ([seen]), and the marks.
class AchievementRecord {
  const AchievementRecord({
    this.since,
    this.cards = false,
    this.seen,
    this.marks = const {},
  });

  static const empty = AchievementRecord();

  final DateTime? since;
  final bool cards;
  final DateTime? seen;
  final Map<String, RecordMark> marks;

  /// Whether the record began; until then the first evaluation is day one.
  bool get started => since != null;

  /// Day one (decision g): the record holds only what it found when it
  /// began. A mark dated after [since] means something has happened in Hanj
  /// since, and the page gives way to its usual top.
  bool get dayOne {
    final start = since;
    return start != null && !marks.values.any((m) => m.at.isAfter(start));
  }

  /// Marks dated after you last looked ([seen], else [since]): the page's
  /// "New". A mark found late for an old date (a decade, once AniList's
  /// facts arrive) isn't new by this test; it's history, not news.
  Set<String> get newKeys {
    final after = seen ?? since;
    if (after == null) return const {};
    return {
      for (final e in marks.entries)
        if (e.value.at.isAfter(after)) e.key,
    };
  }

  /// How many achievements the record holds: one per entry, whatever its
  /// levels or repeats. What the screen counts.
  int get count => Achievements.countAchievements(marks.keys);

  AchievementRecord copyWith({
    DateTime? since,
    bool? cards,
    DateTime? seen,
    Map<String, RecordMark>? marks,
  }) =>
      AchievementRecord(
        since: since ?? this.since,
        cards: cards ?? this.cards,
        seen: seen ?? this.seen,
        marks: marks ?? this.marks,
      );
}

/// AniList's facts about one show (D8), which list entries don't store.
/// [startDate] and [endDate] are yyyymmdd, with 00 for an unknown month or
/// day. A show AniList didn't return is kept with every fact null, so it
/// counts as known.
class ShowFacts {
  const ShowFacts({
    required this.id,
    this.format,
    this.season,
    this.seasonYear,
    this.status,
    this.startDate,
    this.endDate,
  });

  final int id;
  final String? format;
  final String? season;
  final int? seasonYear;
  final String? status;
  final int? startDate;
  final int? endDate;

  int? get startYear => _year(startDate);

  /// The year the show premiered: its season's year, else its start's.
  int? get year => seasonYear ?? startYear;

  static int? _year(int? yyyymmdd) {
    if (yyyymmdd == null) return null;
    final y = yyyymmdd ~/ 10000;
    return y > 0 ? y : null;
  }

  /// A yyyymmdd date with a known month and day as a local day, else null.
  static DateTime? dayOf(int? yyyymmdd) {
    if (yyyymmdd == null) return null;
    final y = yyyymmdd ~/ 10000, m = yyyymmdd ~/ 100 % 100, d = yyyymmdd % 100;
    if (y == 0 || m == 0 || d == 0) return null;
    return DateTime(y, m, d);
  }
}

/// A tier list on this device, as "Ranked a cast" reads it.
class TierListFact {
  const TierListFact({
    required this.id,
    required this.createdAt,
    required this.ranked,
  });

  final String id;
  final DateTime createdAt;

  /// Characters placed in a tier (TierList.rankedCount).
  final int ranked;
}

/// Everything one evaluation reads. Dates are DateTimes (or milliseconds):
/// AchievementsService turns Firestore Timestamps into DateTimes first, and
/// a pending server timestamp arrives as null.
class AchievementInputs {
  const AchievementInputs({
    required this.entries,
    required this.now,
    this.activity,
    this.facts = const {},
    this.top9,
    this.top9At,
    this.isFounder = false,
    this.founderNumber,
    this.founderJoinedAt,
    this.tierLists,
    this.cards,
    this.live = const {},
  });

  /// The whole list: users/{uid}/animeList, by document id.
  final Map<String, Map<String, Object?>> entries;
  final DateTime now;

  /// users/{uid}/activity, document id ('DROPPED_154587') to its
  /// createdAt. Null when it hasn't been read: the three rules that need it
  /// (As it aired, Second chance, Off the watchlist) then wait.
  final Map<String, DateTime?>? activity;

  /// AniList's facts, by show id. The five rules that need them wait until
  /// every finished show's are known, so a missing one can't give an
  /// achievement a later date than it deserves.
  final Map<int, ShowFacts> facts;

  /// users/{uid}.top9 (ids in order) and top9At.
  final List<String>? top9;
  final DateTime? top9At;

  final bool isFounder;
  final int? founderNumber;
  final DateTime? founderJoinedAt;

  /// Tier lists on this device; null when not looked at.
  final List<TierListFact>? tierLists;

  /// Hanj Cards held (users/{uid}/cards), card id to unlockedAt; null when
  /// not read.
  final Map<String, DateTime?>? cards;

  /// Ids of what you've just changed (list entries, or `user:top9`,
  /// `tier:<id>`): an episodes mark decided by one names its show.
  final Set<String> live;
}

/// The counts behind the record, for the page's plain "next" lines.
class AchievementTotals {
  const AchievementTotals({
    required this.finished,
    required this.episodes,
    required this.sealed,
    required this.finishedSealed,
    required this.genres,
    required this.byGenre,
    this.decades,
  });

  final int finished;
  final int episodes;
  final int sealed;
  final int finishedSealed;

  /// Hanj's genres among your finished shows, and each one's count.
  final Set<String> genres;
  final Map<String, int> byGenre;

  /// The decades among your finished shows; null until AniList's facts
  /// are known for all of them.
  final Set<int>? decades;

  /// Hanj's genres with no finished show yet, in the filter sheet's order.
  List<String> get missingGenres =>
      [for (final g in Achievements.genres) if (!genres.contains(g)) g];
}

/// One plain "next" line: the next level of a count, what you have, and
/// what it takes. Never a bar (decision a).
class NextStep {
  const NextStep(this.ref, this.have);

  final MarkRef ref;
  final int have;

  int get need => ref.step.threshold;
  int get toGo => need - have;

  /// "89 now, 11 to go."
  String get line =>
      '${Achievements.number(have)} now, ${Achievements.number(toGo)} to go.';
}

/// What one evaluation found.
class AchievementResult {
  const AchievementResult({
    required this.marks,
    required this.totals,
    required this.factsComplete,
  });

  /// Every mark the data supports now, by key. Write-once is the caller's
  /// ([Achievements.newOnly]): a mark already in the record is never
  /// rewritten, whatever this says.
  final Map<String, FoundMark> marks;
  final AchievementTotals totals;

  /// Whether AniList's facts were known for every finished show, so the
  /// five rules that need them ran.
  final bool factsComplete;
}

/// A batch's span (D3): first to last, plus a minute.
class BatchSpan {
  const BatchSpan(this.start, this.end, this.size);

  final DateTime start;
  final DateTime end;
  final int size;

  bool contains(DateTime t) => !t.isBefore(start) && !t.isAfter(end);
}

class Achievements {
  Achievements._();

  /// Achievements replace Hanj Cards (Shahid, 2026-11-06: "remove the Hanj
  /// cards and replace it by achievements"). Every Hanj Cards entry point
  /// reads this: Profile's row and its ⋮ entry, the /cards route and the
  /// three card_unlock handlers. False gives Hanj Cards back exactly as they
  /// were; no card file is deleted or changed, and the cards people hold
  /// stay in users/{uid}/cards untouched.
  static const bool replaceCards = true;

  // ── The catalogue ───────────────────────────────────────────────────────

  /// Hanj's 16 genres (D7), the filter sheet's list (hanj_filter_sheet.dart).
  /// AniList's others (Ecchi, Hentai, Mahou Shoujo) don't count.
  static const List<String> genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Horror',
    'Mystery', 'Romance', 'Sci-Fi', 'Slice of Life', 'Sports',
    'Supernatural', 'Thriller', 'Mecha', 'Music', 'Psychological',
  ];

  /// The 22 entries, in each group's order on the page. Carvings follow
  /// decision d: firsts are 1; the tens and most singles 2; a hundred, a
  /// full set or 100 episodes of one show 3; the ends of long ladders and
  /// Founder's plate 4. Finished carves 1, 2, 2, 3, 4, 4, so "your
  /// hundredth" gets the most visible change.
  static const List<Achievement> catalogue = [
    // Milestones
    Achievement(
      id: 'finished',
      name: 'Finished',
      group: AchievementGroup.milestones,
      what: 'How many shows you’ve finished',
      steps: [
        AchievementStep(1, 'First finish', 1),
        AchievementStep(10, '10 finished', 2),
        AchievementStep(50, '50 finished', 2),
        AchievementStep(100, '100 finished', 3),
        AchievementStep(250, '250 finished', 4),
        AchievementStep(500, '500 finished', 4),
      ],
    ),
    Achievement(
      id: 'episodes',
      name: 'Episodes',
      group: AchievementGroup.milestones,
      what: 'How much you’ve watched',
      steps: [
        AchievementStep(100, '100 episodes', 1),
        AchievementStep(1000, '1,000 episodes', 2),
        AchievementStep(5000, '5,000 episodes', 3),
        AchievementStep(10000, '10,000 episodes', 4),
      ],
    ),
    // Taste
    Achievement(
      id: 'sealed',
      name: 'Sealed',
      group: AchievementGroup.taste,
      what: 'How many verdicts you’ve given',
      steps: [
        AchievementStep(1, 'First seal', 1),
        AchievementStep(10, '10 sealed', 2),
        AchievementStep(100, '100 sealed', 3),
      ],
    ),
    Achievement(
      id: 'finished_sealed',
      name: 'Finished and sealed',
      group: AchievementGroup.taste,
      what: 'Judging a show while its ending is fresh',
      steps: [
        AchievementStep(1, 'Finished and sealed', 1),
        AchievementStep(10, '10 finished and sealed', 2),
        AchievementStep(100, '100 finished and sealed', 3),
      ],
    ),
    Achievement(
      id: 'whole_ruler',
      name: 'The whole ruler',
      group: AchievementGroup.taste,
      what: 'Using the whole scale, low to high',
      steps: [AchievementStep(0, 'The whole ruler', 2)],
    ),
    Achievement(
      id: 'against_crowd',
      name: 'Against the crowd',
      group: AchievementGroup.taste,
      what: 'A verdict far from the crowd’s',
      steps: [AchievementStep(0, 'Against the crowd', 2)],
      unlisted: true,
    ),
    // Range
    Achievement(
      id: 'genres',
      name: 'Genres',
      group: AchievementGroup.range,
      what: 'How wide your finished shows range',
      steps: [
        AchievementStep(8, 'Half the genres', 2),
        AchievementStep(16, 'Every genre', 3),
      ],
    ),
    Achievement(
      id: 'decades',
      name: 'Decades',
      group: AchievementGroup.range,
      what: 'How far back you’ve gone',
      steps: [
        AchievementStep(3, 'Three decades', 2),
        AchievementStep(5, 'Five decades', 3),
      ],
    ),
    Achievement(
      id: 'forms',
      name: 'Every form',
      group: AchievementGroup.range,
      what: 'Anime in all its forms',
      steps: [AchievementStep(0, 'Every form', 3)],
    ),
    Achievement(
      id: 'full_year',
      name: 'A full year',
      group: AchievementGroup.range,
      what: 'A year of anime, season by season',
      steps: [AchievementStep(0, 'A full year', 2)],
      keyPrefix: 'year',
    ),
    // Staying with it
    Achievement(
      id: 'long_haul',
      name: 'The long haul',
      group: AchievementGroup.stayingWithIt,
      what: 'A long show seen to the end',
      steps: [AchievementStep(0, 'The long haul', 3)],
    ),
    Achievement(
      id: 'as_it_aired',
      name: 'As it aired',
      group: AchievementGroup.stayingWithIt,
      what: 'A show followed week by week',
      steps: [AchievementStep(0, 'As it aired', 2)],
    ),
    Achievement(
      id: 'second_chance',
      name: 'Second chance',
      group: AchievementGroup.stayingWithIt,
      what: 'A show you dropped, came back to, and finished',
      steps: [AchievementStep(0, 'Second chance', 2)],
    ),
    Achievement(
      id: 'off_watchlist',
      name: 'Off the watchlist',
      group: AchievementGroup.stayingWithIt,
      what: 'Following through on something you saved',
      steps: [AchievementStep(0, 'Off the watchlist', 2)],
    ),
    Achievement(
      id: 'deep_genre',
      name: 'Deep in a genre',
      group: AchievementGroup.stayingWithIt,
      what: 'A genre you keep coming back to',
      steps: [AchievementStep(0, 'Deep in a genre', 2)],
      keyPrefix: 'deep',
    ),
    Achievement(
      id: 'on_the_day',
      name: 'On the day',
      group: AchievementGroup.stayingWithIt,
      what: 'A happy coincidence',
      steps: [AchievementStep(0, 'On the day', 2)],
      unlisted: true,
    ),
    // Your picks
    Achievement(
      id: 'masterpiece',
      name: 'Named a masterpiece',
      group: AchievementGroup.yourPicks,
      what: 'Your highest regard, given',
      steps: [AchievementStep(0, 'Named a masterpiece', 1)],
    ),
    Achievement(
      id: 'hidden_gem',
      name: 'Found a hidden gem',
      group: AchievementGroup.yourPicks,
      what: 'A discovery you vouch for',
      steps: [AchievementStep(0, 'Found a hidden gem', 1)],
    ),
    Achievement(
      id: 'favourite',
      name: 'Marked a favourite',
      group: AchievementGroup.yourPicks,
      what: 'A show you hold close',
      steps: [AchievementStep(0, 'Marked a favourite', 1)],
    ),
    Achievement(
      id: 'top9',
      name: 'Chose your Top 9',
      group: AchievementGroup.yourPicks,
      what: 'Your nine, in your order',
      steps: [AchievementStep(0, 'Chose your Top 9', 2)],
    ),
    Achievement(
      id: 'tier_list',
      name: 'Ranked a cast',
      group: AchievementGroup.yourPicks,
      what: 'A tier list made',
      steps: [AchievementStep(0, 'Ranked a cast', 1)],
    ),
    // Founder
    Achievement(
      id: 'founder',
      name: 'Founder',
      group: AchievementGroup.founder,
      what: 'One of Hanj’s first 50',
      steps: [AchievementStep(0, 'Founder', 4)],
    ),
  ];

  static final Map<String, Achievement> _byId = {
    for (final a in catalogue) a.id: a,
  };

  static Achievement? byId(String id) => _byId[id];

  /// The entries of [group], in page order.
  static List<Achievement> inGroup(AchievementGroup group) =>
      [for (final a in catalogue) if (a.group == group) a];

  /// What a mark key refers to, or null for a key this build doesn't know
  /// (a level added later, read by an older app): it's kept, not shown.
  static MarkRef? parse(String key) {
    final colon = key.indexOf(':');
    final head = colon < 0 ? key : key.substring(0, colon);
    final tail = colon < 0 ? null : key.substring(colon + 1);
    for (final a in catalogue) {
      if (a.keyPrefix != null) {
        if (head == a.keyPrefix && tail != null && tail.isNotEmpty) {
          return MarkRef(a, a.steps.single, tail);
        }
        continue;
      }
      if (head != a.id) continue;
      if (!a.tiered) return tail == null ? MarkRef(a, a.steps.single) : null;
      final threshold = int.tryParse(tail ?? '');
      for (final step in a.steps) {
        if (step.threshold == threshold) return MarkRef(a, step);
      }
      return null;
    }
    return null;
  }

  /// How many achievements these mark keys make: one per entry, however
  /// many levels or repeats it holds. The screen always counts this.
  static int countAchievements(Iterable<String> keys) =>
      {for (final k in keys) ?parse(k)?.achievement.id}.length;

  /// How many achievements the stamp book lists: the 20 listed, Founder only
  /// for founders (decision f).
  static int listedTotal({required bool isFounder}) => catalogue
      .where((a) => !a.unlisted && (isFounder || a.group != AchievementGroup.founder))
      .length;

  /// Hanj Cards that carry into the record (§5 of the design: only cards
  /// whose rule guarantees the new one). Every other card stays in
  /// users/{uid}/cards, unshown (decision e).
  static const Map<String, String> cardCarry = {
    'first_pull': 'finished:1',
    'rated': 'sealed:1',
    'the_critic': 'sealed:10',
    'the_50_club': 'finished:50',
    'the_100_club': 'finished:100',
    // 200 isn't on the ladder; holding it proves 100.
    'the_200_club': 'finished:100',
    // These two and time_traveller could never fire (no year was stored),
    // but a card held is carried.
    'decade_hopper': 'decades:3',
    'decade_scholar': 'decades:5',
    'time_traveller': 'decades:5',
    'resurrection': 'second_chance',
  };

  // ── Rules ───────────────────────────────────────────────────────────────

  /// D3: 5 or more times that follow one another within 60 seconds. An
  /// import writes an entry every fraction of a second; adding one show by
  /// hand takes longer than a minute. Each span runs from its first time to
  /// its last plus a minute.
  static List<BatchSpan> batchesOf(Iterable<DateTime> times) {
    final sorted = times.toList()..sort();
    final spans = <BatchSpan>[];
    var start = 0;
    for (var i = 1; i <= sorted.length; i++) {
      final breaks = i == sorted.length ||
          sorted[i].difference(sorted[i - 1]) > const Duration(seconds: 60);
      if (!breaks) continue;
      if (i - start >= 5) {
        spans.add(BatchSpan(sorted[start],
            sorted[i - 1].add(const Duration(minutes: 1)), i - start));
      }
      start = i;
    }
    return spans;
  }

  /// Every mark the data supports, with its date and deciding entry.
  static AchievementResult evaluate(AchievementInputs input) {
    final entries = [
      for (final e in input.entries.entries) _Entry(e.key, e.value),
    ];
    final batches = [
      ...batchesOf([for (final e in entries) ?e.addedAt]),
      if (input.activity != null)
        ...batchesOf([for (final t in input.activity!.values) ?t]),
    ];
    bool inBatch(DateTime t) => batches.any((b) => b.contains(t));

    final found = <String, FoundMark>{};

    // A mark decided by [e] at [at]. Inside a batch the order is unknown,
    // so it came with your list and names no show (D10); [exact] says
    // whether the date is the day it happened or only an upper bound.
    void put(String key, _Entry e, DateTime at, {bool exact = true}) {
      final how = inBatch(at)
          ? MarkHow.withList
          : exact
              ? MarkHow.onDay
              : MarkHow.by;
      found[key] = FoundMark(
        key,
        RecordMark(at: at, how: how, show: how == MarkHow.onDay ? e.id : null),
        e.id,
      );
    }

    // D1, D2: finished shows in the order they were finished, ties by title.
    // One with no date yet (a pending server timestamp) waits for it.
    final finished = _ordered(
        entries.where((e) => e.finished), (e) => e.finishedAt);

    // Finished.
    for (final step in byId('finished')!.steps) {
      if (finished.length < step.threshold) break;
      final (e, at) = finished[step.threshold - 1];
      put('finished:${step.threshold}', e, at);
    }

    // Episodes (D4), walking entries by their latest date. Episodes pile up
    // before an entry's latest date, so the date is only "by", and the show
    // is named only when it's the one you just moved on.
    final byLatest = _ordered(entries, (e) => e.latest ?? input.now);
    var running = 0;
    var episodeSteps = byId('episodes')!.steps.toList();
    for (final (e, at) in byLatest) {
      running += e.episodesWatched;
      while (episodeSteps.isNotEmpty && running >= episodeSteps.first.threshold) {
        put('episodes:${episodeSteps.first.threshold}', e, at,
            exact: input.live.contains(e.id) && e.latest != null);
        episodeSteps = episodeSteps.sublist(1);
      }
    }
    final totalEpisodes = entries.fold<int>(0, (sum, e) => sum + e.episodesWatched);

    // Genres and Deep in a genre, along the finished shows.
    final seenGenres = <String>{};
    final byGenre = <String, int>{};
    for (final (e, at) in finished) {
      for (final g in e.genres) {
        if (!genres.contains(g)) continue;
        final added = seenGenres.add(g);
        final count = byGenre[g] = (byGenre[g] ?? 0) + 1;
        if (count == 25) put('deep:$g', e, at);
        if (added && seenGenres.length == 8) put('genres:8', e, at);
        if (added && seenGenres.length == 16) put('genres:16', e, at);
      }
    }

    // The five rules that need AniList's facts (D8), once every finished
    // show's are known.
    final factsComplete = finished.every((f) {
      final id = int.tryParse(f.$1.id);
      return id == null || input.facts.containsKey(id);
    });
    ShowFacts? factsOf(_Entry e) {
      final id = int.tryParse(e.id);
      return id == null ? null : input.facts[id];
    }

    Set<int>? decades;
    if (factsComplete) {
      decades = {};
      final forms = <String>{};
      final seasons = <int, Set<String>>{};
      for (final (e, at) in finished) {
        final f = factsOf(e);
        if (f == null) continue;
        final year = f.year;
        if (year != null && decades.add(year ~/ 10)) {
          if (decades.length == 3) put('decades:3', e, at);
          if (decades.length == 5) put('decades:5', e, at);
        }
        final form = _formOf(f.format);
        if (form != null && forms.add(form) && forms.length == 4) {
          put('forms', e, at);
        }
        final season = f.season, seasonYear = f.seasonYear;
        if (season != null && seasonYear != null && _seasons.contains(season)) {
          final inYear = seasons.putIfAbsent(seasonYear, () => {});
          if (inYear.add(season) && inYear.length == 4) {
            put('year:$seasonYear', e, at);
          }
        }
      }

      // On the day (unlisted): finished outside a batch on the day and
      // month it first aired, in a later year.
      for (final (e, at) in finished) {
        final start = ShowFacts.dayOf(factsOf(e)?.startDate);
        if (start == null || inBatch(at)) continue;
        if (at.month == start.month && at.day == start.day && at.year > start.year) {
          put('on_the_day', e, at);
          break;
        }
      }
    }

    // The long haul: a finished show of 100 episodes or more.
    for (final (e, at) in finished) {
      if ((e.episodes ?? e.current ?? 0) >= 100) {
        put('long_haul', e, at);
        break;
      }
    }

    // The three rules that read the activity log (D9).
    final activity = input.activity;
    if (activity != null) {
      DateTime? logged(String type, _Entry e) => activity['${type}_${e.id}'];
      bool has(String type, _Entry e) => activity.containsKey('${type}_${e.id}');

      // Second chance: dropped, then finished.
      for (final (e, at) in finished) {
        if (has('DROPPED', e)) {
          put('second_chance', e, at);
          break;
        }
      }

      // Off the watchlist: finished six months or more after it went on it.
      for (final (e, at) in finished) {
        final saved = logged('PLAN_TO_WATCH', e);
        if (saved != null && at.difference(saved) >= const Duration(days: 182)) {
          put('off_watchlist', e, at);
          break;
        }
      }

      // As it aired: on Watching before its final episode's day, and
      // finished outside a batch from a day before that day to 14 after.
      // With no Completed in the log it was finished by +1, so the time it
      // was added is when it was started.
      if (factsComplete) {
        for (final (e, at) in finished) {
          final end = ShowFacts.dayOf(factsOf(e)?.endDate);
          if (end == null || inBatch(at)) continue;
          final started = logged('WATCHING', e) ??
              (has('COMPLETED', e) ? null : e.addedAt);
          if (started == null || !started.isBefore(end)) continue;
          if (at.isBefore(end.subtract(const Duration(days: 1)))) continue;
          if (!at.isBefore(end.add(const Duration(days: 15)))) continue;
          put('as_it_aired', e, at);
          break;
        }
      }
    }

    // Your picks: the shelves and the Favourite mark, dated by when the tag
    // was set. One set by the status sheet before tagsUpdatedAt existed is
    // dated "by" the entry's latest write, which set it.
    void firstTagged(String key, bool Function(_Entry e) on, DateTime? Function(_Entry e) when) {
      final dated = _ordered(entries.where(on), (e) => when(e) ?? e.latest);
      if (dated.isEmpty) return;
      final (e, at) = dated.first;
      put(key, e, at, exact: when(e) != null);
    }

    firstTagged('masterpiece', (e) => HanjShelves.shelfOf(e.tags) == HanjShelves.masterpiece,
        (e) => e.tagsUpdatedAt);
    if (HanjShelves.favouritesApart) {
      firstTagged('hidden_gem', (e) => HanjShelves.shelfOf(e.tags) == HanjShelves.hiddenGems,
          (e) => e.tagsUpdatedAt);
    }
    firstTagged('favourite', (e) => HanjShelves.isFavourite(e.tags),
        (e) => e.favouritedAt ?? e.tagsUpdatedAt);

    // Chose your Top 9: dated by top9At, else "by" the day the phone sees it.
    final top9 = input.top9;
    if (top9 != null && top9.length == 9) {
      final at = input.top9At ?? input.now;
      found['top9'] = FoundMark(
        'top9',
        RecordMark(
          at: at,
          how: input.top9At != null ? MarkHow.onDay : MarkHow.by,
          show: input.top9At != null ? top9.first : null,
        ),
        'user:top9',
      );
    }

    // Ranked a cast: the first tier list on this device with 5 or more placed.
    final lists = [
      for (final t in input.tierLists ?? const <TierListFact>[])
        if (t.ranked >= 5) t,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (lists.isNotEmpty) {
      final t = lists.first;
      found['tier_list'] = FoundMark(
        'tier_list',
        RecordMark(at: t.createdAt, how: MarkHow.onDay, n: t.ranked),
        'tier:${t.id}',
      );
    }

    // Seals (D5), each dated by ratedAt (D6). An imported seal has none: it
    // is placed at its entry's batch, else "by" the entry's latest write.
    final seals = _ordered(entries.where((e) => e.seal != null), (e) {
      final ratedAt = e.ratedAt;
      if (ratedAt != null) return ratedAt;
      final added = e.addedAt;
      if (added != null && inBatch(added)) return added;
      return e.latest ?? input.now;
    });

    // Sealed.
    for (final step in byId('sealed')!.steps) {
      if (seals.length < step.threshold) break;
      final (e, at) = seals[step.threshold - 1];
      put('sealed:${step.threshold}', e, at, exact: e.ratedAt != null);
    }

    // The whole ruler: seals in each third, 4 or below, 4.5 to 7, 7.5 up.
    final thirds = <int>{};
    for (final (e, at) in seals) {
      final s = e.seal!;
      if (thirds.add(s <= 4 ? 0 : (s <= 7 ? 1 : 2)) && thirds.length == 3) {
        put('whole_ruler', e, at, exact: e.ratedAt != null);
        break;
      }
    }

    // Finished and sealed: sealed in Hanj within six hours of finishing,
    // outside a batch (Home's "finishedThen").
    final finishedSealed = _ordered(
      entries.where((e) {
        final f = e.finishedAt, r = e.ratedAt;
        return e.finished &&
            e.seal != null &&
            f != null &&
            r != null &&
            !inBatch(f) &&
            r.difference(f).inMinutes.abs() <= 6 * 60;
      }),
      (e) => e.ratedAt,
    );
    for (final step in byId('finished_sealed')!.steps) {
      if (finishedSealed.length < step.threshold) break;
      final (e, at) = finishedSealed[step.threshold - 1];
      put('finished_sealed:${step.threshold}', e, at);
    }

    // Against the crowd (unlisted): a seal given in Hanj 3 or more from the
    // crowd's average.
    for (final (e, at) in _ordered(entries, (e) => e.ratedAt)) {
      final seal = e.seal, crowd = e.average;
      if (seal == null || crowd == null || crowd <= 0) continue;
      if ((seal - crowd / 10).abs() >= 3) {
        put('against_crowd', e, at);
        break;
      }
    }

    // Founder: one of the first 50.
    if (input.isFounder && input.founderNumber != null) {
      final joined = input.founderJoinedAt;
      found['founder'] = FoundMark(
        'founder',
        RecordMark(
          at: joined ?? input.now,
          how: joined != null ? MarkHow.onDay : MarkHow.by,
          n: input.founderNumber,
        ),
        'user:founder',
      );
    }

    // Hanj Cards held carry in with their dates when those are earlier
    // (§8.6); a card's date is classified like any other (D3).
    final cards = input.cards;
    if (cards != null) {
      final carried = <String, (String, DateTime?)>{};
      for (final card in cards.entries) {
        final key = cardCarry[card.key];
        if (key == null) continue;
        final had = carried[key];
        final at = card.value;
        if (had == null || (at != null && (had.$2 == null || at.isBefore(had.$2!)))) {
          carried[key] = (card.key, at);
        }
      }
      for (final c in carried.entries) {
        final (cardId, at) = c.value;
        final phone = found[c.key];
        if (phone != null && (at == null || !at.isBefore(phone.mark.at))) continue;
        found[c.key] = FoundMark(
          c.key,
          RecordMark(
            at: at ?? input.now,
            how: at == null
                ? MarkHow.by
                : (inBatch(at) ? MarkHow.withList : MarkHow.onDay),
            card: true,
          ),
          'card:$cardId',
        );
      }
    }

    return AchievementResult(
      marks: found,
      factsComplete: factsComplete,
      totals: AchievementTotals(
        finished: entries.where((e) => e.finished).length,
        episodes: totalEpisodes,
        sealed: entries.where((e) => e.seal != null).length,
        finishedSealed: finishedSealed.length,
        genres: seenGenres,
        byGenre: byGenre,
        decades: decades,
      ),
    );
  }

  /// Write-once (principle 4): the marks in [found] that [existing] doesn't
  /// hold. A mark already written keeps its date and show for good, even if
  /// the show is removed or the rules would date it differently today.
  static Map<String, FoundMark> newOnly(
          Map<String, RecordMark> existing, Map<String, FoundMark> found) =>
      {
        for (final e in found.entries)
          if (!existing.containsKey(e.key)) e.key: e.value,
      };

  /// The next level of each count, nearest first: plain lines for the
  /// page's "Next" (decision a), never a bar.
  static List<NextStep> nextSteps(AchievementTotals totals, Set<String> earned) {
    final have = <String, int>{
      'finished': totals.finished,
      'episodes': totals.episodes,
      'sealed': totals.sealed,
      'finished_sealed': totals.finishedSealed,
      'genres': totals.genres.length,
      if (totals.decades != null) 'decades': totals.decades!.length,
    };
    final out = <NextStep>[];
    for (final h in have.entries) {
      final a = byId(h.key)!;
      for (final step in a.steps) {
        if (earned.contains(a.keyFor(step)) || h.value >= step.threshold) continue;
        out.add(NextStep(MarkRef(a, step), h.value));
        break;
      }
    }
    out.sort((a, b) => (b.have / b.need).compareTo(a.have / a.need));
    return out;
  }

  // ── Words ───────────────────────────────────────────────────────────────

  /// A mark's line in the journal voice (design §3.1). [show] looks up the
  /// named show's title and, where the line quotes them, your seal and the
  /// crowd's score; a show no longer on the list is left unnamed.
  static String line(String key, RecordMark mark, {ShowNote? Function(String id)? show}) {
    final ref = parse(key);
    if (ref == null) return '';
    final note = mark.show == null || show == null ? null : show(mark.show!);
    final title = note?.title;
    final t = ref.step.threshold;
    switch (ref.achievement.id) {
      case 'finished':
        final nth = t == 1 ? 'first' : ordinal(t);
        if (title != null) return 'Your $nth finished show: $title.';
        if (mark.how == MarkHow.withList) return 'Your $nth finished show came with your list.';
        return 'Your $nth finished show.';
      case 'episodes':
        final words = {100: 'hundredth', 1000: 'thousandth', 5000: 'five-thousandth', 10000: 'ten-thousandth'}[t];
        return title != null && words != null
            ? '${number(t)} episodes. The $words came during $title.'
            : '${number(t)} episodes.';
      case 'genres':
        if (t == 16) {
          return title != null
              ? 'Every genre. The last came with $title.'
              : 'Finished shows in every one of Hanj’s 16 genres.';
        }
        return 'Finished shows in $t of Hanj’s 16 genres.';
      case 'decades':
        final n = t == 3 ? 'three' : 'five';
        return title != null
            ? 'Finished shows from $n decades. The last to join: $title.'
            : 'Finished shows from $n decades.';
      case 'forms':
        return title != null
            ? 'A series, a film, an OVA and a web series, all finished. The last of the four: $title.'
            : 'A series, a film, an OVA and a web series, all finished.';
      case 'full_year':
        return '${ref.param} in four seasons: a show from each, finished.';
      case 'long_haul':
        final eps = note?.episodes;
        return title != null && eps != null
            ? '$title, all ${number(eps)} episodes.'
            : 'A show of 100 episodes or more, seen to the end.';
      case 'as_it_aired':
        return 'You followed ${title ?? 'a show'} as it aired and finished it '
            'the week its last episode came out.';
      case 'second_chance':
        return 'You dropped ${title ?? 'a show'}, came back, and finished it.';
      case 'off_watchlist':
        return '${title ?? 'A show'}, finished six months or more after it went on your watchlist.';
      case 'deep_genre':
        return title != null
            ? 'Deep in ${ref.param}: 25 finished. The 25th: $title.'
            : 'Deep in ${ref.param}: 25 finished.';
      case 'masterpiece':
        return title != null ? 'Your first Masterpiece: $title.' : 'Your first Masterpiece.';
      case 'hidden_gem':
        return title != null ? 'Your first hidden gem: $title.' : 'Your first hidden gem.';
      case 'favourite':
        return title != null ? 'Your first favourite: $title.' : 'Your first favourite.';
      case 'top9':
        return title != null
            ? 'Your Top 9, chosen and ordered by you. Number one: $title.'
            : 'Your Top 9, chosen and ordered by you.';
      case 'tier_list':
        final n = mark.n;
        return n != null
            ? 'Your first tier list: $n characters, ranked.'
            : 'Your first tier list.';
      case 'sealed':
        final r = note?.rating;
        final nth = t == 1 ? 'first' : ordinal(t);
        return title != null && r != null
            ? 'Your $nth seal: ${sealText(r)} for $title.'
            : 'Your $nth seal.';
      case 'finished_sealed':
        final r = note?.rating;
        if (t == 1) {
          return title != null && r != null
              ? 'Finished and sealed the same night: $title, ${sealText(r)}.'
              : 'Finished and sealed the same night.';
        }
        return title != null
            ? '$t shows finished and sealed the same night. The ${ordinal(t)}: $title.'
            : '$t shows finished and sealed the same night.';
      case 'whole_ruler':
        return 'Your seals run the whole ruler, from 4 or below to 7.5 and up.';
      case 'founder':
        return 'Founder #${mark.n ?? ''}, one of the first 50 people on Hanj.';
      case 'against_crowd':
        final r = note?.rating, crowd = note?.crowd;
        return title != null && r != null && crowd != null
            ? 'You sealed $title at ${sealText(r)}. The crowd gives it ${(crowd / 10).toStringAsFixed(1)}.'
            : 'A verdict 3 or more from the crowd’s.';
      case 'on_the_day':
        final year = note?.startYear;
        final years = year == null ? null : mark.at.year - year;
        return title != null && years != null
            ? 'You finished $title on ${mark.at.day} ${_months[mark.at.month - 1]}, '
                '$years ${years == 1 ? 'year' : 'years'} to the day after it first aired.'
            : 'You finished a show on the day it first aired, years later.';
    }
    return ref.title;
  }

  /// A mark's date in the three forms (§7.1), or as a carried card's.
  static String dateLine(RecordMark mark) {
    final day = date(mark.at);
    if (mark.card && mark.how == MarkHow.onDay) return 'Earned as a Hanj Card on $day';
    if (mark.card && mark.how == MarkHow.by) return 'Earned as a Hanj Card';
    return switch (mark.how) {
      MarkHow.onDay => day,
      MarkHow.by => 'By $day',
      MarkHow.withList => 'Came with your list, $day',
    };
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  /// "3 November 2026".
  static String date(DateTime at) => '${at.day} ${_months[at.month - 1]} ${at.year}';

  /// "4,541".
  static String number(int n) {
    final digits = n.abs().toString();
    final out = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  /// "100th", "1st", "22nd".
  static String ordinal(int n) {
    final teen = n % 100 >= 11 && n % 100 <= 13;
    final suffix = teen
        ? 'th'
        : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '${number(n)}$suffix';
  }

  /// A seal as Hanj writes it: "8.5", "9".
  static String sealText(double rating) {
    final step = (rating * 2).round() / 2;
    return step == step.roundToDouble() ? '${step.toInt()}' : '$step';
  }

  static const _seasons = {'WINTER', 'SPRING', 'SUMMER', 'FALL'};

  /// AniList's format as one of the four forms "Every form" asks for.
  static String? _formOf(String? format) => switch (format) {
        'TV' || 'TV_SHORT' => 'series',
        'MOVIE' => 'film',
        'OVA' || 'SPECIAL' => 'ova',
        'ONA' => 'web',
        _ => null,
      };

  /// [items] with a date, oldest first; ties by title, then id, so the
  /// order never shuffles between evaluations.
  static List<(_Entry, DateTime)> _ordered(
      Iterable<_Entry> items, DateTime? Function(_Entry e) when) {
    final out = [
      for (final e in items)
        if (when(e) case final DateTime at) (e, at),
    ];
    out.sort((a, b) {
      final byDate = a.$2.compareTo(b.$2);
      if (byDate != 0) return byDate;
      final byTitle = a.$1.title.toLowerCase().compareTo(b.$1.title.toLowerCase());
      return byTitle != 0 ? byTitle : a.$1.id.compareTo(b.$1.id);
    });
    return out;
  }
}

/// What a line needs to know of a named show.
class ShowNote {
  const ShowNote({
    required this.title,
    this.rating,
    this.crowd,
    this.episodes,
    this.startYear,
  });

  final String title;

  /// Your rating, as stored.
  final double? rating;

  /// The crowd's averageScore, 0–100, as list entries store it.
  final double? crowd;
  final int? episodes;
  final int? startYear;
}

/// One list entry, as the rules read it.
class _Entry {
  _Entry(this.id, Map<String, Object?> data)
      : title = data['title'] is String ? data['title'] as String : '',
        status = data['status'],
        addedAt = _date(data['addedAt']),
        lastWatched = _date(data['lastWatched']),
        ratedAt = _date(data['ratedAt']),
        tagsUpdatedAt = _date(data['tagsUpdatedAt']),
        favouritedAt = _date(data['favouritedAt']),
        episodes = _int(data['episodes']),
        current = _int(data['currentEpisode']),
        rating = _double(data['userRating']),
        average = _double(data['averageScore']),
        genres = [
          for (final g in (data['genres'] is List ? data['genres'] as List : const []))
            if (g is String) g,
        ],
        tags = data['tags'];

  final String id;
  final String title;
  final Object? status;
  final DateTime? addedAt;
  final DateTime? lastWatched;
  final DateTime? ratedAt;
  final DateTime? tagsUpdatedAt;
  final DateTime? favouritedAt;
  final int? episodes;
  final int? current;
  final double? rating;
  final double? average;
  final List<String> genres;
  final Object? tags;

  /// D1.
  bool get finished => status == 'COMPLETED';

  /// D2: lastWatched, which the write that completes a show stamps.
  DateTime? get finishedAt => finished ? (lastWatched ?? addedAt) : null;

  /// The entry's latest write that the rules can see.
  DateTime? get latest {
    final a = addedAt, w = lastWatched;
    if (a == null) return w;
    if (w == null) return a;
    return w.isAfter(a) ? w : a;
  }

  /// D4, Profile's definition: a finished show with a known total counts
  /// its total; any other its current episode.
  int get episodesWatched {
    final total = episodes, now = current;
    if (finished && total != null) return total;
    return now ?? 0;
  }

  /// D5: the rating at its nearest half step on Hanj's 1–10 ruler; null for
  /// none, or one off the ruler (imported on a 100-point scale).
  double? get seal {
    final r = rating;
    if (r == null) return null;
    final step = (r * 2).round() / 2;
    return step >= 1 && step <= 10 ? step : null;
  }

  static DateTime? _date(Object? value) => switch (value) {
        DateTime() => value,
        int() => DateTime.fromMillisecondsSinceEpoch(value),
        _ => null,
      };

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static double? _double(Object? value) => value is num ? value.toDouble() : null;
}
