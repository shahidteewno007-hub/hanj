import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/arcs_service.dart';
import '../../widgets/hanko_board.dart';
import '../../widgets/hanko_field.dart';
import '../../widgets/hanko_print.dart';
import 'arc_compose_hanko.dart';
import 'arc_page_hanko.dart';

// ─────────────────────────────────────────────────────────────
// Arcs in Hanko (arcs redesign, 2026-11-14): the index, and the pieces the
// arc page and thread share. Reached from ArcsScreen when its _printRoom
// switch is on; design in arcs-design.md (notes folder).
//
// An arc is one show and a group, so it's drawn as a print on its own
// colour's mat (the show) beside a label carrying its stops (the group's
// shape). On a field all text is washi; the label sits on sumi 3, where
// stone and ai keep 5.6:1 or better.
// ─────────────────────────────────────────────────────────────

final DateFormat _day = DateFormat('EEE d MMM');
final DateFormat _date = DateFormat('d MMM');

/// "Episodes 1–28 · 4 a week".
String arcRangeLine(Arc arc) {
  final range =
      arc.from == arc.to ? 'Episode ${arc.from}' : 'Episodes ${arc.from}–${arc.to}';
  return '$range · ${arc.pace} a week';
}

/// Where the arc stands today, in words.
String arcPhaseLine(Arc arc, DateTime now) {
  if (!arc.scheduled) {
    return arc.postCount == 1 ? '1 post' : '${arc.postCount} posts';
  }
  switch (arc.phaseOn(now)) {
    case ArcPhase.starting:
      return 'Starts ${_day.format(arc.startsOn!)}';
    case ArcPhase.finished:
      final last = arc.endsOn.subtract(const Duration(days: 1));
      return 'Finished ${_date.format(last)}';
    case ArcPhase.running:
      final stop = arc.stop(arc.stopOn(now));
      return stop.first == stop.last
          ? 'This week: episode ${stop.first}'
          : 'This week: episodes ${stop.episodes}';
  }
}

String arcWatching(int n) => '$n watching';

String arcStopDay(DateTime d) => _date.format(d);

/// A short time for a post or reply: "now", "5m", "3h", "2d", "14 Nov".
String arcWhen(DateTime? t, DateTime now) {
  if (t == null) return 'now';
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  return _date.format(t);
}

/// Shows a short message at the foot of the screen.
void arcSay(BuildContext context, String message) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    backgroundColor: AppTheme.hankoSumi3,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius)),
    content: Text(message, style: AppTheme.hankoSans(height: 1.35)),
  ));
}

/// Hanko's app bar for Arcs' pages: a Mincho title and an optional stone
/// line under it.
PreferredSizeWidget arcAppBar(String title, {String? line, List<Widget>? actions}) {
  return AppBar(
    backgroundColor: AppTheme.hankoSumi,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    actions: actions,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: AppTheme.hankoSerif(fontSize: 18, height: 1.3),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.fade),
        if (line != null)
          Text(line,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  color: AppTheme.hankoStone,
                  height: 1.3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}

/// One button for a screen reader: washi tile with sumi words when
/// [filled] (a screen's main action, 15.3:1), else washi words in an edge
/// outline. 2 px corners, a press wash and no ripple, 48 dp at least.
class ArcAction extends StatelessWidget {
  const ArcAction({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = true,
    this.busy = false,
    this.busyLabel,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;
  final bool busy;
  final String? busyLabel;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final ink = filled ? AppTheme.hankoSumi : AppTheme.hankoWashi;
    final corners = BorderRadius.circular(AppTheme.hankoRadius);
    final text = busy ? (busyLabel ?? label) : label;
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null && !busy,
      label: text,
      child: Material(
        color: filled ? AppTheme.hankoWashi : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: corners,
          side: filled
              ? BorderSide.none
              : const BorderSide(color: AppTheme.hankoEdge),
        ),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: corners,
          splashFactory: NoSplash.splashFactory,
          highlightColor: filled
              ? AppTheme.hankoSumi.withValues(alpha: 0.08)
              : AppTheme.hankoPressWash,
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                  minWidth: AppTheme.hankoTouch,
                  minHeight: AppTheme.hankoTouch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ink),
                      )
                    else if (icon != null)
                      Icon(icon, size: 18, color: ink),
                    if (busy || icon != null) const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        text,
                        textAlign: TextAlign.center,
                        style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoListTitleSize,
                          weight: FontWeight.w600,
                          color: ink,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An arc's weeks as ticks on a hairline: past weeks stone, this week's
/// washi and taller, weeks to come the edge colour. Decorative; the screen
/// says the same in words.
class ArcStopStrip extends StatelessWidget {
  const ArcStopStrip({
    super.key,
    required this.stops,
    required this.current,
    this.height = 16,
  });

  final int stops;

  /// This week's stop: -1 before the start, [stops] once finished.
  final int current;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
              painter: _StopsPainter(stops: stops, current: current)),
        ),
      );
}

