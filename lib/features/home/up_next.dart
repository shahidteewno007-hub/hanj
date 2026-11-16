import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// Up next, at the top of Home (up-next, 2026-11-14; questions U-1..U-12 in
// up-next-report.md, notes folder).
//
// Shahid, 2026-11-14: "why do I need to see what I last did? ... we need to
// replace it with something useful." So the top of Home stops reporting
// your newest rating and says what to watch next:
//
//   Episode 8 of Firefly Wedding is next        [print]
//   Out now · 7 of 12
//
// The show is the one you watched most recently that has an episode you can
// watch now (UpNext.pick). The second line says whether it's out, or how far
// you are. When you're caught up on everything you watch, the top says so,
// and when the next episode airs. Under it, a show you're watching that
// airs later today (UpNextTonight).
//
// Everything comes from what Home already holds: its read of your list and
// its airing batch (next episode and air time for each show you watch). No
// new request. Home lays these words beside the show's print on its colour
// field (Print Room), with no seal: nothing here is your verdict.
// ─────────────────────────────────────────────────────────────

/// The next episode the airing batch knows for a show: its number and when
/// it airs, on the device's clock.
typedef NextAiring = ({int episode, DateTime at});

/// The show the top of Home is about, and what to say about it.
class UpNext {
  const UpNext({
    required this.entry,
    required this.caughtUp,
    this.aired,
    this.nextAiring,
  });

  /// The list entry (Home's read of animeList).
  final Map<String, dynamic> entry;

  /// True when you've seen every episode that has aired, on this show and
  /// every other you watch: there's nothing to watch now.
  final bool caughtUp;

  /// Episodes aired so far, from the airing batch; null when the batch knows
  /// nothing (finished airing, not scheduled, not answered yet, failed, or a
  /// MyAnimeList import).
  final int? aired;

  /// The next episode to air, when the batch knows it.
  final NextAiring? nextAiring;

  /// Picks from [watching] (Continue's shows, most recently watched first)
  /// the first whose next episode you can watch now: one the airing batch
  /// doesn't show as caught up. Before the batch answers, every show counts
  /// as watchable, so it's Continue's first. Caught up on all of them, the
  /// one whose next episode airs soonest. Null with nothing on Continue.
  /// An episode the batch had as next that has aired by [now] (Home left
  /// open past its time) counts as aired.
  static UpNext? pick(
    List<Map<String, dynamic>> watching, {
    required int? Function(Map<String, dynamic> entry) airedFor,
    required NextAiring? Function(Map<String, dynamic> entry) nextAiringFor,
    required DateTime now,
  }) {
    if (watching.isEmpty) return null;
    UpNext? soonest;
    for (final entry in watching) {
      var aired = airedFor(entry);
      var next = nextAiringFor(entry);
      if (next != null && !next.at.isAfter(now)) {
        if (aired == null || next.episode > aired) aired = next.episode;
        next = null;
      }
      if (aired == null || aired > currentOf(entry)) {
        return UpNext(
            entry: entry, caughtUp: false, aired: aired, nextAiring: next);
      }
      if (next != null &&
          (soonest?.nextAiring == null ||
              next.at.isBefore(soonest!.nextAiring!.at))) {
        soonest = UpNext(
            entry: entry, caughtUp: true, aired: aired, nextAiring: next);
      }
    }
    return soonest ??
        UpNext(
          entry: watching.first,
          caughtUp: true,
          aired: currentOf(watching.first),
        );
  }

  static int currentOf(Map<String, dynamic> entry) =>
      (entry['currentEpisode'] as num?)?.toInt() ?? 0;

  String get id => entry['animeId']?.toString() ?? '';
  String get title {
    final t = (entry['title'] as String?)?.trim() ?? '';
    return t.isEmpty ? 'Unknown' : t;
  }

  int get current => currentOf(entry);
  int? get total {
    final t = (entry['episodes'] as num?)?.toInt();
    return t != null && t > 0 ? t : null;
  }

  int get next => current + 1;

  /// The title as it sits in a sentence: never broken after a hyphen (the
  /// phone broke "One-" / "Punch Man" in the old lede), which a word joiner
  /// forbids and draws nothing; and a short last word ("Season 3", "Part
  /// 2") kept with the word before it, since at 1.3x "3" was left alone on
  /// a line beside the print.
  String get _titleInSentence {
    var t = title.replaceAll('-', '-\u2060');
    final last = t.lastIndexOf(' ');
    if (last > 0 && t.length - last - 1 <= 3) {
      t = '${t.substring(0, last)}\u00A0${t.substring(last + 1)}';
    }
    return t;
  }

  /// The Mincho sentence. Its number keeps its word ("Episode 8") and "is
  /// next" stays together, by no-break spaces, so neither is left alone on
  /// a line.
  String sentence() {
    final t = _titleInSentence;
    if (caughtUp) {
      return current == 0
          ? '$t hasn’t started yet'
          : 'You’re caught up on $t';
    }
    final total = this.total;
    if (total == 1) return '$t is\u00A0next';
    if (total != null && next == total && total >= 2) {
      return 'The finale of $t is\u00A0next';
    }
    return 'Episode\u00A0$next of $t is\u00A0next';
  }

