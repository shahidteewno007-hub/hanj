import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/theme/app_theme.dart';
import '../../models/achievements.dart';
import '../../models/anime_model.dart';
import '../../models/hanj_shelves.dart';
import '../../services/achievements_service.dart';
import '../../widgets/hanko_badge.dart';
import '../../widgets/hanko_cover_colour.dart';
import '../../widgets/hanko_field.dart';
import '../../widgets/hanko_paper.dart';
import '../../widgets/hanko_print.dart';
import '../../widgets/hanko_seal.dart';
import '../anime_detail/anime_detail_screen.dart';
import '../profile/profile_screen.dart' show ProfileScreen;
import '../search/search_screen.dart';

/// Achievements (r9 stage 3; Shahid, 2026-11-10: "Stamp book, prints on
/// mats", "Yes, build it"): your record, as a stamp book.
///
/// Every achievement has a fixed space, in a fixed order, under the six
/// headings (decision j). Earning one fills its space in: a print of the
/// show behind it, on a mat of that show's own colour, with the badge
/// pressed across the print's corner, the way your seal is pressed onto
/// prints everywhere else in Print Room. A space you haven't earned stays
/// dark and dashed. Nothing reshuffles when you earn something, so the same
/// glance finds the same place every visit (spatial memory).
///
/// The top is your latest achievement on its show's colour, then the count
/// ("You've earned 15 of 20": achievements, never marks) and the three
/// nearest next steps, as plain lines with no bars (decision a: show the
/// fact, not the meter). On day one, before anything has been earned live,
/// the top is a still paper card, "Your record so far" (decision g), with
/// no animation: a past event isn't celebrated as if it had just happened.
///
/// Tapping a space opens its sheet: the record slip on paper (paper is
/// earned: a not-yet sheet has none), the levels as a row of stamps with
/// the next one in words, and the shows behind it as prints. The sheet's
/// "On your profile" choice is stage 5's, not this one.
///
/// The record itself is AchievementsService's (worked out on the phone from
/// the list). This page reads the list once more for the shows' titles and
/// covers, feeds each snapshot to the service, and asks it to refresh. A
/// snapshot from the cache doesn't count as confirmed (the service's rule:
/// the cache can hold part of a list), so the refresh reads the list once
/// from the server while the record needs it.
/// Opened from Profile's row, from the /cards route while
/// [Achievements.replaceCards] is on, and from a tapped card_unlock
/// notification.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();

  /// The badge you've just chosen to show (stage 5), until Profile has
  /// pressed it onto your monogram's corner: the press plays once, when
  /// you're back on Profile, never on an ordinary visit. Null otherwise.
  static String? pressOnProfile;

  /// The record's latest mark: the newest date, and on a tie (day one's
  /// marks can share a day) the deepest carving, so the most visible badge
  /// leads. Null for an empty record.
  static String? latestKey(AchievementRecord record) {
    String? best;
    RecordMark? bestMark;
    var bestCarving = 0;
    for (final e in record.marks.entries) {
      final ref = Achievements.parse(e.key);
      if (ref == null) continue;
      final m = e.value;
      final later = bestMark == null ||
          m.at.isAfter(bestMark.at) ||
          (m.at == bestMark.at && ref.carving > bestCarving);
      if (later) {
        best = e.key;
        bestMark = m;
        bestCarving = ref.carving;
      }
    }
    return best;
  }

  /// Profile's Achievements row: its line, in plain words with no dot or
  /// count bubble (lead §4). What's new comes first, since it's what changed;
  /// then day one; then the count and the latest.
  static String rowLine(AchievementsState s) {
    final record = s.record;
    if (!s.known || record.count == 0) {
      return 'Earned by what you log, from your first show';
    }
    final fresh = Achievements.countAchievements(s.newKeys);
    if (fresh > 0) return '$fresh new since you last looked';
    final count = record.count;
    if (record.dayOne) {
      return 'Your record so far: $count ${count == 1 ? 'achievement' : 'achievements'}';
    }
    final latest = latestKey(record);
    final title = latest == null ? null : Achievements.parse(latest)?.title;
    return title == null
        ? '$count in your record'
        : '$count in your record · latest: $title';
  }

  /// Profile's Achievements row: its icon, the badge you show or else your
  /// latest, at 24 dp in the rows' stone (the small cut). Dashed for a
  /// record with nothing in it yet.
  static Widget rowIcon(AchievementsState s) {
    final key = s.badge ?? latestKey(s.record);
    final ref = key == null ? null : Achievements.parse(key);
    if (key == null || ref == null) {
      return const HankoBadge(
        id: 'finished',
        size: 24,
        state: HankoBadgeState.notYet,
        semanticLabel: 'Badge, not yet earned',
      );
    }
    return HankoBadge(
      id: ref.achievement.id,
      tier: ref.carving,
      size: 24,
      ink: AppTheme.hankoStone,
      number: ref.achievement.id == 'founder' ? s.record.marks[key]?.n : null,
      semanticLabel: 'Badge: ${ref.title}',
    );
  }

  /// One achievement's sheet, over whatever screen you're on: the unlock
  /// slip's "See" (stage 4) opens it where you earned it, without leaving
  /// Detail or Home (lead §5.2). It reads the list and your user document
  /// for the sheet's shows and your name, from the phone's cache first
  /// (Detail and Home have just read them), and from the server only when
  /// the cache has nothing. Never throws; offline with nothing cached, the
  /// sheet opens with the record alone.
  static Future<void> showSheet(BuildContext context, String key) async {
    final ref = Achievements.parse(key);
    final user = FirebaseAuth.instance.currentUser;
    if (ref == null || user == null) return;
    final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    Future<T?> cacheFirst<T>(
        Future<T> Function(GetOptions options) read, bool Function(T) empty) async {
      try {
        final cached = await read(const GetOptions(source: Source.cache));
        if (!empty(cached)) return cached;
      } catch (_) {}
      try {
        return await read(const GetOptions());
      } catch (_) {
        return null;
      }
    }

    final list = await cacheFirst<QuerySnapshot<Map<String, dynamic>>>(
        (o) => doc.collection('animeList').get(o), (s) => s.docs.isEmpty);
    final me = await cacheFirst<DocumentSnapshot<Map<String, dynamic>>>(
        (o) => doc.get(o), (d) => !d.exists);
    if (!context.mounted) return;
    final data = me?.data() ?? const <String, dynamic>{};
    final top9 = data['top9'];
    final shown = data['displayName'];
    final name = shown is String && shown.trim().isNotEmpty
        ? shown.trim()
        : (user.displayName ?? '');
    final avatar = data['avatarImageUrl'];
    final s = AchievementsService.instance.state.value;
    final held = _Held.of(s.record);
    final shows = _Shows(
      {for (final d in list?.docs ?? const []) d.id: d.data()},
      top9 is List ? [for (final id in top9) '$id'] : const [],
    )..spread(held);
    final still = MediaQuery.disableAnimationsOf(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.hankoSumi2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.hankoSheetRadius)),
      ),
      sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
      builder: (sheetContext) => _Sheet(
        held: held[ref.achievement.id]!,
        shows: shows,
        totals: s.totals,
        factsComplete: s.factsComplete,
        name: name,
        avatarUrl: avatar is String ? avatar : null,
      ),
    );
  }
}

// ── Measures ──────────────────────────────────────────────────────────────

/// The gap between spaces, across.
const double _gap = 12;

/// A space's width three across on the 360 dp phone (the CPH2573), inside
/// the 20 dp gutters: 98.7 dp. Wider windows take more columns at this width,
/// never wider spaces (lead §2.5).
const double _space3 = (360 - 2 * AppTheme.hankoGutter - 2 * _gap) / 3;

/// The same, two across: where large text would split a word (lead §2.5).
const double _space2 = (360 - 2 * AppTheme.hankoGutter - _gap) / 2;

/// The badge on a space and on a "Next" row.
const double _spaceBadge = 50;

/// A non-breaking space, so "4 Nov", "By 4 Nov" and "of 20" never split.
final String _nb = String.fromCharCode(0xA0);

const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct',
  'Nov', 'Dec',
];

/// Counts up to twenty in words, as Hanj's journal sentences spell them.
const _countWords = [
  'No', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight',
  'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
  'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen', 'Twenty',
];

/// How each one is earned, in one plain sentence, for a sheet you haven't
/// earned yet (lead §3.1).
const Map<String, String> _howTo = {
  'finished': 'Finish a show: set it to Completed, or log its last episode.',
  'episodes': 'Every episode you log counts, and a finished show counts all of its episodes.',
  'sealed': 'Rate a show on the ruler.',
  'finished_sealed': 'Rate a show within six hours of finishing it.',
  'whole_ruler': 'Seal shows across the whole ruler: one at 4 or below, one from 4.5 to 7, and one at 7.5 or above.',
  'genres': 'Finish shows in 8 of Hanj’s 16 genres, then in all 16.',
  'decades': 'Finish shows that first aired in three different decades, then in five.',
  'forms': 'Finish a series, a film, an OVA or special, and a web series.',
  'full_year': 'Finish a show from each season of one year: winter, spring, summer and fall.',
  'long_haul': 'Finish a show of 100 episodes or more.',
  'as_it_aired': 'Follow a show while it airs, and finish it within two weeks of its last episode.',
  'second_chance': 'Drop a show, come back to it, and finish it.',
  'off_watchlist': 'Finish a show six months or more after it went on your watchlist.',
  'deep_genre': 'Finish 25 shows in one genre.',
  'masterpiece': 'Put a show on your Masterpiece shelf.',
  'hidden_gem': 'Put a show on your Hidden gems shelf.',
  'favourite': 'Mark a show as one of your favourites.',
  'top9': 'Choose and order your Top 9 in Ranking Cards.',
  'tier_list': 'Make a tier list with 5 or more characters placed in tiers.',
  'founder': 'One of the first 50 people on Hanj.',
};

