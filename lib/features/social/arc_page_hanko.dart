import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/arcs_service.dart';
import '../../widgets/hanko_board.dart';
import '../../widgets/hanko_field.dart';
import '../../widgets/hanko_paper.dart';
import '../../widgets/hanko_print.dart';
import 'arc_compose_hanko.dart';
import 'arcs_hanko.dart';

// ─────────────────────────────────────────────────────────────
// An arc's page and a post's thread, in Hanko (arcs redesign, 2026-11-14).
//
// The page: the show's print on its colour field with the arc's name and
// Join; under it, on sumi, the watchers (ai), the stops as printed chips
// (this week's chosen first), the way to write, and the posts about the
// chosen stop's episodes. A post tagged past your own episode is sealed:
// a slip of paper says which episode it's about and where you are, and
// opens on request.
//
// The thread: the post printed on paper, the replies under it, and Episode
// discussions' flat Hanko composer for members.
// ─────────────────────────────────────────────────────────────

class ArcPageScreen extends StatefulWidget {
  const ArcPageScreen({super.key, required this.arcId, this.initial});

  final String arcId;

  /// The arc as the index had it, so the page draws at once.
  final Arc? initial;

  @override
  State<ArcPageScreen> createState() => _ArcPageScreenState();
}

class _ArcPageScreenState extends State<ArcPageScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  late final Stream<Arc?> _arc = ArcsService.instance.arc(widget.arcId);
  late final Stream<List<ArcPost>> _posts =
      ArcsService.instance.posts(widget.arcId);

  /// How far you've watched this show (your list); null until read.
  int? _progress;
  String? _progressFor;

  /// The stop whose posts show; null for all of them. Chosen once, from
  /// this week, then by you.
  int? _stop;
  bool _stopChosen = false;

  final Set<String> _opened = <String>{};
  bool _joining = false;

  void _readProgress(Arc arc) {
    final uid = _uid;
    final show = arc.show;
    if (uid == null || show == null || _progressFor == show.id) return;
    _progressFor = show.id;
    ArcsService.instance.progress(uid, show.id).then((p) {
      if (mounted) setState(() => _progress = p);
    });
  }

  void _chooseStop(Arc arc, DateTime now) {
    if (_stopChosen || !arc.scheduled) return;
    _stopChosen = true;
    final i = arc.stopOn(now);
    _stop = (i >= 0 && i < arc.stopCount) ? i : null;
  }

  Future<void> _setMember(Arc arc, bool join) async {
    final uid = _uid;
    if (uid == null || _joining) return;
    setState(() => _joining = true);
    try {
      await ArcsService.instance.setMember(arc.id, uid, join: join);
    } on ArcsFailure catch (e) {
      if (mounted) arcSay(context, e.message);
    }
    if (mounted) setState(() => _joining = false);
  }

  Future<void> _write(Arc arc, DateTime now) async {
    final uid = _uid;
    if (uid == null) return;
    final stop = _stop != null ? arc.stop(_stop!) : null;
    final i = arc.stopOn(now);
    final fallback = (i >= 0 && i < arc.stopCount) ? arc.stop(i).last : arc.from;
    final posted = await showArcPostSheet(context,
        arc: arc, uid: uid, ep: stop?.last ?? fallback);
    if (posted == true && mounted) arcSay(context, 'Posted');
  }

  Future<void> _deleteArc(Arc arc) async {
    final ok = await arcConfirm(context,
        title: 'Delete this arc?',
        line: 'Nothing has been posted in it yet. This can\'t be undone.',
        action: 'Delete');
    if (ok != true || !mounted) return;
    try {
      await ArcsService.instance.deleteArc(arc.id);
      if (mounted) Navigator.pop(context);
    } on ArcsFailure catch (e) {
      if (mounted) arcSay(context, e.message);
    }
  }

  Future<void> _like(ArcPost post) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await ArcsService.instance.toggleLike(widget.arcId, post.id, uid);
    } on ArcsFailure catch (e) {
      if (mounted) arcSay(context, e.message);
    }
  }

  void _openThread(Arc arc, ArcPost post) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              ArcThreadScreen(arc: arc, postId: post.id, initial: post)));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Arc?>(
      stream: _arc,
      initialData: widget.initial,
      builder: (context, snap) {
        final arc = snap.data;
        if (arc == null) {
          final gone = snap.connectionState == ConnectionState.active ||
              snap.hasError;
          return Scaffold(
            backgroundColor: AppTheme.hankoSumi,
            appBar: arcAppBar('Arc'),
            body: Center(
              child: gone
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                          snap.hasError
                              ? 'This arc can\'t be read right now'
                              : 'This arc is gone',
                          textAlign: TextAlign.center,
                          style: AppTheme.hankoSerif(
                              fontSize: AppTheme.hankoFeaturedSize)),
                    )
                  : const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.hankoStone)),
            ),
          );
        }
        final now = DateTime.now();
        _readProgress(arc);
        _chooseStop(arc, now);
        return Scaffold(
          backgroundColor: AppTheme.hankoSumi,
          appBar: arcAppBar(arc.show?.title ?? 'Arc', line: 'Watch-along',
              actions: [
                // The maker can delete an arc while nothing's been posted
                // (the rules' condition, so nothing is ever stranded).
                if (_uid != null && arc.createdBy == _uid && arc.postCount == 0)
                  PopupMenuButton<int>(
                    tooltip: 'More',
                    color: AppTheme.hankoSumi3,
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.hankoRadius)),
                    icon: const Icon(Icons.more_horiz_sharp,
                        color: AppTheme.hankoStone),
                    onSelected: (_) => _deleteArc(arc),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 0,
                          child: Text('Delete this arc',
                              style: AppTheme.hankoSans())),
                    ],
                  ),
              ]),
          body: StreamBuilder<List<ArcPost>>(
            stream: _posts,
            builder: (context, ps) => _page(arc, now, ps),
          ),
        );
      },
    );
  }

  Widget _page(Arc arc, DateTime now, AsyncSnapshot<List<ArcPost>> ps) {
    final member = arc.hasMember(_uid);
    final all = ps.data ?? const <ArcPost>[];
    final stop = _stop != null && _stop! < arc.stopCount ? arc.stop(_stop!) : null;
    final shown = stop == null
        ? all
        : all.where((p) => p.ep != null && stop.holds(p.ep!)).toList();
    final current = arc.stopOn(now);
    final progress = _progress ?? 0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        ArcHero(
          arc: arc,
          now: now,
          member: member,
          busy: _joining,
          onJoin: _uid == null ? null : () => _setMember(arc, true),
          onLeave: _uid == null ? null : () => _setMember(arc, false),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.hankoGutter, 16, AppTheme.hankoGutter, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  Text(arcWatching(arc.memberCount),
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          weight: FontWeight.w500,
                          color: AppTheme.hankoAi)),
                  if (arc.creatorName.isNotEmpty)
                    Text('Started by ${arc.creatorName}',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: AppTheme.hankoStone)),
                ],
              ),
              if (arc.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(arc.description,
                    style: AppTheme.hankoSans(height: 1.5)),
              ],
              const SizedBox(height: 14),
              Text(arcPhaseLine(arc, now),
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoListTitleSize,
                      weight: FontWeight.w500)),
              if (arc.scheduled) ...[
                const SizedBox(height: 8),
                ArcStopStrip(stops: arc.stopCount, current: current, height: 18),
              ],
            ],
          ),
        ),
        if (arc.scheduled) ...[
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
            child: Row(
              children: [
                HankoChip(
                  label: 'All',
                  semanticLabel: 'All stops',
                  on: _stop == null,
                  onTap: () => setState(() => _stop = null),
                ),
                for (final s in arc.stops) ...[
                  const SizedBox(width: 8),
                  HankoChip(
                    label: s.index == current
                        ? 'This week · ${s.episodes}'
                        : 'Stop ${s.index + 1} · ${s.episodes}',
                    semanticLabel: 'Stop ${s.index + 1}, '
                        '${s.first == s.last ? 'episode ${s.first}' : 'episodes ${s.first} to ${s.last}'}'
                        '${s.index == current ? ', this week' : ', from ${arcStopDay(s.opens)}'}',
                    on: _stop == s.index,
                    onTap: () => setState(() => _stop = s.index),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
          child: member
              ? ArcAction(
                  label: stop == null
                      ? 'Write a post'
                      : 'Write about episode${stop.first == stop.last ? '' : 's'} ${stop.episodes}',
                  icon: Icons.edit_sharp,
                  filled: false,
                  expand: true,
                  onTap: () => _write(arc, now),
                )
              : Text(
                  _uid == null
                      ? 'Sign in to join and write'
                      : 'Join the arc to write and reply',
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      color: AppTheme.hankoStone)),
        ),
        const SizedBox(height: 8),
        if (ps.hasError)
          _quiet('Posts can\'t be read right now')
        else if (ps.connectionState == ConnectionState.waiting && !ps.hasData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.hankoStone),
              ),
            ),
          )
        else if (shown.isEmpty)
          _quiet(stop == null
              ? 'Nothing posted yet'
              : 'Nothing about episode${stop.first == stop.last ? '' : 's'} ${stop.episodes} yet')
        else
          for (final p in shown)
            ArcPostTile(
              post: p,
              uid: _uid,
              now: now,
              progress: progress,
              sealed: _progress != null &&
                  p.sealedFor(_uid, progress) &&
                  !_opened.contains(p.id),
              onOpenSealed: () => setState(() => _opened.add(p.id)),
              onTap: () => _openThread(arc, p),
              onLike: () => _like(p),
            ),
      ],
    );
  }

  Widget _quiet(String line) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, 28, AppTheme.hankoGutter, 0),
        child: Text(line,
            textAlign: TextAlign.center,
            style: AppTheme.hankoSans(color: AppTheme.hankoStone)),
      );
}