class _StopsPainter extends CustomPainter {
  const _StopsPainter({required this.stops, required this.current});

  final int stops;
  final int current;

  @override
  void paint(Canvas canvas, Size size) {
    if (stops <= 0) return;
    final mid = size.height / 2;
    canvas.drawRect(Rect.fromLTWH(0, mid - 0.5, size.width, 1),
        Paint()..color = AppTheme.hankoHairline);
    // Ticks spread over the width, at most 14 dp apart.
    final step = stops == 1
        ? 0.0
        : (size.width - 4).clamp(0.0, 14.0 * (stops - 1)) / (stops - 1);
    final w = stops > 40 ? 1.5 : 2.0;
    for (var i = 0; i < stops; i++) {
      final now = i == current;
      final h = now ? size.height : size.height * 0.55;
      final colour = now
          ? AppTheme.hankoWashi
          : i < current
              ? AppTheme.hankoStone
              : AppTheme.hankoEdge;
      final x = 2 + i * step;
      canvas.drawRect(
          Rect.fromLTWH(x - (now ? 1.5 : w / 2), mid - h / 2, now ? 3 : w, h),
          Paint()..color = colour);
    }
  }

  @override
  bool shouldRepaint(_StopsPainter old) =>
      old.stops != stops || old.current != current;
}

/// An arc on the index: the show's print on its own colour's mat, beside a
/// label on sumi 3 with the name, the show, the range and pace, the stop
/// strip, where it stands this week, and how many are watching (ai, the
/// crowd's number). One button for a screen reader.
class ArcBoard extends StatelessWidget {
  const ArcBoard({
    super.key,
    required this.arc,
    required this.uid,
    required this.now,
    required this.onTap,
  });

  final Arc arc;
  final String? uid;
  final DateTime now;
  final VoidCallback onTap;

  static const double printWidth = 72;
  static const double printHeight = 102;