/// The entries that need AniList's facts about each show (format, season,
/// air dates). Until the phone has them for every finished show, their
/// spaces say so instead of a count (lead §2.4).
const Set<String> _needsFacts = {'decades', 'forms', 'full_year', 'as_it_aired'};

// ── What the page knows ───────────────────────────────────────────────────

/// One achievement as your record holds it: its marks, highest level (or,
/// for the two that repeat, the newest instance) first.
class _Held {
  _Held(this.achievement, this.marks);

  final Achievement achievement;

  /// (key, ref, mark), the top one first.
  final List<(String, MarkRef, RecordMark)> marks;

  bool get earned => marks.isNotEmpty;
  String get topKey => marks.first.$1;
  MarkRef get top => marks.first.$2;
  RecordMark get topMark => marks.first.$3;

  /// The keys held, for the levels row.
  Set<String> get keys => {for (final m in marks) m.$1};

  static Map<String, _Held> of(AchievementRecord record) {
    final by = <String, List<(String, MarkRef, RecordMark)>>{};
    for (final e in record.marks.entries) {
      final ref = Achievements.parse(e.key);
      if (ref == null) continue;
      by.putIfAbsent(ref.achievement.id, () => []).add((e.key, ref, e.value));
    }
    return {
      for (final a in Achievements.catalogue)
        a.id: _Held(
          a,
          (by[a.id] ?? [])
            ..sort((x, y) {
              if (a.repeats) return y.$3.at.compareTo(x.$3.at);
              return y.$2.step.threshold.compareTo(x.$2.step.threshold);
            }),
        ),
    };
  }
}

/// The list as this page read it, for the shows behind each achievement:
/// titles, covers, ratings. Entries keyed by their id (the AniList id).
class _Shows {
  _Shows(this.entries, this.top9);

  static final empty = _Shows(const {}, const []);

  final Map<String, Map<String, dynamic>> entries;

  /// Your Top 9's ids, in your order (users/{uid}.top9).
  final List<String> top9;

  String? cover(String? id) {
    final url = entries[id]?['imageUrl'];
    return url is String && url.isNotEmpty ? url : null;
  }

  String title(String id) {
    final t = entries[id]?['title'];
    return t is String && t.isNotEmpty ? t : 'A show';
  }

  ShowNote? note(String id) {
    final e = entries[id];
    if (e == null) return null;
    final t = e['title'];
    if (t is! String || t.isEmpty) return null;
    return ShowNote(
      title: t,
      rating: (e['userRating'] as num?)?.toDouble(),
      crowd: (e['averageScore'] as num?)?.toDouble(),
      episodes: (e['episodes'] as num?)?.toInt(),
    );
  }

  static DateTime? _when(Object? v) => v is Timestamp ? v.toDate() : null;

  static bool _finished(Map<String, dynamic> e) => e['status'] == 'COMPLETED';

  /// D5: a rating on Hanj's ruler, at its nearest half step.
  static double? _seal(Map<String, dynamic> e) {
    final r = (e['userRating'] as num?)?.toDouble();
    if (r == null) return null;
    final step = (r * 2).round() / 2;
    return step >= 1 && step <= 10 ? step : null;
  }

  /// D4, Profile's definition.
  static int _episodes(Map<String, dynamic> e) {
    final total = (e['episodes'] as num?)?.toInt();
    final now = (e['currentEpisode'] as num?)?.toInt();
    if (_finished(e) && total != null) return total;
    return now ?? 0;
  }

  /// The shows behind an achievement that the list alone can name, newest
  /// first. Decades and Every form count every finished show, so those are
  /// theirs. The ones that need the activity log or a season (a drop and a
  /// return, a full year) name only their deciding show, so their sheet
  /// never lists shows that don't belong.
  List<String> behind(Achievement a, String? param) {
    bool Function(Map<String, dynamic> e)? test;
    var bySeal = false;
    switch (a.id) {
      case 'finished' || 'decades' || 'forms':
        test = _finished;
      case 'episodes':
        test = (e) => _episodes(e) > 0;
      case 'sealed' || 'whole_ruler':
        test = (e) => _seal(e) != null;
        bySeal = true;
      case 'finished_sealed':
        test = (e) {
          final rated = _when(e['ratedAt']);
          final done = _when(e['lastWatched']);
          return _finished(e) &&
              _seal(e) != null &&
              rated != null &&
              done != null &&
              rated.difference(done).abs() <= const Duration(hours: 6);
        };
        bySeal = true;
      case 'genres':
        test = (e) =>
            _finished(e) &&
            ((e['genres'] as List?) ?? const []).any(Achievements.genres.contains);
      case 'deep_genre':
        test = (e) =>
            _finished(e) && ((e['genres'] as List?) ?? const []).contains(param);
      case 'long_haul':
        test = (e) =>
            _finished(e) &&
            (((e['episodes'] ?? e['currentEpisode']) as num?)?.toInt() ?? 0) >= 100;
      case 'masterpiece':
        test = (e) => HanjShelves.shelfOf(e['tags']) == HanjShelves.masterpiece;
      case 'hidden_gem':
        test = (e) => HanjShelves.shelfOf(e['tags']) == HanjShelves.hiddenGems;
      case 'favourite':
        test = (e) => HanjShelves.isFavourite(e['tags']);
      case 'top9':
        return [for (final id in top9) if (entries.containsKey(id)) id];
    }
    if (test == null) return const [];
    DateTime when(Map<String, dynamic> e) =>
        (bySeal ? _when(e['ratedAt']) : null) ??
        _when(e['lastWatched']) ??
        _when(e['addedAt']) ??
        DateTime(2000);
    final ids = [
      for (final e in entries.entries)
        if (test(e.value)) e.key,
    ]..sort((x, y) {
        final byDate = when(entries[y]!).compareTo(when(entries[x]!));
        return byDate != 0 ? byDate : title(x).compareTo(title(y));
      });
    return ids;
  }

  /// The show to print for a mark: the one that decided it when Hanj knows
  /// it (D10), else your highest-rated among those behind it, with no claim
  /// that it decided anything (lead §2.3). Null when there's none.
  String? showFor(Achievement a, String? param, RecordMark mark) {
    final named = mark.show;
    if (named != null && entries.containsKey(named)) return named;
    final spread = _spread['${a.id}|$param'];
    if (spread != null) return spread;
    String? best;
    var bestSeal = -1.0;
    for (final id in behind(a, param)) {
      final s = _seal(entries[id]!) ?? 0;
      if (s > bestSeal) {
        best = id;
        bestSeal = s;
      }
    }
    return best;
  }

  /// The shows [spread] chose, by achievement id and parameter.
  final Map<String, String> _spread = {};

  /// Stage 3's recommendation, taken in stage 4 (Shahid, 2026-11-10: "go
  /// with your recommendations for everything"): on an imported record the
  /// same highest-rated show stood behind Finished, Episodes, Sealed,
  /// Genres, Decades and Every form, so most mats were one colour. Walking
  /// the spaces in the page's order, a space whose mark names no show takes
  /// the highest-rated show behind it that no earlier space already shows,
  /// and only when every one is taken the highest-rated again. A mark that
  /// names its show keeps it. True to the rule either way: the print is
  /// "a show behind it", never "the one that decided it" (lead §2.3).
  void spread(Map<String, _Held> held) {
    _spread.clear();
    if (entries.isEmpty) return;
    final used = <String>{};
    for (final group in AchievementGroup.values) {
      for (final a in Achievements.inGroup(group)) {
        final h = held[a.id];
        if (h == null || !h.earned || a.id == 'founder') continue;
        final named = h.topMark.show;
        if (named != null && entries.containsKey(named)) {
          used.add(named);
          continue;
        }
        String? best, fresh;
        var bestSeal = -1.0, freshSeal = -1.0;
        for (final id in behind(a, h.top.param)) {
          final s = _seal(entries[id]!) ?? 0;
          if (s > bestSeal) {
            best = id;
            bestSeal = s;
          }
          if (!used.contains(id) && s > freshSeal) {
            fresh = id;
            freshSeal = s;
          }
        }
        final pick = fresh ?? best;
        if (pick == null) continue;
        _spread['${a.id}|${h.top.param}'] = pick;
        used.add(pick);
      }
    }
  }

  /// The deciding show, then the rest behind it.
  List<String> reel(Achievement a, String? param, RecordMark mark) {
    final named = mark.show;
    final rest = behind(a, param);
    if (named == null || !entries.containsKey(named)) return rest;
    return [named, for (final id in rest) if (id != named) id];
  }

  int get finishedCount => entries.values.where(_finished).length;

