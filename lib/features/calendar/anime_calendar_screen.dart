import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../services/anilist_service.dart';
import '../../services/firestore_service.dart';
import '../../models/anime_model.dart';
import '../anime_detail/anime_detail_screen.dart';

class AnimeCalendarScreen extends StatefulWidget {
  const AnimeCalendarScreen({super.key});

  @override
  State<AnimeCalendarScreen> createState() => _AnimeCalendarScreenState();
}

class _AnimeCalendarScreenState extends State<AnimeCalendarScreen> {
  final _firestoreService = FirestoreService();
  bool _isLoading = true;
  // Set when the last _loadSchedule failed, so an empty schedule can tell
  // "nothing airs" apart from "nothing loaded".
  bool _loadFailed = false;
  Map<String, List<Map<String, dynamic>>> _scheduleByDay = {};
  // Airing time of the last entry on a full page: the query fetches the next
  // 50 airings across all of AniList, a few days' worth, so the schedule says
  // nothing about later. Null when the page wasn't full (AniList had nothing
  // further scheduled) or nothing was fetched.
  DateTime? _scheduleEnds;
  final Set<String> _remindersOn = {}; // animeId strings

  static const _days = [
    'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
    'FRIDAY', 'SATURDAY', 'SUNDAY'
  ];

  static const _dayLabels = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];

  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday'
  ];

  // Hanko's press: an 8% washi wash, no ripple, square corners (Profile's).
  static const ButtonStyle _pressStyle = ButtonStyle(
    overlayColor: WidgetStatePropertyAll(AppTheme.hankoPressWash),
    splashFactory: NoSplash.splashFactory,
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
    )),
  );

  int _selectedDay = DateTime.now().weekday - 1; // 0=Mon

  @override
  void initState() {
    super.initState();
    _loadSchedule();
    _loadReminders();
  }

  Future<void> _loadReminders() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('alerts')
        .get();
    if (mounted) {
      setState(() => _remindersOn.addAll(snap.docs.map((d) => d.id)));
    }
  }

  Future<void> _toggleReminder(String animeId, String title, int episode, bool newVal) async {
    setState(() {
      if (newVal) {
        _remindersOn.add(animeId);
      } else {
        _remindersOn.remove(animeId);
      }
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('alerts').doc(animeId);
    if (newVal) {
      await ref.set({
        'animeId': animeId,
        'title': title,
        'episode': episode,
        'addedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }

  Future<void> _loadSchedule() async {
    setState(() { _isLoading = true; _loadFailed = false; });
    try {
      // Get user's watching list
      final snapshot =
          await _firestoreService.getAnimeByStatus('WATCHING').first;
      if (!mounted) return;
      final watchingIds = snapshot.docs
          .map((d) => (d.data() as Map)['animeId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (watchingIds.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // Fetch airing schedule from AniList
      const query = r'''
      query ($page: Int) {
        Page(page: $page, perPage: 50) {
          airingSchedules(notYetAired: true, sort: TIME) {
            airingAt
            episode
            media {
              id
              title { romaji english }
              coverImage { medium }
              averageScore
              genres
              episodes
            }
          }
        }
      }
      ''';

      await AnilistService.throttle();
      // 15 s, as in AnilistService._post. A stalled connection used to keep
      // the spinner up for good; now the TimeoutException lands in the
      // catch below like any other failed load.
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'query': query, 'variables': {'page': 1}}),
      ).timeout(const Duration(seconds: 15));
      AnilistService.noteLimits(response.headers);
      if (response.statusCode == 429) {
        AnilistService.backoff(
            int.tryParse(response.headers['retry-after'] ?? '') ?? 10);
      }

      if (response.statusCode != 200) throw Exception('Failed');

      final data = jsonDecode(response.body);
      final schedules =
          data['data']['Page']['airingSchedules'] as List;

      // Filter to only user's watching list + group by day
      final Map<String, List<Map<String, dynamic>>> byDay = {};
      for (final day in _days) {
        byDay[day] = [];
      }

      for (final schedule in schedules) {
        final mediaId = schedule['media']['id'].toString();
        if (!watchingIds.contains(mediaId)) continue;

        final airingAt =
            DateTime.fromMillisecondsSinceEpoch(schedule['airingAt'] * 1000);
        final dayIndex = airingAt.weekday - 1; // 0=Mon
        final dayKey = _days[dayIndex];

        byDay[dayKey]!.add({
          'media': schedule['media'],
          'episode': schedule['episode'],
          'airingAt': airingAt,
        });
      }

      // If watching list has items but none are in the schedule,
      // show all currently airing anime as fallback
      final hasAny = byDay.values.any((list) => list.isNotEmpty);
      if (!hasAny) {
        // Fallback: show all from schedule grouped by day
        for (final schedule in schedules.take(50)) {
          final airingAt = DateTime.fromMillisecondsSinceEpoch(
              schedule['airingAt'] * 1000);
          final dayIndex = airingAt.weekday - 1;
          final dayKey = _days[dayIndex];
          byDay[dayKey]!.add({
            'media': schedule['media'],
            'episode': schedule['episode'],
            'airingAt': airingAt,
          });
        }
      }

      final ends = schedules.length >= 50
          ? DateTime.fromMillisecondsSinceEpoch(
              schedules.last['airingAt'] * 1000)
          : null;

      if (!mounted) return;
      setState(() {
        _scheduleByDay = byDay;
        _scheduleEnds = ends;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _loadFailed = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday - 1;

    return Scaffold(
      appBar: AppBar(
        // Detail's back arrow (Hanko H3), with the same pop as BackButton.
        leading: IconButton(
          tooltip: 'Back',
          style: _pressStyle,
          icon: const Icon(Icons.arrow_back_sharp, color: AppTheme.hankoWashi),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text('Anime Calendar'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            style: _pressStyle,
            icon: const Icon(Icons.refresh_sharp, color: AppTheme.hankoWashi),
            onPressed: _loadSchedule,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Day selector: hanko.html's chips on the page, then the screen's
          // one rule, the border's, as under Detail's tabs. In the page's
          // column on a wide window.
          _hankoColumn(
            context,
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.hankoGutter - 2, 2, AppTheme.hankoGutter - 2, 6),
                  child: Row(
                    children: List.generate(7, (i) {
                      return Expanded(
                        child: _DayChip(
                          label: _dayLabels[i],
                          name: _dayNames[i],
                          selected: _selectedDay == i,
                          today: today == i,
                          hasEpisodes:
                              _scheduleByDay[_days[i]]?.isNotEmpty == true,
                          onTap: () => setState(() => _selectedDay = i),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(
                  width: double.infinity,
                  height: 1,
                  child: ColoredBox(color: AppTheme.border),
                ),
              ],
            ),
          ),

          // Schedule list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: AppTheme.hankoWashi, strokeWidth: 1.5),
                    ),
                  )
                : _buildDaySchedule(),
          ),
        ],
      ),
    );
  }

  Widget _buildDaySchedule() {
    final dayKey = _days[_selectedDay];
    final items = _scheduleByDay[dayKey] ?? [];

    if (items.isEmpty) {
      // Nothing has loaded and the last fetch failed. Without this every
      // day read "No episodes today", which isn't something the app knows.
      final failed = _loadFailed && _scheduleByDay.isEmpty;
      // The copy names the selected day (it said "today" on every day), and
      // says "No episodes" only if the loaded schedule runs past the end of
      // that day's next occurrence. Beyond that the app hasn't looked.
      final now = DateTime.now();
      final isToday = _selectedDay == now.weekday - 1;
      final dayName = isToday ? 'today' : _dayNames[_selectedDay];
      final daysAhead = (_selectedDay - (now.weekday - 1)) % 7;
      final dayEnds = DateTime(now.year, now.month, now.day + daysAhead + 1);
      final unseen = _scheduleEnds != null && _scheduleEnds!.isBefore(dayEnds);
      // Hanko: Stage 0's words, as one Mincho sentence at the top of the
      // page with a quiet line in stone under it (Profile's empty state), no
      // emoji and no forced line breaks. A failed load also offers Retry,
      // which reloads as the refresh button does, through the throttle.
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          _hankoColumn(
            context,
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failed
                        ? 'The schedule can\'t load right now'
                        : unseen
                            ? 'Nothing to show for $dayName yet'
                            : isToday
                                ? 'No episodes today'
                                : 'No episodes on $dayName',
                    style: AppTheme.hankoSerif(fontSize: 17, height: 1.5),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    failed
                        ? 'Try again shortly.'
                        : unseen
                            ? 'The calendar only looks a few days ahead. '
                                'Check back closer to the day.'
                            : 'Check other days or add more anime to your '
                                'watching list',
                    style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      color: AppTheme.hankoStone,
                      height: 1.4,
                    ),
                  ),
                  if (failed) ...[
                    const SizedBox(height: 16),
                    _TextTile(label: 'Retry', onTap: _loadSchedule),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Hanko: rows drawn as Home's Coming up draws them (question 46), with
    // no card and space between: the cover, the title on up to two lines
    // fading at its end, "Episode 6 at 13:00" in Jost, and Detail's bell.
    // The day is the chip above, so the line names only the time. The Ep
    // badge was coral on a coral tint, 3.91:1; the line is stone, 6.9:1.
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final media = item['media'] as Map<String, dynamic>;
        final episode = item['episode'] as int;
        final airingAt = item['airingAt'] as DateTime;
        final title = media['title']['english'] ??
            media['title']['romaji'] ?? 'Unknown';
        final imageUrl = media['coverImage']['medium'] as String?;

        return _hankoColumn(
          context,
          Padding(
            padding: EdgeInsets.fromLTRB(AppTheme.hankoGutter,
                index == 0 ? 0 : 16, AppTheme.hankoGutter, 0),
            child: InkWell(
              onTap: () {
                final anime = Anime(
                  id: media['id'].toString(),
                  title: media['title']['romaji'] ?? 'Unknown',
                  titleEnglish: media['title']['english'],
                  imageUrl: imageUrl,
                  averageScore: (media['averageScore'] as num?)?.toDouble(),
                  genres: media['genres'] != null
                      ? List<String>.from(media['genres'])
                      : [],
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AnimeDetailScreen(anime: anime)),
                );
              },
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: _hankoCover(imageUrl),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FadeTitle(
                          title,
                          maxLines: 2,
                          style: AppTheme.hankoSerif(
                              fontSize: AppTheme.hankoListTitleSize,
                              height: 1.25),
                        ),
                        const SizedBox(height: 7),
                        // "at" and the time are joined by a no-break space,
                        // so large text never leaves the time alone.
                        Text(
                          'Episode $episode at ${_formatTime(airingAt)}',
                          style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoLabelSize,
                            weight: FontWeight.w500,
                            color: AppTheme.hankoStone,
                            height: 1.3,
                            tabular: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Room for a cut title's fade before the bell (3dbd8fd).
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _bell(media['id'].toString(), title, episode),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The reminder bell, drawn as Detail's and Home's (Hanko H3, Q46): a 36
  /// dp square in a 48 dp target, an edge outline when off, washi with a
  /// sumi bell when on, where the round coral bell glowed. It does what that
  /// bell did: the same toggle, the same write, the same message, in a
  /// Hanko snack bar. It is its own semantics node with the same tap, so a
  /// screen reader reaches it apart from the row it sits in; folded into the
  /// row, the bell and the row's way into the show were one node.
  Widget _bell(String mediaId, String title, int episode) {
    final isOn = _remindersOn.contains(mediaId);
    void toggle() {
      final newVal = !isOn;
      _toggleReminder(mediaId, title, episode, newVal);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newVal
            ? 'Reminder set for $title Ep $episode'
            : 'Reminder removed for $title Ep $episode'),
        backgroundColor: AppTheme.surfaceLight,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        ),
        duration: const Duration(seconds: 2),
      ));
    }

    return Semantics(
      container: true,
      button: true,
      toggled: isOn,
      label: 'Remind me when episode $episode of $title airs',
      onTap: toggle,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: toggle,
        child: SizedBox.square(
          dimension: AppTheme.hankoTouch,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isOn ? AppTheme.hankoWashi : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                border: isOn ? null : Border.all(color: AppTheme.hankoEdge),
              ),
              child: Icon(
                isOn
                    ? Icons.notifications_sharp
                    : Icons.notifications_none_outlined,
                color: isOn ? AppTheme.hankoSumi : AppTheme.hankoWashi,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The cover at 42 x 60, as Coming up's, with Hanko's 2 px corners on a
  /// sumi 3 ground, which is also what shows while it loads, when it fails,
  /// or when AniList sends none (the row used to lose its poster and shift).
  /// Left out of the semantics tree: the title beside it names the show.
  Widget _hankoCover(String? url) {
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: SizedBox(
          width: 42,
          height: 60,
          child: ColoredBox(
            color: AppTheme.hankoSumi3,
            child: url == null || url.isEmpty
                ? const SizedBox.expand()
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.expand(),
                  ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}

/// One day of the week strip (question 73), as hanko.html's chip: Jost 500
/// 13 on a 2 px square. The day you're looking at is washi with sumi text,
/// about 15:1, where the coral chip's white text measured 3.35:1. Today, when
/// it isn't the one chosen, is washi text in an edge outline, so it differs
/// by shape as well as tone; the other days are stone on the page, 6.9:1. A
/// 4 px square under the name marks a day with episodes, sumi on the chosen
/// day and washi elsewhere, and a screen reader hears "has episodes". The
/// slot is at least 48 dp tall to touch, and at very large text the name
/// scales down to fit its slot instead of breaking inside the word.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.name,
    required this.selected,
    required this.today,
    required this.hasEpisodes,
    required this.onTap,
  });

  final String label;
  final String name;
  final bool selected;
  final bool today;
  final bool hasEpisodes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected
        ? AppTheme.hankoSumi
        : today
            ? AppTheme.hankoWashi
            : AppTheme.hankoStone;
    // The label replaces the chip's own text, so the tap is given here too:
    // excludeSemantics would otherwise drop the GestureDetector's, and a
    // screen reader could find the day but not choose it.
    return Semantics(
      button: true,
      selected: selected,
      label: [name, if (today) 'today', if (hasEpisodes) 'has episodes']
          .join(', '),
      onTap: onTap,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              decoration: BoxDecoration(
                color: selected ? AppTheme.hankoWashi : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                // Always a 1 px border, clear unless it's today, so a chip
                // never shifts by a pixel when the choice moves.
                border: Border.all(
                  color: today && !selected
                      ? AppTheme.hankoEdge
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize,
                        weight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: ink,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox.square(
                    dimension: 4,
                    child: hasEpisodes
                        ? ColoredBox(
                            color: selected
                                ? AppTheme.hankoSumi
                                : AppTheme.hankoWashi)
                        : null,
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

/// On a wide window (1024 px and up) the page keeps the phone's column,
/// Responsive.proseMaxWidth plus the gutters, hung on the left as Profile's
/// and Home's are. Below 1024 it does nothing (WEB.md §9.2).
Widget _hankoColumn(BuildContext context, Widget child) {
  if (!Responsive.isDesktop(context)) return child;
  return Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
          maxWidth: Responsive.proseMaxWidth + 2 * AppTheme.hankoGutter),
      child: child,
    ),
  );
}

/// A Hanko secondary tile with a word on it ("Retry"), as Profile's and
/// Home's: sumi 3 with a 1 px edge outline, Jost 600 15 washi, 48 dp tall,
/// pressed with the 8% wash. Its own semantics node (container), so a
/// screen reader finds one button named "Retry"; without it the button
/// folded into the note around it, which then read as one long button.
class _TextTile extends StatelessWidget {
  const _TextTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: AppTheme.hankoSumi3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          side: const BorderSide(color: AppTheme.hankoEdge),
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  style: AppTheme.hankoSans(
                      fontSize: 15, weight: FontWeight.w600, height: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Shippori title on up to [maxLines] lines whose last line fades out at
/// its end when the title runs longer, instead of an ellipsis: Shippori
/// draws "…" as the centred Japanese ⋯ (AppTheme.hankoSerif). Flutter's own
/// TextOverflow.fade on a multi-line Text fades the bottom half of the last
/// line instead, so the title is split after its last full line and that
/// line is set on its own, one line with TextOverflow.fade.
///
/// The same as Home's and Profile's, which this file can't import: widgets
/// are private to their file, and a shared one needs its own approval. It
/// finds the last line's start with getPositionForOffset, because on
/// CanvasKit getLineBoundary at a line's first offset answers with the line
/// before (H4's emulator run).
class _FadeTitle extends StatelessWidget {
  const _FadeTitle(this.text, {required this.style, required this.maxLines});

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: constraints.maxWidth);
      final overflows = painter.didExceedMaxLines;
      final lines = overflows ? painter.computeLineMetrics() : null;
      final lastStart = lines == null || lines.length < maxLines
          ? 0
          : painter
              .getPositionForOffset(Offset(
                  0, lines[maxLines - 1].baseline - lines[maxLines - 1].ascent / 2))
              .offset;
      painter.dispose();
      if (!overflows || lastStart <= 0) {
        return Text(text,
            style: style,
            maxLines: maxLines,
            softWrap: maxLines > 1,
            overflow: TextOverflow.fade);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text.substring(0, lastStart).trimRight(),
              style: style, maxLines: maxLines - 1),
          Text(text.substring(lastStart).trimLeft(),
              style: style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade),
        ],
      );
    });
  }
}