/// The top of an arc's page: the show's print (sharp) on its colour field,
/// the arc's name, range and pace, its first day, and Join, or Joined with
/// Leave. On a field all text is washi.
class ArcHero extends StatelessWidget {
  const ArcHero({
    super.key,
    required this.arc,
    required this.now,
    required this.member,
    required this.busy,
    required this.onJoin,
    required this.onLeave,
  });

  final Arc arc;
  final DateTime now;
  final bool member;
  final bool busy;
  final VoidCallback? onJoin;
  final VoidCallback? onLeave;

  static const double printWidth = 104;
  static const double printHeight = 148;

  @override
  Widget build(BuildContext context) {
    final show = arc.show;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(arc.name,
            style: AppTheme.hankoSerif(fontSize: 22, height: 1.25)),
        if (arc.scheduled) ...[
          const SizedBox(height: 8),
          Text(arcRangeLine(arc),
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  weight: FontWeight.w500,
                  tabular: true,
                  height: 1.35)),
          Text(
              arc.phaseOn(now) == ArcPhase.starting
                  ? 'From ${arcStopDay(arc.startsOn!)}'
                  : 'Since ${arcStopDay(arc.startsOn!)}',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize, height: 1.35)),
        ],
        const SizedBox(height: 14),
        if (member)
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_sharp,
                      size: 18, color: AppTheme.hankoWashi),
                  const SizedBox(width: 6),
                  Text('Joined',
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoListTitleSize,
                          weight: FontWeight.w600)),
                ],
              ),
              ArcAction(
                label: 'Leave',
                filled: false,
                busy: busy,
                busyLabel: 'Leaving…',
                onTap: onLeave,
              ),
            ],
          )
        else
          ArcAction(
            label: 'Join the arc',
            busy: busy,
            busyLabel: 'Joining…',
            onTap: onJoin,
          ),
      ],
    );

    return HankoField(
      coverUrl: show?.cover,
      glow: const Alignment(-0.6, -0.2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, 16, AppTheme.hankoGutter, 20),
        child: LayoutBuilder(builder: (context, box) {
          // Beside the print while the words keep 180 dp, else under it.
          final beside = show != null && box.maxWidth - printWidth - 16 >= 180;
          final print = show == null
              ? null
              : HankoPrint(
                  url: HankoPrint.sharpUrl(show.cover),
                  width: printWidth,
                  height: printHeight,
                  lift: HankoPrintLift.large,
                );
          if (print == null) return words;
          if (beside) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                print,
                const SizedBox(width: 16),
                Expanded(child: words),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [print, const SizedBox(height: 16), words],
          );
        }),
      ),
    );
  }
}