  void open(BuildContext context, String id) {
    final data = entries[id];
    if (data == null) return;
    final anime = Anime(
      id: data['animeId']?.toString() ?? id,
      title: data['title'] as String? ?? 'Unknown',
      imageUrl: data['imageUrl'] as String?,
      episodes: (data['episodes'] as num?)?.toInt(),
      genres: (data['genres'] as List<dynamic>?)?.whereType<String>().toList() ??
          const [],
      averageScore: (data['averageScore'] as num?)?.toDouble(),
    );
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)));
  }
}

// ── Words ─────────────────────────────────────────────────────────────────

/// A space's short date (§3.3): "6 Nov", "By 4 Nov", "With your list", or
/// "As a Hanj Card" for one carried from a card.
String _shortDate(RecordMark m) {
  if (m.card) return 'As a Hanj Card';
  final day = '${m.at.day}$_nb${_monthsShort[m.at.month - 1]}';
  return switch (m.how) {
    MarkHow.onDay => day,
    MarkHow.by => 'By$_nb$day',
    MarkHow.withList => 'With your list',
  };
}

/// A mark's title as its space and stamps name it: the level's title, or
/// for Founder "Founder #12".
String _titleOf(MarkRef ref, RecordMark mark) =>
    ref.achievement.id == 'founder' && mark.n != null ? 'Founder #${mark.n}' : ref.title;

/// [name] with "Top 9" held on one line, as the brief's 1.3x rule asks of
/// counts ("Top 9" never splits).
String _together(String name) => name.replaceAll('Top 9', 'Top${_nb}9');

/// What a space or the sheet says about the level: "level 4 of 6".
String? _levelOf(MarkRef ref) {
  final steps = ref.achievement.steps;
  if (steps.length < 2) return null;
  // Non-breaking, so large text never leaves "2" alone on a line.
  return 'level$_nb${steps.indexOf(ref.step) + 1}${_nb}of$_nb${steps.length}';
}

/// What you have toward [a]'s counts, from the last evaluation; null where
/// the phone can't count it.
int? _have(Achievement a, AchievementTotals? t) {
  if (t == null) return null;
  return switch (a.id) {
    'finished' => t.finished,
    'episodes' => t.episodes,
    'sealed' => t.sealed,
    'finished_sealed' => t.finishedSealed,
    'genres' => t.genres.length,
    'decades' => t.decades?.length,
    _ => null,
  };
}

/// "Mecha and Music"; "Mecha, Music and Sports".
String _andList(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

// ── The page ──────────────────────────────────────────────────────────────

class _AchievementsScreenState extends State<AchievementsScreen> {
  final _service = AchievementsService.instance;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _listSub;
  Map<String, Map<String, dynamic>>? _entries;
  bool _listFailed = false;

  // The user document's facts this page shows: your name on the slip and
  // the day-one card, your Top 9's order, Founder.
  String _name = '';
  List<String> _top9 = const [];
  bool _isFounder = false;

  /// The character picture you picked in Edit Profile, for the sheet's
  /// preview of your header (stage 5); null for your seal.
  String? _avatarUrl;

  // Nothing for 400 ms (lead §2.4): the list usually comes from Firestore's
  // cache faster than that, and a flash of "Reading…" would be noise.
  bool _patient = false;
  Timer? _patience;

  bool _refreshed = false;
  Timer? _refreshFallback;

  // What was New when you opened the page. It stays marked for this visit
  // after markSeen() has emptied the service's newKeys.
  Set<String> _shownNew = const {};
  bool _seenHandled = false;

  @override
  void initState() {
    super.initState();
    _patience = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _patient = true);
    });
    _service.state.addListener(_onState);
    unawaited(_service.load().catchError((Object _) {}).then((_) => _onState()));
    _listen();
    unawaited(_readUser());
  }

  @override
  void dispose() {
    _service.state.removeListener(_onState);
    _listSub?.cancel();
    _patience?.cancel();
    _refreshFallback?.cancel();
    super.dispose();
  }

  /// Reads the whole list (no order, no filter: the rules need all of it),
  /// and hands each snapshot to the service, post-frame. The refresh starts
  /// with the first snapshot, or after 3 s without one.
  void _listen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _listSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('animeList')
        .snapshots()
        .listen(_onList, onError: (Object _) {
      if (!mounted) return;
      setState(() => _listFailed = true);
      _refreshOnce();
    });
    _refreshFallback = Timer(const Duration(seconds: 3), _refreshOnce);
  }

  void _onList(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    setState(() {
      _entries = {for (final d in snap.docs) d.id: d.data()};
      _listFailed = false;
    });
    // A snapshot from the cache never hears the server confirm it (that's
    // metadata only), so the refresh doesn't wait for one: it reads the
    // list itself when nothing confirmed has been fed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _service.observeList(snap);
      _refreshOnce();
    });
  }

  /// refresh() on open (stage 1's API): the user document, the activity
  /// log, the tier lists, the cards once ever and AniList's facts. It never
  /// throws.
  void _refreshOnce() {
    if (_refreshed) return;
    _refreshed = true;
    _refreshFallback?.cancel();
    unawaited(_service.refresh().catchError((Object _) {}));
  }

  Future<void> _readUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _name = user.displayName ?? '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      if (!mounted) return;
      final top9 = data['top9'];
      final name = data['displayName'];
      final avatar = data['avatarImageUrl'];
      setState(() {
        if (name is String && name.trim().isNotEmpty) _name = name.trim();
        _top9 = top9 is List ? [for (final id in top9) '$id'] : const [];
        _isFounder = data['isFounder'] == true;
        _avatarUrl = avatar is String ? avatar : null;
      });
    } catch (_) {
      // Offline with nothing cached: the slip goes without a Top 9's order.
    }
  }

  /// Once something New is in the record, it's noted for this visit and the
  /// page counts as seen. markSeen() is a write, so it's made only when
  /// there was something new to see. It keeps listening until then, since
  /// the refresh can find marks a moment after the page opens (found on the
  /// web emulators: a record read first, then evaluated).
  void _onState() {
    if (_seenHandled || !mounted) return;
    final s = _service.state.value;
    if (!s.known || !s.record.started) return;
    final fresh = s.newKeys;
    if (fresh.isEmpty) return;
    _seenHandled = true;
    setState(() => _shownNew = fresh);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => unawaited(_service.markSeen().catchError((Object _) {})));
  }

  void _tryAgain() {
    _listSub?.cancel();
    _refreshed = false;
    setState(() => _listFailed = false);
    _listen();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Clear over the hero's field, sumi once the page scrolls under it.
        backgroundColor: WidgetStateColor.resolveWith((states) =>
            states.contains(WidgetState.scrolledUnder)
                ? AppTheme.hankoSumi
                : AppTheme.hankoSumi.withValues(alpha: 0)),
        surfaceTintColor: AppTheme.hankoSumi.withValues(alpha: 0),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_sharp),
          color: AppTheme.hankoWashi,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Achievements', style: AppTheme.hankoSerif(fontSize: 20)),
      ),
      body: ValueListenableBuilder<AchievementsState>(
        valueListenable: _service.state,
        builder: (context, s, _) => _body(context, s, still),
      ),
    );
  }

  Widget _body(BuildContext context, AchievementsState s, bool still) {
    final top = MediaQuery.paddingOf(context).top;
    final record = s.record;
    final ready = s.known && record.started;
    if (!ready) {
      if (!_patient) return const SizedBox.shrink();
      // Never names a cause it can't verify (ANILIST-OFFLINE's copy rule).
      final failed = _listFailed && !s.known;
      return ListView(
        padding: EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, top + 24, AppTheme.hankoGutter, 24),
        children: [
          Text(
            failed
                ? 'Your record couldn’t be read just now.'
                : 'Reading your record…',
            style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoBodySize, color: AppTheme.hankoStone),
          ),
          if (failed) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: _WashiButton(label: 'Try again', onTap: _tryAgain),
            ),
          ],
        ],
      );
    }

    final shows = _entries == null ? _Shows.empty : _Shows(_entries!, _top9);
    final held = _Held.of(record);
    shows.spread(held);
    final founder = _isFounder || held['founder']!.earned;
    final listedEarned = [
      for (final a in Achievements.catalogue)
        if (!a.unlisted && held[a.id]!.earned) a,
    ].length;
    final total = Achievements.listedTotal(isFounder: founder);
    final fresh = record.count == 0;

    final children = <Widget>[];
    if (fresh) {
      children.add(_NewAccountTop(top: top));
    } else if (record.dayOne) {
      children.add(Padding(
        padding: EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, top + 12, AppTheme.hankoGutter, 0),
        child: _DayOneCard(
          record: record,
          held: held,
          name: _name,
          shows: shows,
        ),
      ));
      children.add(_countLine(listedEarned, total, 28));
    } else {
      final latest = AchievementsScreen.latestKey(record)!;
      children.add(_Hero(
        top: top,
        keyName: latest,
        ref: Achievements.parse(latest)!,
        mark: record.marks[latest]!,
        shows: shows,
        count: _countText(listedEarned, total),
        onOpen: () => _openSheet(Achievements.parse(latest)!.achievement, s, shows),
      ));
    }

    if (!fresh) {
      final next = s.next.take(3).toList();
      if (next.isNotEmpty) {
        children.add(_head('Next', 'The three nearest', 36));
        for (final step in next) {
          children.add(_NextRow(
            step: step,
            held: held[step.ref.achievement.id]!,
            totals: s.totals,
            onTap: () => _openSheet(step.ref.achievement, s, shows),
          ));
        }
      }
    }

    final measure = _longestWord(context);
    for (final group in AchievementGroup.values) {
      if (group == AchievementGroup.founder && !founder) continue;
      final spaces = [
        for (final a in Achievements.inGroup(group))
          if (!a.unlisted || held[a.id]!.earned) a,
      ];
      final listed = spaces.where((a) => !a.unlisted).toList();
      final aside = group == AchievementGroup.founder
          ? 'Hanj’s first 50'
          : '${listed.where((a) => held[a.id]!.earned).length}${_nb}of$_nb${listed.length}';
      children.add(_head(group.heading, aside, 40));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
        child: LayoutBuilder(builder: (context, box) {
          final across = measure <= _space3 ? _space3 : _space2;
          final cols =
              math.max(across == _space3 ? 3 : 2, ((box.maxWidth + _gap) / (across + _gap)).floor());
          final width = math.min(across, (box.maxWidth - _gap * (cols - 1)) / cols);
          return Wrap(
            spacing: _gap,
            runSpacing: 24,
            children: [
              for (final a in spaces)
                SizedBox(
                  width: width,
                  child: _Space(
                    held: held[a.id]!,
                    shows: shows,
                    totals: s.totals,
                    factsComplete: s.factsComplete,
                    isNew: held[a.id]!.keys.any(_shownNew.contains),
                    width: width,
                    still: still,
                    onTap: () => _openSheet(a, s, shows),
                  ),
                ),
            ],
          );
        }),
      ));
    }

    children.add(_foot(held));
    return ListView(
      padding: EdgeInsets.only(bottom: 32 + MediaQuery.paddingOf(context).bottom),
      children: children,
    );
  }

  String _countText(int earned, int total) =>
      'You’ve earned $earned${_nb}of$_nb$total.';

  Widget _countLine(int earned, int total, double above) => Padding(
        padding: EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, above, AppTheme.hankoGutter, 0),
        child: Text(_countText(earned, total),
            style: AppTheme.hankoSerif(fontSize: 20, height: 1.3)),
      );

  /// A group's heading, Shippori 16, with its aside in Jost 12 stone.
  Widget _head(String title, String aside, double above) => Padding(
        padding: EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, above, AppTheme.hankoGutter, 14),
        child: Semantics(
          header: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(title,
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoSectionSize, height: 1.3)),
              ),
              const SizedBox(width: 12),
              Text(aside,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      color: AppTheme.hankoStone)),
            ],
          ),
        ),
      );

  /// The unlisted line and the page's one note on dates and privacy.
  Widget _foot(Map<String, _Held> held) {
    final unlisted = [
      for (final a in Achievements.catalogue)
        if (a.unlisted && held[a.id]!.earned) a,
    ].length;
    final lines = [
      if (unlisted == 0)
        'Two more are never listed. They’re written in when they happen.'
      else if (unlisted == 1)
        'One more is never listed. It’s written in when it happens.',
      'Worked out on this phone from your list. Signed-in Hanj users can see '
          'your record, as they can see your list. “With your list” marks what '
          'came with an import: Hanj knows when your list arrived, not when you '
          'watched. “By” means on or before that day.',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 40, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(line,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      color: AppTheme.hankoStone,
                      height: 1.45)),
            ),
        ],
      ),
    );
  }

  /// The widest single word any space can print, at the reader's text size
  /// (lead §2.5, P5's whole-word rule): while it fits a space three across,
  /// the book stays three across; past that it goes two across.
  double _longestWord(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize, weight: FontWeight.w500);
    final words = <String>{
      for (final a in Achievements.catalogue) ...[
        ...a.name.split(' '),
        for (final step in a.steps) ...step.title.split(' '),
      ],
    };
    var widest = 0.0;
    for (final word in words) {
      final painter = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  void _openSheet(Achievement a, AchievementsState s, _Shows shows) {
    final still = MediaQuery.disableAnimationsOf(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.hankoSumi2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.hankoSheetRadius)),
      ),
      sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
      builder: (sheetContext) => _Sheet(
        held: _Held.of(s.record)[a.id]!,
        shows: shows,
        totals: s.totals,
        factsComplete: s.factsComplete,
        name: _name,
        avatarUrl: _avatarUrl,
      ),
    );
  }
}