  @override
  Widget build(BuildContext context) {
    final show = arc.show;
    final joined = arc.hasMember(uid);
    final phase = arcPhaseLine(arc, now);
    final label = [
      arc.name,
      if (show != null && show.title != arc.name) show.title,
      if (arc.scheduled) arcRangeLine(arc),
      phase,
      arcWatching(arc.memberCount),
      if (joined) 'Joined',
    ].join('. ');
    final corners = BorderRadius.circular(AppTheme.hankoRadius);

    final text = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(arc.name,
              style: AppTheme.hankoSerif(
                  fontSize: AppTheme.hankoListTitleSize, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.fade),
          if (show != null && show.title != arc.name) ...[
            const SizedBox(height: 2),
            Text(show.title,
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoMetaSize,
                    color: AppTheme.hankoStone,
                    height: 1.3),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
          if (arc.scheduled) ...[
            const SizedBox(height: 6),
            Text(arcRangeLine(arc),
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoLabelSize,
                    weight: FontWeight.w500,
                    color: AppTheme.hankoStone,
                    tabular: true,
                    height: 1.3)),
            const SizedBox(height: 10),
            ArcStopStrip(stops: arc.stopCount, current: arc.stopOn(now)),
          ],
          const SizedBox(height: 8),
          Text(phase,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  weight: FontWeight.w500,
                  height: 1.3)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(arcWatching(arc.memberCount),
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      weight: FontWeight.w500,
                      color: AppTheme.hankoAi,
                      height: 1.3)),
              if (joined)
                Text('Joined',
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoLabelSize,
                        weight: FontWeight.w600,
                        height: 1.3)),
            ],
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      label: label,
      child: Material(
        color: AppTheme.hankoSumi3,
        borderRadius: corners,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          child: ExcludeSemantics(
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (show != null)
                    SizedBox(
                      width: printWidth + 24,
                      child: HankoField(
                        coverUrl: show.cover,
                        solidTo: 1,
                        glow: Alignment.center,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: HankoPrint(
                              url: show.cover,
                              width: printWidth,
                              height: printHeight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Expanded(child: text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// The index
// ─────────────────────────────────────────────────────────────

/// Arcs' index: Running (every arc, most watchers first) and Yours (arcs
/// you've joined). With [show], only that show's arcs, and Start an arc
/// starts one for it (Detail's way in).
class ArcsIndexScreen extends StatefulWidget {
  const ArcsIndexScreen({super.key, this.show});

  final ArcShow? show;

  @override
  State<ArcsIndexScreen> createState() => _ArcsIndexScreenState();
}

class _ArcsIndexScreenState extends State<ArcsIndexScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  int _tab = 0;

  // Built once per tab choice, never in build() (AUDIT S4-2).
  late Stream<List<Arc>> _arcs = _streamFor(_tab);

  Stream<List<Arc>> _streamFor(int tab) {
    final show = widget.show;
    if (show != null) return ArcsService.instance.forShow(show.id);
    if (tab == 1) {
      final uid = _uid;
      return uid == null
          ? Stream.value(const <Arc>[])
          : ArcsService.instance.mine(uid);
    }
    return ArcsService.instance.running();
  }

  void _select(int tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _arcs = _streamFor(tab);
    });
  }

  void _open(Arc arc) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ArcPageScreen(arcId: arc.id, initial: arc)));

  Future<void> _start() async {
    final id = await showArcStartSheet(context, show: widget.show);
    if (!mounted || id == null) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => ArcPageScreen(arcId: id)));
  }

  @override
  Widget build(BuildContext context) {
    final show = widget.show;
    return Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      appBar: arcAppBar('Arcs',
          line: show == null ? 'Watch a show together' : show.title),
      body: StreamBuilder<List<Arc>>(
        stream: _arcs,
        builder: (context, snap) {
          final now = DateTime.now();
          final arcs = snap.data ?? const <Arc>[];
          final waiting =
              snap.connectionState == ConnectionState.waiting && !snap.hasData;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.hankoGutter, 8, AppTheme.hankoGutter, 40),
            children: [
              if (show == null) ...[
                HankoTabStrip(
                  labels: const ['Running', 'Yours'],
                  selected: _tab,
                  onSelect: _select,
                ),
                const SizedBox(height: 16),
              ],
              if (waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.hankoStone),
                    ),
                  ),
                )
              else if (snap.hasError)
                _ArcsNote(
                  title: 'Arcs can\'t be read right now',
                  line: 'Check your connection and come back in a moment.',
                )
              else if (arcs.isEmpty)
                _ArcsNote(
                  hand: true,
                  title: show != null
                      ? 'No one is watching this together yet'
                      : _tab == 1
                          ? 'You haven\'t joined an arc'
                          : 'No arcs yet',
                  line: show != null
                      ? 'Start an arc and pick a pace. Others can join you.'
                      : _tab == 1
                          ? 'Join one from Running, or start your own.'
                          : 'Start the first one: pick a show from your list '
                              'and a pace.',
                )
              else
                for (final arc in arcs) ...[
                  ArcBoard(
                    arc: arc,
                    uid: _uid,
                    now: now,
                    onTap: () => _open(arc),
                  ),
                  const SizedBox(height: 12),
                ],
              if (!waiting) ...[
                const SizedBox(height: 12),
                ArcAction(
                  label: 'Start an arc',
                  icon: Icons.add_sharp,
                  expand: true,
                  onTap: _uid == null ? null : _start,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A quiet note in place of a list: an empty hand (optional), a Mincho line
/// and a stone one.
class _ArcsNote extends StatelessWidget {
  const _ArcsNote({required this.title, required this.line, this.hand = false});

  final String title;
  final String line;
  final bool hand;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(
        children: [
          if (hand) ...[
            const HankoEmptyHand(),
            const SizedBox(height: 20),
          ],
          Text(title,
              textAlign: TextAlign.center,
              style: AppTheme.hankoSerif(
                  fontSize: AppTheme.hankoFeaturedSize, height: 1.3)),
          const SizedBox(height: 8),
          Text(line,
              textAlign: TextAlign.center,
              style: AppTheme.hankoSans(color: AppTheme.hankoStone, height: 1.5)),
        ],
      ),
    );
  }
}