/// The episode a post is about, as a small outlined tag: "EP 6".
class ArcEpTag extends StatelessWidget {
  const ArcEpTag({super.key, required this.ep, this.onPaper = false});

  final int ep;
  final bool onPaper;

  @override
  Widget build(BuildContext context) {
    final ink = onPaper ? HankoPaper.ink2 : AppTheme.hankoStone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: ink),
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      ),
      child: Text('EP $ep',
          style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoDataSmallSize,
              weight: FontWeight.w500,
              color: ink,
              tabular: true,
              letterSpacing: 0.5,
              height: 1.2)),
    );
  }
}

/// A post on an arc's page: who and when, the episode tag, the title, four
/// lines of it, and its like and replies. Sealed, the words give way to a
/// paper slip naming the episode and where you are, with Open anyway.
class ArcPostTile extends StatelessWidget {
  const ArcPostTile({
    super.key,
    required this.post,
    required this.uid,
    required this.now,
    required this.progress,
    required this.sealed,
    required this.onOpenSealed,
    required this.onTap,
    required this.onLike,
  });

  final ArcPost post;
  final String? uid;
  final DateTime now;
  final int progress;
  final bool sealed;
  final VoidCallback onOpenSealed;
  final VoidCallback onTap;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final liked = uid != null && post.likes.contains(uid);
    final replies =
        post.replyCount == 1 ? '1 reply' : '${post.replyCount} replies';

