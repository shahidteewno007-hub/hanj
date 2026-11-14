import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/arcs_service.dart';
import '../../widgets/hanko_field.dart';
import '../../widgets/hanko_print.dart';
import '../social/arc_page_hanko.dart';
import '../social/arcs_hanko.dart';

// ─────────────────────────────────────────────────────────────
// Your arcs this week, on Home (arcs-home, 2026-11-14; questions H-1..H-10
// in arcs-home-report.md, notes folder).
//
// The arcs you've joined that are running today, one row each: the show's
// print on its own colour's mat beside a sumi 3 label (an ArcBoard made
// small), with the arc's name, this week's episodes, the stop strip, and
// where you are on your list. A tap opens the arc's page. With no running
// arcs it draws nothing at all, so Home is unchanged for everyone else.
//
// One Firestore listener (ArcsService.mine), opened in initState. Home's
// tab root is rebuilt on every tab switch, so the last answer is kept in a
// static display cache (per user) that seeds the next build and never
// replaces the read. No AniList calls.
// ─────────────────────────────────────────────────────────────

/// Home's "Your arcs this week" block, or nothing. [entries] is Home's read
/// of your list (for "You're on episode 6"); [open] is Home's push, which
/// re-reads the list on return; [more] sits at the head's end (Home's quiet
/// link to every arc).
class ArcsThisWeek extends StatefulWidget {
  const ArcsThisWeek({
    super.key,
    required this.entries,
    required this.open,
    this.more,
  });

  final List<Map<String, dynamic>> entries;
  final void Function(Route<void> route) open;
  final Widget? more;

  @override
  State<ArcsThisWeek> createState() => _ArcsThisWeekState();
}

class _ArcsThisWeekState extends State<ArcsThisWeek> {
  // A display cache, not a request cache (CLAUDE.md, state pattern 3).
  static String? _cachedUid;
  static List<Arc> _cached = const [];

  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  List<Arc> _arcs = const [];
  StreamSubscription<List<Arc>>? _sub;

  @override
  void initState() {
    super.initState();
    final uid = _uid;
    if (uid == null) return;
    if (_cachedUid == uid) _arcs = _cached;
    _sub = ArcsService.instance.mine(uid).listen(
      (arcs) {
        _cachedUid = uid;
        _cached = arcs;
        if (mounted) setState(() => _arcs = arcs);
      },
      // A failed read keeps what is on screen (or nothing); Home says
      // nothing about it, as it says nothing about arcs at all.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// How far you've watched [animeId], from Home's read of your list. Null
  /// when the show isn't on it.
  int? _progress(String animeId) {
    for (final e in widget.entries) {
      if (e['animeId']?.toString() == animeId) {
        return (e['currentEpisode'] as num?)?.toInt() ?? 0;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ArcsThisWeekList(
      arcs: _arcs,
      now: DateTime.now(),
      progress: _progress,
      more: widget.more,
      onOpen: (arc) => widget.open(MaterialPageRoute(
          builder: (_) => ArcPageScreen(arcId: arc.id, initial: arc))),
    );
  }
}

/// The block itself, given the arcs you've joined: a Mincho head and up to
/// [ArcsThisWeekList.most] rows, the week closing soonest first. Nothing
/// when none of [arcs] is running on [now]'s day.
class ArcsThisWeekList extends StatelessWidget {
  const ArcsThisWeekList({
    super.key,
    required this.arcs,
    required this.now,
    required this.onOpen,
    this.progress,
    this.more,
  });

  final List<Arc> arcs;
  final DateTime now;
  final void Function(Arc arc) onOpen;
  final int? Function(String animeId)? progress;
  final Widget? more;

  /// Rows Home has room for; "All arcs" holds the rest.
  static const int most = 3;

  /// The arcs to show: scheduled, running today, the stop that opened first
  /// (so closes first) on top, then by name.
  static List<Arc> runningOn(List<Arc> arcs, DateTime now) {
    final running = [
      for (final a in arcs)
        if (a.scheduled && a.phaseOn(now) == ArcPhase.running) a,
    ];
    running.sort((a, b) {
      final byOpen =
          a.stop(a.stopOn(now)).opens.compareTo(b.stop(b.stopOn(now)).opens);
      return byOpen != 0 ? byOpen : a.name.compareTo(b.name);
    });
    return running;
  }

  @override
  Widget build(BuildContext context) {
    final running = runningOn(arcs, now);
    if (running.isEmpty) return const SizedBox.shrink();
    final more = this.more;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 24, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Your arcs this week',
                      style: AppTheme.hankoSerif(height: 1.3)),
                ),
              ),
              if (more != null) ...[const SizedBox(width: 12), more],
            ],
          ),
          const SizedBox(height: 8),
          for (final (i, arc) in running.take(most).indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            ArcWeekRow(
              key: ValueKey('home-arc-${arc.id}'),
              arc: arc,
              now: now,
              progress: arc.show == null ? null : progress?.call(arc.show!.id),
              onTap: () => onOpen(arc),
            ),
          ],
        ],
      ),
    );
  }
}

/// One running arc on Home: the show's print (48 × 68) on its colour's mat,
/// beside a sumi 3 label with the arc's name (Mincho 15, two lines), this
/// week's episodes (washi), the stop strip, and "You're on episode 6"
/// (stone) when the show is on your list. One button for a screen reader.
class ArcWeekRow extends StatelessWidget {
  const ArcWeekRow({
    super.key,
    required this.arc,
    required this.now,
    required this.onTap,
    this.progress,
  });

  final Arc arc;
  final DateTime now;
  final VoidCallback onTap;

  /// Your episode of the arc's show, from your list; null when it's not on it.
  final int? progress;

  static const double printWidth = 48;
  static const double printHeight = 68;

  @override
  Widget build(BuildContext context) {
    final show = arc.show;
    final phase = arcPhaseLine(arc, now);
    final p = progress;
    final yours = p == null ? null : 'You’re on episode $p';
    final label = [
      arc.name,
      if (show != null && show.title != arc.name) show.title,
      phase,
      ?yours,
    ].join('. ');
    final corners = BorderRadius.circular(AppTheme.hankoRadius);

    final text = Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(arc.name,
              style: AppTheme.hankoSerif(
                  fontSize: AppTheme.hankoListTitleSize, height: 1.3),
              maxLines: 2,
              overflow: TextOverflow.fade),
          const SizedBox(height: 4),
          Text(phase,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  weight: FontWeight.w500,
                  tabular: true,
                  height: 1.3)),
          const SizedBox(height: 8),
          ArcStopStrip(
              stops: arc.stopCount, current: arc.stopOn(now), height: 12),
          if (yours != null) ...[
            const SizedBox(height: 6),
            Text(yours,
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoLabelSize,
                    color: AppTheme.hankoStone,
                    tabular: true,
                    height: 1.3)),
          ],
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
                      width: printWidth + 20,
                      child: HankoField(
                        coverUrl: show.cover,
                        solidTo: 1,
                        glow: Alignment.center,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