// ── The top ───────────────────────────────────────────────────────────────

/// Your latest achievement on its show's colour (Print Room's hero, as on
/// Home): the date it happened when Hanj saw it, one sentence in the
/// journal voice, the level, and the show's print with the badge pressed
/// across its lower-left corner, in the badge's ink, never coral. Then the
/// count, still on the field's fade.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.top,
    required this.keyName,
    required this.ref,
    required this.mark,
    required this.shows,
    required this.count,
    required this.onOpen,
  });

  final double top;
  final String keyName;
  final MarkRef ref;
  final RecordMark mark;
  final _Shows shows;
  final String count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final a = ref.achievement;
    final show = shows.showFor(a, ref.param, mark);
    final cover = shows.cover(show);
    final sentence = Achievements.line(keyName, mark, show: shows.note);
    final level = _levelOf(ref);
    final title = _titleOf(ref, mark);
    final meta = level == null ? title : '$title · $level';
    final day = mark.how == MarkHow.onDay && !mark.card
        ? DateFormat('EEEE, d MMMM').format(mark.at)
        : null;
    final badge = HankoBadge(
      id: a.id,
      tier: ref.carving,
      size: 56,
      keyline: true,
      number: a.id == 'founder' ? mark.n : null,
      semanticLabel: 'Badge: $title',
    );
    return HankoField(
      coverUrl: cover,
      solidTo: 0.62,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, top + 12, AppTheme.hankoGutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              button: true,
              label: 'Your latest achievement. ${day == null ? '' : '$day. '}'
                  '$sentence $meta.',
              child: InkWell(
                onTap: onOpen,
                splashFactory: NoSplash.splashFactory,
                highlightColor: AppTheme.hankoPressWash,
                hoverColor: AppTheme.hankoPressWash,
                child: ExcludeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (day != null) ...[
                                Text(day,
                                    style: AppTheme.hankoSans(
                                        fontSize: AppTheme.hankoMetaSize,
                                        weight: FontWeight.w500)),
                                const SizedBox(height: 10),
                              ],
                              Text(sentence,
                                  style: AppTheme.hankoSerif(
                                      fontSize: AppTheme.hankoLedeSize,
                                      height: 1.3)),
                              const SizedBox(height: 12),
                              Text(meta,
                                  style: AppTheme.hankoSans(
                                      fontSize: AppTheme.hankoMetaSize,
                                      weight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Padding(
                          padding: const EdgeInsets.only(left: 20, bottom: 18),
                          child: cover == null
                              ? badge
                              : HankoPrint(
                                  url: cover,
                                  width: 96,
                                  height: 136,
                                  sharp: true,
                                  lift: HankoPrintLift.large,
                                  seal: badge,
                                  sealCorner: Alignment.bottomLeft,
                                  sealOverhang: const Offset(18, 16),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(count, style: AppTheme.hankoSerif(fontSize: 20, height: 1.3)),
          ],
        ),
      ),
    );
  }
}

/// Day one (decision g): a still paper card. The achievements already in
/// your record when Hanj began keeping it, pressed in sumi on washi, and
/// one sentence on why most carry the import's day. No animation and no
/// overlay; once you earn one live, the page's usual top takes its place.
class _DayOneCard extends StatelessWidget {
  const _DayOneCard({
    required this.record,
    required this.held,
    required this.name,
    required this.shows,
  });

  final AchievementRecord record;
  final Map<String, _Held> held;
  final String name;
  final _Shows shows;