    final head = Row(
      children: [
        Flexible(
          child: Text(post.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize, weight: FontWeight.w600)),
        ),
        Text('  ·  ${arcWhen(post.createdAt, now)}',
            style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoMetaSize, color: AppTheme.hankoStone)),
        const Spacer(),
        if (post.ep != null) ArcEpTag(ep: post.ep!),
      ],
    );

    final Widget words = sealed
        ? ArcSealSlip(ep: post.ep ?? 0, progress: progress, onOpen: onOpenSealed)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (post.title.isNotEmpty) ...[
                Text(post.title,
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoListTitleSize, height: 1.3)),
                const SizedBox(height: 4),
              ],
              Text(post.body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.hankoSans(height: 1.45)),
            ],
          );

    final open = Semantics(
      container: true,
      button: !sealed,
      label: sealed
          ? 'Post by ${post.authorName}, sealed: episode ${post.ep}'
          : [
              'Post by ${post.authorName}',
              if (post.ep != null) 'episode ${post.ep}',
              if (post.title.isNotEmpty) post.title,
              post.body,
              replies,
            ].join('. '),
      child: InkWell(
        onTap: sealed ? null : onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.hankoGutter, 14, AppTheme.hankoGutter, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: head),
              const SizedBox(height: 8),
              sealed ? words : ExcludeSemantics(child: words),
            ],
          ),
        ),
      ),
    );

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.hankoHairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          open,
          if (!sealed)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTheme.hankoGutter - 12, 0, AppTheme.hankoGutter, 6),
              child: Row(
                children: [
                  ArcLike(liked: liked, count: post.likeCount, onTap: onLike),
                  const SizedBox(width: 4),
                  ExcludeSemantics(
                    child: Text(replies,
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoLabelSize,
                            weight: FontWeight.w500,
                            color: AppTheme.hankoAi)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A like: a heart and the count. Yours is coral (your own verdict); the
/// count is ai (the crowd's number). 48 dp to touch.
class ArcLike extends StatelessWidget {
  const ArcLike({
    super.key,
    required this.liked,
    required this.count,
    required this.onTap,
    this.onPaper = false,
  });

  final bool liked;
  final int count;
  final VoidCallback onTap;
  final bool onPaper;

  @override
  Widget build(BuildContext context) {
    final idle = onPaper ? HankoPaper.ink2 : AppTheme.hankoStone;
    return Semantics(
      container: true,
      button: true,
      toggled: liked,
      label: count == 1 ? 'Like, 1 like' : 'Like, $count likes',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minWidth: AppTheme.hankoTouch, minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                      liked
                          ? Icons.favorite_sharp
                          : Icons.favorite_border_sharp,
                      size: 18,
                      color: liked ? AppTheme.hankoCoral : idle),
                  const SizedBox(width: 6),
                  Text('$count',
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoLabelSize,
                          weight: FontWeight.w500,
                          tabular: true,
                          color: onPaper ? HankoPaper.ink2 : AppTheme.hankoAi)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A sealed post's slip: paper, "Sealed · episode 9", "You're on 6", and
/// Open anyway (sumi words on the paper).
class ArcSealSlip extends StatelessWidget {
  const ArcSealSlip({
    super.key,
    required this.ep,
    required this.progress,
    required this.onOpen,
  });

  final int ep;
  final int progress;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final where = progress <= 0
        ? 'This show isn\'t on your list yet'
        : 'You\'re on episode $progress';
    return HankoPaper(
      child: Row(
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sealed · episode $ep',
                      style: AppTheme.hankoSerif(
                          fontSize: AppTheme.hankoListTitleSize,
                          color: HankoPaper.ink,
                          height: 1.3)),
                  const SizedBox(height: 2),
                  Text(where,
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          color: HankoPaper.ink2,
                          height: 1.35)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            container: true,
            button: true,
            label: 'Open anyway, episode $ep',
            child: InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
              child: ExcludeSemantics(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                      minWidth: AppTheme.hankoTouch,
                      minHeight: AppTheme.hankoTouch),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: HankoPaper.ink),
                      borderRadius:
                          BorderRadius.circular(AppTheme.hankoRadius),
                    ),
                    child: Text('Open anyway',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            weight: FontWeight.w600,
                            color: HankoPaper.ink)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// The thread
// ─────────────────────────────────────────────────────────────

class ArcThreadScreen extends StatefulWidget {
  const ArcThreadScreen({
    super.key,
    required this.arc,
    required this.postId,
    this.initial,
  });

  final Arc arc;
  final String postId;
  final ArcPost? initial;

  @override
  State<ArcThreadScreen> createState() => _ArcThreadScreenState();
}

class _ArcThreadScreenState extends State<ArcThreadScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  late final Stream<ArcPost?> _post =
      ArcsService.instance.post(widget.arc.id, widget.postId);
  late final Stream<List<ArcReply>> _replies =
      ArcsService.instance.replies(widget.arc.id, widget.postId);
  late final Stream<Arc?> _arc = ArcsService.instance.arc(widget.arc.id);

  final TextEditingController _reply = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final uid = _uid;
    final text = _reply.text.trim();
    if (uid == null || text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ArcsService.instance.addReply(
          arcId: widget.arc.id, postId: widget.postId, uid: uid, body: text);
      _reply.clear();
    } on ArcsFailure catch (e) {
      // The words stay in the field.
      if (mounted) arcSay(context, e.message);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _like() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await ArcsService.instance.toggleLike(widget.arc.id, widget.postId, uid);
    } on ArcsFailure catch (e) {
      if (mounted) arcSay(context, e.message);
    }
  }

  Future<void> _act(_ArcItemAction action, {String? replyId}) async {
    final uid = _uid;
    if (uid == null) return;
    final svc = ArcsService.instance;
    final arcId = widget.arc.id, postId = widget.postId;
    try {
      switch (action) {
        case _ArcItemAction.delete:
          final ok = await arcConfirm(context,
              title: replyId == null ? 'Delete this post?' : 'Delete this reply?',
              line: replyId == null
                  ? 'Its replies go with it from the arc. This can\'t be undone.'
                  : 'This can\'t be undone.',
              action: 'Delete');
          if (ok != true) return;
          if (replyId == null) {
            await svc.deletePost(arcId, postId);
            if (mounted) Navigator.pop(context);
          } else {
            await svc.deleteReply(arcId, postId, replyId);
          }
        case _ArcItemAction.spoiler:
        case _ArcItemAction.spam:
        case _ArcItemAction.abuse:
          await svc.report(
            uid: uid,
            path: replyId == null
                ? ArcsService.postPath(arcId, postId)
                : ArcsService.replyPath(arcId, postId, replyId),
            reason: action.name,
          );
          if (mounted) arcSay(context, 'Reported. Thank you');
      }
    } on ArcsFailure catch (e) {
      if (mounted) arcSay(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Arc?>(
      stream: _arc,
      initialData: widget.arc,
      builder: (context, a) {
        final arc = a.data ?? widget.arc;
        final member = arc.hasMember(_uid);
        final maker = _uid != null && arc.createdBy == _uid;
        return StreamBuilder<ArcPost?>(
          stream: _post,
          initialData: widget.initial,
          builder: (context, p) {
            final post = p.data;
            final now = DateTime.now();
            return Scaffold(
              backgroundColor: AppTheme.hankoSumi,
              appBar: arcAppBar(arc.name,
                  line: post?.ep != null ? 'Episode ${post!.ep}' : 'Post',
                  actions: [
                    if (post != null && _uid != null)
                      _ArcItemMenu(
                        mine: post.authorId == _uid,
                        maker: maker,
                        onSelect: (x) => _act(x),
                      ),
                  ]),
              body: Column(
                children: [
                  Expanded(
                    child: post == null
                        ? Center(
                            child: Text(
                                p.connectionState == ConnectionState.active
                                    ? 'This post is gone'
                                    : '',
                                style: AppTheme.hankoSerif(
                                    fontSize: AppTheme.hankoFeaturedSize)),
                          )
                        : _thread(arc, post, now, maker),
                  ),
                  if (post != null && member) _composer(),
                  if (post != null && !member && _uid != null)
                    Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: AppTheme.hankoSumi2,
                        border: Border(
                            top: BorderSide(color: AppTheme.hankoHairline)),
                      ),
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.hankoGutter),
                          child: Text('Join the arc to reply',
                              style: AppTheme.hankoSans(
                                  color: AppTheme.hankoStone)),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _thread(Arc arc, ArcPost post, DateTime now, bool maker) {
    final liked = _uid != null && post.likes.contains(_uid);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 12, AppTheme.hankoGutter, 24),
      children: [
        HankoPaper(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        '${post.authorName}  ·  ${arcWhen(post.createdAt, now)}',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            weight: FontWeight.w500,
                            color: HankoPaper.ink2)),
                  ),
                  if (post.ep != null) ArcEpTag(ep: post.ep!, onPaper: true),
                ],
              ),
              if (post.title.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(post.title,
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoFeaturedSize,
                        color: HankoPaper.ink,
                        height: 1.3)),
              ],
              const SizedBox(height: 8),
              SelectableText(post.body,
                  style: AppTheme.hankoSans(
                      color: HankoPaper.ink, height: 1.55)),
              const SizedBox(height: 4),
              Transform.translate(
                offset: const Offset(-12, 0),
                child: ArcLike(
                    liked: liked,
                    count: post.likeCount,
                    onTap: _like,
                    onPaper: true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Replies', style: AppTheme.hankoSerif()),
        const SizedBox(height: 4),
        StreamBuilder<List<ArcReply>>(
          stream: _replies,
          builder: (context, r) {
            if (r.hasError) {
              return _line('Replies can\'t be read right now');
            }
            final replies = r.data ?? const <ArcReply>[];
            if (replies.isEmpty) {
              return _line(r.hasData ? 'No replies yet' : '');
            }
            return Column(
              children: [
                for (final reply in replies)
                  ArcReplyRow(
                    reply: reply,
                    now: now,
                    menu: _uid == null
                        ? null
                        : _ArcItemMenu(
                            mine: reply.authorId == _uid,
                            maker: maker,
                            onSelect: (x) => _act(x, replyId: reply.id),
                          ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _line(String s) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(s, style: AppTheme.hankoSans(color: AppTheme.hankoStone)),
      );

  /// Episode discussions' composer in flat Hanko: sumi 2 under a hairline,
  /// a sumi 3 field with an edge outline (washi when focused), and Send, the
  /// screen's main action.
  Widget _composer() {
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      borderSide: const BorderSide(color: AppTheme.hankoEdge),
    );
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.hankoSumi2,
        border: Border(top: BorderSide(color: AppTheme.hankoHairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.hankoGutter, 10, AppTheme.hankoGutter, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _reply,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: ArcLimits.reply,
                  textCapitalization: TextCapitalization.sentences,
                  cursorColor: AppTheme.hankoWashi,
                  style: AppTheme.hankoSans(height: 1.35),
                  decoration: InputDecoration(
                    hintText: 'Write a reply…',
                    hintStyle: AppTheme.hankoSans(
                        color: AppTheme.hankoAsh, height: 1.35),
                    filled: true,
                    fillColor: AppTheme.hankoSumi3,
                    counterText: '',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    border: edge,
                    enabledBorder: edge,
                    focusedBorder: edge.copyWith(
                        borderSide:
                            const BorderSide(color: AppTheme.hankoWashi)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ArcAction(
                label: 'Send',
                busy: _sending,
                busyLabel: 'Sending…',
                onTap: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One reply: who, when, the words, and its ⋯.
class ArcReplyRow extends StatelessWidget {
  const ArcReplyRow({
    super.key,
    required this.reply,
    required this.now,
    this.menu,
  });

  final ArcReply reply;
  final DateTime now;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.hankoHairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: reply.authorName,
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoMetaSize,
                                weight: FontWeight.w600)),
                        TextSpan(
                            text: '  ·  ${arcWhen(reply.createdAt, now)}',
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoMetaSize,
                                color: AppTheme.hankoStone)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(reply.body, style: AppTheme.hankoSans(height: 1.45)),
                  ],
                ),
              ),
            ),
            ?menu,
          ],
        ),
      ),
    );
  }
}

enum _ArcItemAction { delete, spoiler, spam, abuse }

/// ⋯ on a post or reply: Delete for your own (or anything in your arc, if
/// you made it), Report for everyone else's.
class _ArcItemMenu extends StatelessWidget {
  const _ArcItemMenu({
    required this.mine,
    required this.maker,
    required this.onSelect,
  });

  final bool mine;
  final bool maker;
  final ValueChanged<_ArcItemAction> onSelect;

  @override
  Widget build(BuildContext context) {
    PopupMenuItem<_ArcItemAction> item(_ArcItemAction a, String label) =>
        PopupMenuItem(
          value: a,
          child: Text(label, style: AppTheme.hankoSans()),
        );
    return PopupMenuButton<_ArcItemAction>(
      tooltip: 'More',
      color: AppTheme.hankoSumi3,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius)),
      icon: const Icon(Icons.more_horiz_sharp, color: AppTheme.hankoStone),
      onSelected: onSelect,
      itemBuilder: (_) => [
        if (mine || maker) item(_ArcItemAction.delete, mine ? 'Delete' : 'Remove from the arc'),
        if (!mine) ...[
          item(_ArcItemAction.spoiler, 'Report an unmarked spoiler'),
          item(_ArcItemAction.spam, 'Report spam'),
          item(_ArcItemAction.abuse, 'Report abuse'),
        ],
      ],
    );
  }
}

/// A Hanko confirm: sumi 2, a Mincho question, a stone line, Cancel and the
/// action. Returns true when confirmed.
Future<bool?> arcConfirm(BuildContext context,
    {required String title, required String line, required String action}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.hankoSumi2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoSheetRadius)),
      title: Text(title, style: AppTheme.hankoSerif(fontSize: 18)),
      content: Text(line,
          style: AppTheme.hankoSans(color: AppTheme.hankoStone, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel',
              style: AppTheme.hankoSans(
                  weight: FontWeight.w500, color: AppTheme.hankoStone)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action,
              style: AppTheme.hankoSans(weight: FontWeight.w600)),
        ),
      ],
    ),
  );
}