  /// The line under it, in Jost: whether the episode is out and how far you
  /// are, or when a caught-up show's next episode airs. Null when there is
  /// nothing true to say.
  String? meta(DateTime now) {
    if (caughtUp) {
      final next = nextAiring;
      if (next == null) return null;
      return 'Episode\u00A0${next.episode} airs ${airsWhen(next.at, now)}';
    }
    final total = this.total;
    final progress = current == 0
        ? null
        : total != null
            ? '$current of $total'
            : '$current watched';
    final waiting = aired == null ? 0 : aired! - current;
    final parts = <String>[
      if (waiting == 1) 'Out now',
      if (waiting > 1) '$waiting new episodes out',
      ?progress,
      if (waiting == 0 && total != null)
        total - current == 1 ? 'one to go' : '${total - current} to go',
    ];
    if (parts.isEmpty) return null;
    return parts.map((p) => p.replaceAll(' ', '\u00A0')).join('\u00A0· ');
  }

  /// What a screen reader says for the whole hero.
  String spoken(DateTime now) {
    final m = meta(now);
    final s = sentence();
    return _plain(m == null ? '$s.' : '$s. $m.');
  }
}

/// A show you're watching whose next episode airs later today (up-next):
/// the line under the hero. Not the hero's own show.
class UpNextTonight {
  const UpNextTonight({required this.entry, required this.airing});

  final Map<String, dynamic> entry;
  final NextAiring airing;

  /// The soonest of [watching], other than [except], whose next episode airs
  /// after [now] and before tomorrow on the device's calendar.
  static UpNextTonight? pick(
    List<Map<String, dynamic>> watching, {
    required Map<String, dynamic>? except,
    required NextAiring? Function(Map<String, dynamic> entry) nextAiringFor,
    required DateTime now,
  }) {
    UpNextTonight? soonest;
    for (final entry in watching) {
      if (identical(entry, except)) continue;
      final next = nextAiringFor(entry);
      if (next == null || !next.at.isAfter(now) || !_sameDay(next.at, now)) {
        continue;
      }
      if (soonest == null || next.at.isBefore(soonest.airing.at)) {
        soonest = UpNextTonight(entry: entry, airing: next);
      }
    }
    return soonest;
  }

  String get title {
    final t = (entry['title'] as String?)?.trim() ?? '';
    return t.isEmpty ? 'Unknown' : t;
  }

  /// "Tonight" from 17:00, "Later today" before.
  String lead() => airing.at.hour >= 17 ? 'Tonight' : 'Later today';

  /// "Frieren, episode 9 at 21:30": the episode and its time kept together.
  String rest() => '$title, '
      '${'episode ${airing.episode} at ${_hhmm(airing.at)}'.replaceAll(' ', '\u00A0')}';

  String spoken() => _plain('${lead()}: ${rest()}');
}

/// When an episode airs, in the lede's journal voice: "tonight at 21:30"
/// (today from 17:00), "today at 13:00", "tomorrow at 13:00", "on Friday at
/// 13:00" (2 to 6 days on), "on 3 December" (a week or more). By the
/// device's own calendar and clock, as Coming up's times are. The phrase
/// keeps its words together.
String airsWhen(DateTime t, DateTime now) {
  final days = DateTime.utc(t.year, t.month, t.day)
      .difference(DateTime.utc(now.year, now.month, now.day))
      .inDays;
  final String phrase;
  if (days <= 0) {
    phrase = '${t.hour >= 17 ? 'tonight' : 'today'} at ${_hhmm(t)}';
  } else if (days == 1) {
    phrase = 'tomorrow at ${_hhmm(t)}';
  } else if (days < 7) {
    phrase = 'on ${DateFormat('EEEE').format(t)} at ${_hhmm(t)}';
  } else {
    phrase = 'on ${DateFormat('d MMMM').format(t)}';
  }
  return phrase.replaceAll(' ', '\u00A0');
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _plain(String s) =>
    s.replaceAll('\u00A0', ' ').replaceAll('\u2060', '');

/// The hero's words (up-next): the sentence in Mincho at [sentenceStyle]
/// (Home's lede size beside the print), and the line under it in Jost,
/// washi, since all text on the hero's field is washi (Print Room).
/// Drawn only: Home wraps it with the print in one button whose label is
/// [UpNext.spoken].
class UpNextWords extends StatelessWidget {
  const UpNextWords({
    super.key,
    required this.upNext,
    required this.now,
    required this.sentenceStyle,
  });

  final UpNext upNext;
  final DateTime now;
  final TextStyle sentenceStyle;

  @override
  Widget build(BuildContext context) {
    final meta = upNext.meta(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(upNext.sentence(), style: sentenceStyle),
        if (meta != null) ...[
          const SizedBox(height: 10),
          Text(
            meta,
            style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoMetaSize,
              weight: FontWeight.w500,
              color: AppTheme.hankoWashi,
              height: 1.35,
              tabular: true,
            ),
          ),
        ],
      ],
    );
  }
}

/// "Tonight: Frieren, episode 9 at 21:30" under the hero (up-next), as one
/// button that opens that show: its tap and focus live in the node a screen
/// reader lands on, with the words excluded under it (CLAUDE.md's pattern).
class UpNextTonightLine extends StatelessWidget {
  const UpNextTonightLine({
    super.key,
    required this.tonight,
    required this.onTap,
  });

  final UpNextTonight tonight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.hankoSans(
      fontSize: AppTheme.hankoMetaSize,
      color: AppTheme.hankoWashi,
      height: 1.35,
      tabular: true,
    );
    return Semantics(
      container: true,
      button: true,
      label: tonight.spoken(),
      onTapHint: 'open ${tonight.title}',
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(style: style, children: [
                  TextSpan(
                    text: '${tonight.lead()}: ',
                    style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      weight: FontWeight.w600,
                      color: AppTheme.hankoWashi,
                      height: 1.35,
                      tabular: true,
                    ),
                  ),
                  TextSpan(text: tonight.rest()),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