  @override
  Widget build(BuildContext context) {
    final count = record.count;
    final since = record.since!;
    final countWord = count < _countWords.length
        ? _countWords[count]
        : Achievements.number(count);
    final withList =
        record.marks.values.where((m) => m.how == MarkHow.withList).length;
    final sentence = StringBuffer(count == 1
        ? '$countWord achievement was already in your record when Hanj began '
            'keeping it, on ${Achievements.date(since)}.'
        : '$countWord achievements were already in your record when Hanj began '
            'keeping it, on ${Achievements.date(since)}.');
    if (withList > 0) {
      sentence.write(withList * 2 > record.marks.length
          ? ' Most came with your list, so they carry that day, not the day you watched.'
          : ' Some came with your list, so they carry that day, not the day you watched.');
    }
    final stamps = [
      for (final a in Achievements.catalogue)
        if (held[a.id]!.earned) held[a.id]!,
    ];
    final finished = shows.finishedCount;
    final foot = shows.entries.isEmpty
        ? ''
        : '${Achievements.number(shows.entries.length)} titles · '
            '${Achievements.number(finished)} finished';
    return Semantics(
      container: true,
      label: 'Your record so far. $sentence '
          '${stamps.map((h) => _titleOf(h.top, h.topMark)).join(', ')}.',
      child: ExcludeSemantics(
        child: HankoPaper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Your record so far',
                  style: AppTheme.hankoSerif(
                      fontSize: 26, color: HankoPaper.ink, height: 1.2)),
              const SizedBox(height: 10),
              Text(sentence.toString(),
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoBodySize,
                      color: HankoPaper.ink2,
                      height: 1.45)),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, box) {
                // Four across while every word fits a column, else three.
                const gap = 8.0;
                final scaler = MediaQuery.textScalerOf(context);
                final style = AppTheme.hankoSans(
                    fontSize: AppTheme.hankoMetaSize, color: HankoPaper.ink);
                var widest = 0.0;
                for (final h in stamps) {
                  for (final w in _titleOf(h.top, h.topMark).split(' ')) {
                    final p = TextPainter(
                      text: TextSpan(text: w, style: style),
                      textDirection: TextDirection.ltr,
                      textScaler: scaler,
                    )..layout();
                    widest = math.max(widest, p.width);
                    p.dispose();
                  }
                }
                final four = (box.maxWidth - 3 * gap) / 4;
                final cols = widest <= four ? 4 : 3;
                final width = (box.maxWidth - (cols - 1) * gap) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: 18,
                  children: [
                    for (final h in stamps)
                      SizedBox(
                        width: width,
                        child: Column(
                          children: [
                            HankoBadge(
                              id: h.achievement.id,
                              tier: h.top.carving,
                              size: 48,
                              onPaper: true,
                              number: h.achievement.id == 'founder'
                                  ? h.topMark.n
                                  : null,
                              semanticLabel: 'Badge: ${h.top.title}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _together(h.achievement.repeats
                                  ? h.achievement.name
                                  : _titleOf(h.top, h.topMark)),
                              textAlign: TextAlign.center,
                              style: style.copyWith(height: 1.3),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              }),
              const SizedBox(height: 20),
              ColoredBox(
                color: HankoPaper.ink2.withValues(alpha: 0.35),
                child: const SizedBox(height: 1),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: HankoPaper.ink2)),
                  ),
                  if (foot.isNotEmpty)
                    Text(foot,
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: HankoPaper.ink2,
                            tabular: true)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A new account (lead frame 11): no field, a dashed badge, one sentence,
/// how achievements are earned, and one washi button to the show you'd log
/// first.
class _NewAccountTop extends StatelessWidget {
  const _NewAccountTop({required this.top});

  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, top + 20, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HankoBadge(
            id: 'finished',
            size: 56,
            state: HankoBadgeState.notYet,
            semanticLabel: 'Badge, not yet earned: First finish',
          ),
          const SizedBox(height: 20),
          Text('Your record starts with the first show you finish.',
              style: AppTheme.hankoSerif(
                  fontSize: AppTheme.hankoLedeSize, height: 1.3)),
          const SizedBox(height: 12),
          Text(
              'Achievements are earned by what you log: the shows you finish, '
              'the seals you give and the shelves you keep. Each one is written '
              'into your record once, with its show.',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoBodySize,
                  color: AppTheme.hankoStone,
                  height: 1.45)),
          const SizedBox(height: 20),
          _WashiButton(
            label: 'Find a show you’ve watched',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
        ],
      ),
    );
  }
}

/// The page's one main action, washi on sumi (Hanko: the one main action's
/// fill), 48 dp tall.
class _WashiButton extends StatelessWidget {
  const _WashiButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      child: Material(
        color: AppTheme.hankoWashi,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: AppTheme.hankoSans(
                        fontSize: 15,
                        weight: FontWeight.w600,
                        color: AppTheme.hankoSumi)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the three nearest, as a plain line with no bar (decision a): the
/// badge you hold for it (dashed when none), the next level's title, and
/// what you have in words.
class _NextRow extends StatelessWidget {
  const _NextRow({
    required this.step,
    required this.held,
    required this.totals,
    required this.onTap,
  });

  final NextStep step;
  final _Held held;
  final AchievementTotals? totals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = step.ref.achievement;
    final title = step.ref.title;
    final line = _nextLine(step, totals);
    return Semantics(
      container: true,
      button: true,
      label: 'Next: $title. $line',
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.hankoGutter, vertical: 10),
            child: Row(
              children: [
                HankoBadge(
                  id: a.id,
                  tier: held.earned ? held.top.carving : 1,
                  size: 40,
                  state: held.earned
                      ? HankoBadgeState.earned
                      : HankoBadgeState.notYet,
                  semanticLabel: title,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppTheme.hankoSans(
                              fontSize: 15,
                              weight: FontWeight.w500,
                              height: 1.3)),
                      const SizedBox(height: 2),
                      Text(line,
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              color: AppTheme.hankoStone,
                              height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right_sharp,
                    size: 20, color: AppTheme.hankoStone),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "89 now, 11 to go."; for Genres, "14 of 16. Still to come: Mecha and
/// Music." while four or fewer are missing.
String _nextLine(NextStep step, AchievementTotals? totals) {
  if (step.ref.achievement.id == 'genres' && totals != null) {
    final missing = totals.missingGenres;
    if (step.need == 16 && missing.isNotEmpty && missing.length <= 4) {
      return '${step.have}${_nb}of${_nb}16. Still to come: ${_andList(missing)}.';
    }
  }
  return step.line;
}

// ── The stamp book ────────────────────────────────────────────────────────

/// One achievement's fixed space in the stamp book.
///
/// Earned: the show's print (the stored 230 px cover, crisp at this size)
/// on a mat of its own colour, with the badge pressed across the print's
/// lower-left corner with its sumi keyline; under it the name and one line
/// (the date in its form, or what a repeating one holds). Not yet: the
/// dashed badge on sumi, the name in stone and the honest count, or "Not
/// yet". Told apart by three things at once, never colour alone: lit print
/// and solid rules against a dashed outline, washi against stone, and the
/// words.
class _Space extends StatelessWidget {
  const _Space({
    required this.held,
    required this.shows,
    required this.totals,
    required this.factsComplete,
    required this.isNew,
    required this.width,
    required this.still,
    required this.onTap,
  });

  final _Held held;
  final _Shows shows;
  final AchievementTotals? totals;
  final bool factsComplete;
  final bool isNew;
  final double width;
  final bool still;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = held.achievement;
    final earned = held.earned;
    final String name;
    final String line;
    if (!earned) {
      name = _together(a.name);
      line = _notYetLine(a);
    } else if (a.id == 'founder') {
      name = _titleOf(held.top, held.topMark);
      line = 'One of the first${_nb}50';
    } else if (a.repeats) {
      name = a.name;
      line = [for (final m in held.marks) m.$2.param].join(', ');
    } else {
      name = _together(_titleOf(held.top, held.topMark));
      line = _shortDate(held.topMark);
    }

    final matH = width * 1.06;
    final Widget art;
    if (earned && a.id == 'founder') {
      // Founder is a plate on the page, not a print (decision f): no mat and
      // no room for one.
      art = HankoBadge(
        id: a.id,
        tier: held.top.carving,
        size: _spaceBadge,
        number: held.topMark.n,
        semanticLabel: name,
      );
    } else if (!earned) {
      art = SizedBox(
        height: matH,
        child: Center(
          child: HankoBadge(
            id: a.id,
            size: _spaceBadge,
            state: HankoBadgeState.notYet,
            semanticLabel: a.name,
          ),
        ),
      );
    } else {
      art = _earnedArt(matH);
    }

    final level = earned ? _levelOf(held.top) : null;
    final label = [
      if (isNew) 'New',
      earned
          ? '$name${level == null ? '' : ', ${a.name}, $level'}'
          : '${a.name}. Not yet',
      if (line != 'Not yet') line,
    ].where((s) => s.isNotEmpty).join('. ');

    return Semantics(
      container: true,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              art,
              const SizedBox(height: 8),
              Text(name,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      weight: FontWeight.w500,
                      color: earned ? AppTheme.hankoWashi : AppTheme.hankoStone,
                      height: 1.3)),
              const SizedBox(height: 2),
              Text(line,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      color: AppTheme.hankoStone,
                      height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }

  /// Not yet, in words: the honest count, "Counted once Hanj has the
  /// details" while AniList's facts are missing, or "Not yet".
  String _notYetLine(Achievement a) {
    if (_needsFacts.contains(a.id) && !factsComplete) {
      return 'Counted once Hanj has the details';
    }
    final have = _have(a, totals);
    final first = a.steps.first.threshold;
    if (a.id == 'genres' && have != null) {
      return '$have${_nb}of${_nb}8 genres';
    }
    if (a.id == 'decades' && have != null) {
      return '$have${_nb}of${_nb}3 decades';
    }
    final byGenre = totals?.byGenre ?? const <String, int>{};
    if (a.id == 'deep_genre' && byGenre.isNotEmpty) {
      final top = byGenre.entries
          .where((e) => Achievements.genres.contains(e.key))
          .fold<MapEntry<String, int>?>(
              null, (best, e) => best == null || e.value > best.value ? e : best);
      if (top != null) return '${top.value}${_nb}of${_nb}25 in ${top.key}';
    }
    if (have != null && have > 0 && first > 1) {
      return '${Achievements.number(have)}${_nb}of$_nb${Achievements.number(first)}';
    }
    return 'Not yet';
  }

  Widget _earnedArt(double matH) {
    final a = held.achievement;
    final mark = held.topMark;
    final badge = HankoBadge(
      id: a.id,
      tier: held.top.carving,
      size: _spaceBadge,
      keyline: true,
      number: a.id == 'founder' ? mark.n : null,
      semanticLabel: held.top.title,
    );
    // Founder is a plate, not a print (decision f): its space holds no show.
    final show = a.id == 'founder' ? null : shows.showFor(a, held.top.param, mark);
    final cover = shows.cover(show);
    if (cover == null) {
      return SizedBox(
        height: matH,
        child: Stack(
          children: [
            if (a.id != 'founder')
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.hankoSumi3,
                    borderRadius:
                        BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
                  ),
                ),
              ),
            Positioned.fill(
              child: Align(
                alignment: a.id == 'founder' ? Alignment.centerLeft : Alignment.center,
                child: badge,
              ),
            ),
            if (isNew) const Positioned(left: 6, top: 6, child: _NewTab()),
          ],
        ),
      );
    }
    final printW = width * 0.6;
    final printH = printW * 1.415;
    final inset = width * 0.07;
    final printLeft = width - inset - printW;
    final printBottom = inset + printH;
    return _Mat(
      coverUrl: cover,
      still: still,
      child: SizedBox(
        width: width,
        height: matH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: inset,
              top: inset,
              child: HankoPrint(url: cover, width: printW, height: printH),
            ),
            Positioned(
              left: math.max(6, printLeft - 30),
              top: math.min(matH - _spaceBadge - 4, printBottom - 34),
              child: badge,
            ),
            if (isNew)
              Positioned(left: printLeft, top: inset, child: const _NewTab()),
          ],
        ),
      ),
    );
  }
}

/// "New" on a print's corner: a washi tab, the same paper tab as Top 9's
/// plate numbers. It marks what you earned without a moment you saw (another
/// phone, an evaluation while you were elsewhere), for this visit only.
class _NewTab extends StatelessWidget {
  const _NewTab();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.hankoWashi,
        borderRadius: BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text('New',
            style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoDataSmallSize,
                weight: FontWeight.w500,
                color: AppTheme.hankoSumi)),
      ),
    );
  }
}

/// A mat of the show's own colour (Print Room's shelf language), read from
/// the cover by HankoCoverColour and set by the field rule. A grey cover
/// gets a sumi 3 mat; a cover that couldn't be read (offline) gets none, so
/// the print lies on the page. The colour fades in over 240 ms, or at once
/// with Remove animations on.
class _Mat extends StatefulWidget {
  const _Mat({required this.coverUrl, required this.still, required this.child});

  final String coverUrl;
  final bool still;
  final Widget child;

  @override
  State<_Mat> createState() => _MatState();
}

class _MatState extends State<_Mat> {
  Color? _colour;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_Mat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coverUrl != widget.coverUrl) _read();
  }

  void _read() {
    final url = widget.coverUrl;
    if (HankoCoverColour.knows(url)) {
      _colour = AppTheme.hankoField(HankoCoverColour.peek(url)) ?? AppTheme.hankoSumi3;
      return;
    }
    _colour = null;
    // HankoCoverColour never throws, so nothing here reaches Crashlytics.
    HankoCoverColour.ofUrl(url).then((colour) {
      if (!mounted || widget.coverUrl != url) return;
      setState(() {
        _colour = HankoCoverColour.knows(url)
            ? (AppTheme.hankoField(colour) ?? AppTheme.hankoSumi3)
            : null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: widget.still ? Duration.zero : const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        color: _colour ?? AppTheme.hankoSumi.withValues(alpha: 0),
        borderRadius:
            const BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
      ),
      child: widget.child,
    );
  }
}

// ── The sheet ─────────────────────────────────────────────────────────────

/// One achievement (lead §3, decisions b and g): the record slip on paper
/// when it's yours, the levels as a row of stamps with the next one in
/// words, and the shows behind it as prints, each opening its show. A
/// not-yet sheet has no paper: paper is earned.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.held,
    required this.shows,
    required this.totals,
    required this.factsComplete,
    required this.name,
    required this.avatarUrl,
  });

  final _Held held;
  final _Shows shows;
  final AchievementTotals? totals;
  final bool factsComplete;
  final String name;

  /// Your picked picture, for "On your profile"'s preview; null for your
  /// seal.
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final a = held.achievement;
    final height = MediaQuery.sizeOf(context).height;
    final reel = held.earned
        ? shows.reel(a, held.top.param, held.topMark)
        : shows.behind(a, null);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height * 0.9),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(AppTheme.hankoGutter, 10,
            AppTheme.hankoGutter, 28 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.hankoEdge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (held.earned) _slip(context) else _notYet(),
            // Stage 5: earned, and never Founder (decision f).
            if (ProfileScreen.badgeOnSeal &&
                held.earned &&
                AchievementsService.canShow(held.topKey))
              _OnYourProfile(
                  markKey: held.topKey, name: name, avatarUrl: avatarUrl),
            if (a.tiered) ..._levels(),
            if (a.repeats && held.marks.length > 1) ..._instances(),
            if (reel.isNotEmpty) ..._behind(context, reel),
          ],
        ),
      ),
    );
  }

  /// The record slip on washi (lead §3.1): the level's title and where it
  /// stands, the show's print with the badge pressed across its corner,
  /// half on the art and half on the paper, the record line in Hanj's
  /// voice, then the date in its form and your name.
  Widget _slip(BuildContext context) {
    final a = held.achievement;
    final ref = held.top;
    final mark = held.topMark;
    final title = _titleOf(ref, mark);
    final level = _levelOf(ref);
    final sub = a.id == 'founder'
        ? 'One of the first 50'
        : level == null
            ? a.what
            : '${a.name} · $level';
    final line = Achievements.line(held.topKey, mark, show: shows.note);
    final show = a.id == 'founder' ? null : shows.showFor(a, ref.param, mark);
    final cover = shows.cover(show);
    final badge = HankoBadge(
      id: a.id,
      tier: ref.carving,
      size: 64,
      onPaper: true,
      keyline: cover != null,
      number: a.id == 'founder' ? mark.n : null,
      semanticLabel: 'Badge: $title',
    );
    final date = Achievements.dateLine(mark);
    return Semantics(
      container: true,
      label: '$title. $sub. $line $date.',
      child: ExcludeSemantics(
        child: HankoPaper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: AppTheme.hankoSerif(
                                fontSize: 25, color: HankoPaper.ink, height: 1.15)),
                        const SizedBox(height: 6),
                        Text(sub,
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoMetaSize,
                                weight: FontWeight.w500,
                                color: HankoPaper.ink2,
                                height: 1.35)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (cover == null)
                    badge
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 30, bottom: 14),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.all(
                              Radius.circular(AppTheme.hankoRadius)),
                          boxShadow: HankoPaper.printShadow,
                        ),
                        child: HankoPrint(
                          url: cover,
                          width: 92,
                          height: 130,
                          sharp: true,
                          lift: HankoPrintLift.none,
                          seal: badge,
                          sealCorner: Alignment.bottomLeft,
                          sealOverhang: const Offset(30, 14),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(line,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoBodySize,
                      color: HankoPaper.ink,
                      height: 1.45)),
              const SizedBox(height: 14),
              ColoredBox(
                color: HankoPaper.ink2.withValues(alpha: 0.35),
                child: const SizedBox(height: 1),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(date,
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          color: HankoPaper.ink2)),
                  if (name.isNotEmpty)
                    Text(name,
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: HankoPaper.ink2)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Not yet: a dashed space on sumi, the name, how it's earned in one
  /// plain sentence, and the honest count.
  Widget _notYet() {
    final a = held.achievement;
    final have = _have(a, totals);
    final String count;
    if (_needsFacts.contains(a.id) && !factsComplete) {
      count = 'Counted once Hanj has the details.';
    } else if (have != null && have > 0) {
      final need = a.steps.first.threshold;
      count = '${Achievements.number(have)}${_nb}of$_nb${Achievements.number(need)} so far.';
    } else {
      count = '';
    }
    return Semantics(
      container: true,
      label: '${a.name}. Not yet. ${_howTo[a.id] ?? a.what} $count',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HankoBadge(
              id: a.id,
              size: 84,
              state: HankoBadgeState.notYet,
              semanticLabel: a.name,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.name,
                      style: AppTheme.hankoSerif(fontSize: 22, height: 1.2)),
                  const SizedBox(height: 4),
                  Text('Not yet',
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          weight: FontWeight.w500,
                          color: AppTheme.hankoStone)),
                  const SizedBox(height: 10),
                  Text(_howTo[a.id] ?? a.what,
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoBodySize, height: 1.45)),
                  if (count.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(count,
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: AppTheme.hankoStone,
                            height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subhead(String title, String aside) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 12),
        child: Semantics(
          header: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(title,
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoSectionSize, height: 1.3)),
              ),
              const SizedBox(width: 12),
              Text(aside,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      color: AppTheme.hankoStone)),
            ],
          ),
        ),
      );

  /// The levels as a row of stamps (decision d): each at its own carving,
  /// solid rules for the ones you hold, dashed for the rest, the number
  /// under each; then the next one in words. No bar.
  List<Widget> _levels() {
    final a = held.achievement;
    final keys = held.keys;
    final heldCount = a.steps.where((s) => keys.contains(a.keyFor(s))).length;
    AchievementStep? next;
    for (final s in a.steps) {
      if (!keys.contains(a.keyFor(s))) {
        next = s;
        break;
      }
    }
    final have = _have(a, totals);
    final String? nextLine;
    if (next == null) {
      nextLine = 'Every level is yours.';
    } else if (have != null) {
      nextLine = 'Next: ${next.title}. You’re at ${Achievements.number(have)}.';
    } else if (_needsFacts.contains(a.id) && !factsComplete) {
      nextLine = 'Next: ${next.title}. Counted once Hanj has the details.';
    } else {
      nextLine = 'Next: ${next.title}.';
    }
    return [
      _subhead('Levels', '$heldCount${_nb}of$_nb${a.steps.length}'),
      Semantics(
        container: true,
        label: [
          for (final s in a.steps)
            '${s.title}, ${keys.contains(a.keyFor(s)) ? 'yours' : 'not yet'}',
        ].join('. '),
        child: ExcludeSemantics(
          child: Wrap(
            spacing: 8,
            runSpacing: 12,
            children: [
              for (final s in a.steps)
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      HankoBadge(
                        id: a.id,
                        tier: s.carving,
                        size: 30,
                        state: keys.contains(a.keyFor(s))
                            ? HankoBadgeState.earned
                            : HankoBadgeState.notYet,
                        semanticLabel: s.title,
                      ),
                      const SizedBox(height: 6),
                      // "10,000" at large text shrinks to its column
                      // rather than run into the next one.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(Achievements.number(s.threshold),
                          maxLines: 1,
                          softWrap: false,
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoLabelSize,
                              weight: FontWeight.w500,
                              color: keys.contains(a.keyFor(s))
                                  ? AppTheme.hankoWashi
                                  : AppTheme.hankoStone,
                              tabular: true)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(nextLine,
          style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoBodySize,
              color: AppTheme.hankoStone,
              height: 1.45)),
    ];
  }

  /// A repeating achievement keeps one space; the sheet lists each one.
  List<Widget> _instances() => [
        _subhead('Each one', '${held.marks.length}'),
        for (final m in held.marks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              container: true,
              label: '${m.$2.title}. ${Achievements.dateLine(m.$3)}.',
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.$2.title,
                        style: AppTheme.hankoSans(
                            fontSize: 15, weight: FontWeight.w500, height: 1.3)),
                    Text(Achievements.dateLine(m.$3),
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: AppTheme.hankoStone,
                            height: 1.4)),
                  ],
                ),
              ),
            ),
          ),
      ];

  /// The shows behind it, as prints: the deciding one first, then newest
  /// first. Each opens its show.
  List<Widget> _behind(BuildContext context, List<String> reel) {
    final decided = held.earned && held.topMark.show != null && reel.first == held.topMark.show;
    final n = reel.length;
    // Room for two caption lines at the reader's text size.
    final caption = MediaQuery.textScalerOf(context)
            .scale(AppTheme.hankoDataSmallSize) *
        1.3 *
        2;
    return [
      _subhead(
          held.earned ? 'Behind it' : 'Behind it so far',
          n == 1
              ? '1 show'
              : '${Achievements.number(n)} shows${decided ? '' : ', newest first'}'),
      SizedBox(
        height: 91 + 8 + caption + 4,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: n,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final id = reel[i];
            final title = shows.title(id);
            final first = i == 0 && decided;
            return Semantics(
              container: true,
              button: true,
              label: first ? 'The one that decided it: $title' : title,
              child: InkWell(
                onTap: () => shows.open(context, id),
                splashFactory: NoSplash.splashFactory,
                highlightColor: AppTheme.hankoPressWash,
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HankoPrint(
                          url: shows.cover(id),
                          width: 64,
                          height: 91,
                          lift: HankoPrintLift.none,
                        ),
                        const SizedBox(height: 8),
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoDataSmallSize,
                                weight: first ? FontWeight.w500 : FontWeight.w400,
                                color: first
                                    ? AppTheme.hankoWashi
                                    : AppTheme.hankoStone,
                                height: 1.3)),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }
}

// ── Your badge on Profile: the sheet's choice (stage 5) ─────────────────

/// "On your profile" (stage 5; Shahid, 2026-11-10: "Corner only"; decision
/// b): under the record slip of an achievement you've earned, a preview of
/// your own header with this badge pressed on your monogram's corner, as
/// Profile will show it, then one washi button: "Show on your profile",
/// "Show instead of 100 finished" when another is shown (so replacing is
/// never a surprise), or "Take it off". One badge at a time, nothing until
/// you choose, and a line that says who can see it before you share it.
///
/// The choice shows at once (AchievementsService publishes before the
/// write lands, since offline the write waits for the server); a refused
/// write puts it back, with a quiet line that names no cause. Never
/// offered for Founder (decision f).
class _OnYourProfile extends StatefulWidget {
  const _OnYourProfile({
    required this.markKey,
    required this.name,
    required this.avatarUrl,
  });

  /// The mark this sheet offers: the achievement's highest level, or its
  /// newest for one that repeats.
  final String markKey;
  final String name;
  final String? avatarUrl;

  @override
  State<_OnYourProfile> createState() => _OnYourProfileState();
}

class _OnYourProfileState extends State<_OnYourProfile> {
  final _service = AchievementsService.instance;

  // The last change was refused; cleared by the next one.
  bool _refused = false;

  Future<void> _choose(String? shown) async {
    final key = widget.markKey;
    final showing = shown != key;
    setState(() => _refused = false);
    if (showing) AchievementsScreen.pressOnProfile = key;
    final ok = showing ? await _service.setBadge(key) : await _service.clearBadge();
    if (!ok) {
      if (AchievementsScreen.pressOnProfile == key) {
        AchievementsScreen.pressOnProfile = null;
      }
      if (mounted) setState(() => _refused = true);
    } else if (!showing && AchievementsScreen.pressOnProfile == key) {
      AchievementsScreen.pressOnProfile = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = Achievements.parse(widget.markKey);
    if (ref == null) return const SizedBox.shrink();
    return ValueListenableBuilder<AchievementsState>(
      valueListenable: _service.state,
      builder: (context, s, _) {
        final shown = s.badge;
        final mine = shown == widget.markKey;
        final other = shown == null || mine ? null : Achievements.parse(shown)?.title;
        final label = mine
            ? 'Take it off'
            : other != null
                ? 'Show instead of $other'
                : 'Show on your profile';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 28, bottom: 12),
              child: Semantics(
                header: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text('On your profile',
                          style: AppTheme.hankoSerif(
                              fontSize: AppTheme.hankoSectionSize, height: 1.3)),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 12),
                      Text('Shown',
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoLabelSize,
                              color: AppTheme.hankoStone)),
                    ],
                  ],
                ),
              ),
            ),
            _preview(ref),
            const SizedBox(height: 14),
            _WashiButton(label: label, onTap: () => _choose(shown)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.visibility_outlined,
                      size: 16, color: AppTheme.hankoStone),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'One badge at a time. Signed-in Hanj users can see it.',
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          color: AppTheme.hankoStone,
                          height: 1.4)),
                ),
              ],
            ),
            if (_refused) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text('Your profile couldn’t be changed just now.',
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize,
                        color: AppTheme.hankoWashi,
                        height: 1.4)),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Your header as Profile draws it, with this badge on your monogram's
  /// corner: your picture (or your seal, its initial held at 30, as on
  /// Profile) and your name, on sumi. Read as one line.
  Widget _preview(MarkRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final initial = (user?.displayName ?? user?.email ?? 'A')[0].toUpperCase();
    final name = widget.name.isNotEmpty ? widget.name : (user?.displayName ?? '');
    final seal = MediaQuery.withNoTextScaling(
        child: HankoSeal(label: initial, size: 64, fontSize: 30));
    final url = widget.avatarUrl;
    final picture = url == null || url.isEmpty
        ? seal
        : ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
            child: SizedBox.square(
              dimension: 64,
              child: Image.network(url,
                  fit: BoxFit.cover, errorBuilder: (_, _, _) => seal),
            ),
          );
    return Semantics(
      container: true,
      label: 'Preview: your profile picture with ${ref.title} on its corner',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
          decoration: BoxDecoration(
            color: AppTheme.hankoSumi,
            borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          ),
          child: Row(
            children: [
              HankoBadgeCorner(
                id: ref.achievement.id,
                tier: ref.carving,
                semanticLabel: ref.title,
                child: picture,
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Text(name,
                    style: AppTheme.hankoSerif(fontSize: 22, height: 1.2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Earning one live: the slip (stage 4) ─────────────────────────────────

/// The unlock slip (stage 4; Shahid, 2026-11-10: "Paper slip where you
/// earned it"; decision h): when something you just did earns an
/// achievement, a small paper slip comes up on the screen where you did it,
/// once the action's own feedback is over (your seal's press, +1's dip, the
/// status sheet closing), so the two never compete. The badge is pressed
/// into it with the house press in the badge's own ink, sumi on washi,
/// never coral (decision i); one line in the record's journal voice; and
/// "See", which opens that achievement's sheet right there.
///
/// It's a SnackBar with paper for content, so it takes its turn in the
/// app's one ScaffoldMessenger queue: it waits behind any snack bar already
/// up, "Rated 8.5. Undo" included, and never covers it (lead §5.2: never
/// cover the user's escape hatch). It stays 4 s, or until dismissed while
/// TalkBack is on; it swipes away. Several earned by one action share one
/// slip: the highest-carved badge and "and 2 more", and "See" opens the
/// page, where each is marked New. With Remove animations on it's simply
/// there with the badge pressed. One haptic tick per action: the press
/// ticks only when the action had no tick of its own.
///
/// Never for an import, day one or another phone: AchievementsService's
/// liveEarns carries only marks decided by what you just did here. No
/// push, no overlay over everything, no confetti.
///
/// How a screen uses it, with [Achievements.replaceCards] on: [expect]
/// just before reporting the action to AchievementsService (noteAction or
/// noteTop9). One listener for the whole app takes the earns, so a screen
/// under another (Home under Detail) never shows a second slip for the
/// same action; the slip belongs to the screen that last acted, and shows
/// only while that screen is the one on top. If you leave it before the
/// slip's turn, there's no slip: what you earned is marked New on the page.
class AchievementSlip {
  AchievementSlip._();

  static StreamSubscription<List<LiveEarn>>? _earns;
  static _Expecting? _expecting;

  /// The status sheet's closing, the feedback a status, shelf or Favourite
  /// chosen in it waits for.
  static const Duration sheetClosing = Duration(milliseconds: 250);

  /// Something you did on [context]'s screen may earn an achievement. The
  /// slip waits [feedback] after now, for the action's own motion. [ticked]
  /// says the action already gave its haptic tick (Detail's seal press).
  /// A new action takes over what's still waiting: Detail learning that
  /// the sheet's Completed pressed your seal, or a Favourite marked in the
  /// sheet just before a status closed it.
  static void expect(BuildContext context,
      {Duration feedback = Duration.zero, bool ticked = false}) {
    if (!Achievements.replaceCards) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final route = ModalRoute.of(context);
    if (messenger == null || route == null) return;
    final previous = _expecting?..stop();
    final next = _expecting =
        _Expecting(messenger, route, DateTime.now().add(feedback), ticked);
    for (final (earns, tick) in previous?._waiting ?? const <(List<LiveEarn>, bool)>[]) {
      next._queue(earns, tick);
    }
    _earns ??= AchievementsService.instance.liveEarns.listen(_earned);
  }

  static void _earned(List<LiveEarn> earns) {
    final e = _expecting;
    if (e == null || earns.isEmpty) return;
    e.add(earns);
  }
}

/// The screen that last acted, and the earns waiting for its slip.
class _Expecting {
  _Expecting(this.messenger, this.route, this.readyAt, this.ticked);

  final ScaffoldMessengerState messenger;
  final ModalRoute<dynamic> route;
  final DateTime readyAt;

  /// Whether this action's tick has been given: by the action itself, or
  /// claimed by its first slip.
  bool ticked;

  /// As long as AchievementsService counts an earn as live.
  final DateTime until = DateTime.now().add(const Duration(minutes: 2));

  /// One slip each, with whether it gives its action's tick.
  final List<(List<LiveEarn>, bool)> _waiting = [];
  Timer? _check;

  /// Earns from this action: the first slip claims the tick, if the
  /// action had none.
  void add(List<LiveEarn> earns) {
    _queue(earns, !ticked);
    ticked = true;
  }

  void _queue(List<LiveEarn> earns, bool tick) {
    if (DateTime.now().isAfter(until)) return;
    _waiting.add((earns, tick));
    _check ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _try());
    _try();
  }

  void stop() {
    _check?.cancel();
    _check = null;
  }

  /// Shows what's waiting once the feedback is over and the screen is the
  /// one on top. A sheet you acted in (the Favourite or a shelf in the
  /// status sheet) counts as closed onto the screen that opened it. A page
  /// that has gone takes its slip with it.
  void _try() {
    final now = DateTime.now();
    if (!messenger.mounted || now.isAfter(until)) {
      _waiting.clear();
      stop();
      return;
    }
    if (now.isBefore(readyAt)) return;
    final bool show;
    if (route.isCurrent) {
      show = true;
    } else if (!route.isActive) {
      if (route is! PopupRoute) {
        _waiting.clear();
        stop();
        return;
      }
      show = true;
    } else {
      show = false;
    }
    if (!show) return;
    final talkBack =
        MediaQuery.maybeAccessibleNavigationOf(messenger.context) ?? false;
    for (final (earns, tick) in _waiting) {
      messenger.showSnackBar(SnackBar(
        content: _UnlockSlip(earns: earns, tick: tick),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const RoundedRectangleBorder(),
        // The paper's own print shadow falls outside it.
        clipBehavior: Clip.none,
        duration: const Duration(seconds: 4),
        persist: talkBack,
      ));
    }
    _waiting.clear();
    stop();
  }
}

/// The slip itself: washi paper, the badge pressed into it, one line, and
/// "See". The motion is lead §5.2's, as approved in final-f15-motion: the
/// slip rises 72 dp over 200 ms, decelerating, with the badge's dashed
/// space on it; the badge is pressed into the space with HankoSealPress in
/// sumi (it lands at 290 ms, when the words appear) and settles at 440 ms.
/// Only the slip's leaf moves. Nothing loops.
class _UnlockSlip extends StatefulWidget {
  const _UnlockSlip({required this.earns, required this.tick});

  /// One action's earns, highest carving first.
  final List<LiveEarn> earns;

  /// Whether the press gives the action's tick.
  final bool tick;

  @override
  State<_UnlockSlip> createState() => _UnlockSlipState();
}

class _UnlockSlipState extends State<_UnlockSlip>
    with SingleTickerProviderStateMixin {
  static const double _riseBy = 72;

  // The slip's 440 ms on one controller, so a slowed clock (timeDilation)
  // slows every step alike: it rises until 200 ms, the press starts there
  // (HankoSealPress, 240 ms) and lands at 290, when the words appear.
  static const double _pressAt = 200 / 440;
  static const double _landAt = 290 / 440;

  late final AnimationController _slip = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
  )..addListener(_step);
  late final Animation<Offset> _from = _slip.drive(
      Tween(begin: const Offset(0, _riseBy), end: Offset.zero)
          .chain(CurveTween(curve: const Interval(0, _pressAt, curve: Curves.decelerate))));

  bool _started = false;
  bool _pressed = false;
  bool _words = false;
  int _presses = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Simply there, with the badge pressed; the tick rule unchanged, so
      // the press is still asked for once, after the first frame.
      _pressed = true;
      _words = true;
      _slip.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _presses = 1);
      });
      return;
    }
    _slip.forward();
  }

  void _step() {
    final t = _slip.value;
    if (!_pressed && t >= _pressAt) {
      setState(() {
        _pressed = true;
        _presses = 1;
      });
    }
    if (!_words && t >= _landAt) setState(() => _words = true);
  }

  @override
  void dispose() {
    _slip.dispose();
    super.dispose();
  }

  /// "See": one achievement's sheet over this screen, or for several the
  /// page, where each is marked New. Through the navigator, since hiding
  /// the slip takes this widget away.
  void _see() {
    final earns = widget.earns;
    final nav = Navigator.of(context);
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    if (earns.length == 1) {
      unawaited(AchievementsScreen.showSheet(nav.context, earns.first.key)
          .catchError((Object _) {}));
    } else {
      nav.push(MaterialPageRoute(builder: (_) => const AchievementsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final earns = widget.earns;
    final first = earns.first;
    final ref = first.ref;
    final more = earns.length - 1;
    var line = Achievements.line(first.key, first.mark);
    if (more > 0) {
      final stem = line.endsWith('.') ? line.substring(0, line.length - 1) : line;
      line = '$stem, and $more more.';
    }
    final title = ref == null ? '' : _titleOf(ref, first.mark);
    final badge = ref == null
        ? const SizedBox.square(dimension: 48)
        : HankoBadge(
            id: ref.achievement.id,
            tier: ref.carving,
            size: 48,
            onPaper: true,
            number: ref.achievement.id == 'founder' ? first.mark.n : null,
            semanticLabel: 'Badge: $title',
          );
    final space = ref == null
        ? const SizedBox.square(dimension: 48)
        : HankoBadge(
            id: ref.achievement.id,
            size: 48,
            state: HankoBadgeState.notYet,
            onPaper: true,
            semanticLabel: title,
          );
    // The line already says what it is; the title would only repeat it.
    final label = more > 0
        ? 'New achievements. $line See them.'
        : 'New achievement. $line See it.';

    return AnimatedBuilder(
      animation: _from,
      builder: (context, child) =>
          Transform.translate(offset: _from.value, child: child),
      child: Semantics(
        container: true,
        button: true,
        label: label,
        child: InkWell(
          onTap: _see,
          splashFactory: NoSplash.splashFactory,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ExcludeSemantics(
            child: HankoPaper(
              child: Row(
                children: [
                  HankoSealPress(
                    presses: _presses,
                    ink: HankoPaper.ink,
                    tick: widget.tick,
                    child: _pressed ? badge : space,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Visibility(
                      visible: _words,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Text(line,
                          style: AppTheme.hankoSerif(
                              fontSize: 17, color: HankoPaper.ink, height: 1.25)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Visibility(
                    visible: _words,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Text('See',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoBodySize,
                            weight: FontWeight.w600,
                            color: HankoPaper.ink)
                        .copyWith(decoration: TextDecoration.underline)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
