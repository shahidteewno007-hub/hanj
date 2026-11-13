import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../models/anime_model.dart';

class EpisodeDiscussionScreen extends StatefulWidget {
  final Anime anime;
  final int episodeNumber;

  const EpisodeDiscussionScreen({
    super.key,
    required this.anime,
    required this.episodeNumber,
  });

  @override
  State<EpisodeDiscussionScreen> createState() =>
      _EpisodeDiscussionScreenState();
}

class _EpisodeDiscussionScreenState extends State<EpisodeDiscussionScreen> {
  /// Flat Hanko for the discussion (the Vibes report's next stage: "Flat
  /// Hanko, not Vibes, for screens still pre-Hanko"; Shahid, 2026-11-10: "go
  /// with your recommendations for everything in future"): a Mincho title,
  /// people as round edge-ringed marks (yours ringed in washi; coral is only
  /// your seal), votes and replies as stone words that turn washi when
  /// they're yours, 48 dp targets, a sumi 2 composer under the one hairline,
  /// a square spoiler box and a washi Post. False gives back a8d40d5's
  /// screen as it was.
  static const bool _printRoom = true;

  final _commentController = TextEditingController();
  final _composerFocus = FocusNode();
  bool _containsSpoilers = false;
  bool _isSubmitting = false;

  // When non-null, the composer is replying to this comment.
  String? _replyingToId;
  String? _replyingToName;

  @override
  void dispose() {
    _commentController.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _startReply(String commentId, String name) {
    setState(() {
      _replyingToId = commentId;
      _replyingToName = name;
    });
    _composerFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToName = null;
    });
  }

  Future<void> _submitComment() async {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return;

    final text = _commentController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('Please write a comment', AppTheme.error);
      return;
    }

    // Capture the reply context and text up front, then clear the field
    // immediately so the box feels responsive — the network write happens
    // after. If it fails, we restore the text.
    final parentId = _replyingToId;
    final spoiler = _containsSpoilers;

    setState(() {
      _isSubmitting = true;
      _replyingToId = null;
      _replyingToName = null;
      _containsSpoilers = false;
    });
    _commentController.clear();
    _composerFocus.unfocus();

    try {
      await FirebaseFirestore.instance.collection('episodeDiscussions').add({
        'animeId': widget.anime.id,
        'animeTitle': widget.anime.title,
        'episodeNumber': widget.episodeNumber,
        'userId': user.uid,
        // Comments are publicly readable, so nothing derived from the email
        // goes in here — not the address, and not its local part, which for
        // most providers is the address. See AUDIT.md D13.
        'userName': user.displayName ?? 'Anonymous',
        'commentText': text,
        'containsSpoilers': spoiler,
        'upvotes': 0,
        'downvotes': 0,
        'parentId': parentId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) setState(() => _isSubmitting = false);
    } catch (e) {
      // Restore what they typed so nothing is lost.
      if (mounted) {
        _commentController.text = text;
        setState(() {
          _isSubmitting = false;
          _containsSpoilers = spoiler;
          _replyingToId = parentId;
        });
      }
      _showSnackBar('Failed to post — try again', AppTheme.error);
    }
  }

  /// Casts a vote. [dir] is +1 (up) or -1 (down). Toggling the same direction
  /// removes the vote; switching direction moves it. Stored per-user in the
  /// comment's `votes` subcollection so each user votes once.
  Future<void> _vote(String commentId, int dir) async {
    final user = Provider.of<AuthService>(context, listen: false).currentUser;
    if (user == null) return;

    final commentRef = FirebaseFirestore.instance
        .collection('episodeDiscussions')
        .doc(commentId);
    final voteRef = commentRef.collection('votes').doc(user.uid);

    try {
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final voteSnap = await txn.get(voteRef);
        final prev = (voteSnap.data()?['dir'] as int?) ?? 0;

        if (prev == dir) {
          // Toggling off
          txn.delete(voteRef);
          txn.update(commentRef, {
            dir > 0 ? 'upvotes' : 'downvotes': FieldValue.increment(-1),
          });
        } else {
          txn.set(voteRef, {
            'dir': dir,
            'votedAt': FieldValue.serverTimestamp(),
          });
          final updates = <String, dynamic>{};
          // Add the new direction
          updates[dir > 0 ? 'upvotes' : 'downvotes'] =
              FieldValue.increment(1);
          // Remove the old one if switching
          if (prev != 0) {
            updates[prev > 0 ? 'upvotes' : 'downvotes'] =
                FieldValue.increment(-1);
          }
          txn.update(commentRef, updates);
        }
      });
    } catch (e) {
      _showSnackBar('Vote error: $e', AppTheme.error);
      rethrow; // let the tile roll back its optimistic arrow
    }
  }

  void _showSnackBar(String message, Color color) {
    if (_printRoom) {
      // Hanko says it in words on sumi 3, square-cornered: no alarm colour.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: AppTheme.hankoSans()),
          backgroundColor: AppTheme.hankoSumi3,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
            side: const BorderSide(color: AppTheme.hankoEdge),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'now';
    final date = timestamp.toDate();
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 7) {
      return DateFormat(_printRoom ? 'd MMM' : 'MMM d').format(date);
    }
    if (diff.inDays > 0) return '${diff.inDays}d';
    if (diff.inHours > 0) return '${diff.inHours}h';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m';
    return 'now';
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<AuthService>(context).currentUser;

    return Scaffold(
      backgroundColor: AppTheme.background,
      resizeToAvoidBottomInset: true,
      appBar: _printRoom ? _hankoAppBar() : AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The title Detail shows (English when AniList has one), ending
            // in Hanko's fade rather than an ellipsis.
            Text(widget.anime.titleEnglish ?? widget.anime.title,
                style: const TextStyle(fontSize: 16),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade),
            Text(
              widget.episodeNumber == 0
                  ? 'Discussion'
                  : 'Episode ${widget.episodeNumber} Discussion',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('episodeDiscussions')
                  .where('animeId', isEqualTo: widget.anime.id)
                  .where('episodeNumber', isEqualTo: widget.episodeNumber)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  // Hanko: stone, the colour of things you wait on.
                  if (_printRoom) {
                    return const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.hankoStone, strokeWidth: 2),
                    );
                  }
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primary, strokeWidth: 2),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('Error loading discussion',
                          textAlign: _printRoom ? TextAlign.center : null,
                          style: _printRoom
                              ? AppTheme.hankoSans(color: AppTheme.hankoStone)
                              : Theme.of(context).textTheme.bodyMedium),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _emptyState();
                }

                // Split into top-level comments and replies-by-parent.
                final all = snapshot.data!.docs;
                final tops = <QueryDocumentSnapshot>[];
                final repliesByParent =
                    <String, List<QueryDocumentSnapshot>>{};

                for (final d in all) {
                  final data = d.data() as Map<String, dynamic>;
                  final parentId = data['parentId'] as String?;
                  if (parentId == null) {
                    tops.add(d);
                  } else {
                    repliesByParent.putIfAbsent(parentId, () => []).add(d);
                  }
                }

                int byNewest(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
                  final at = (a.data() as Map)['createdAt'] as Timestamp?;
                  final bt = (b.data() as Map)['createdAt'] as Timestamp?;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  return bt.compareTo(at);
                }

                tops.sort(byNewest);
                for (final list in repliesByParent.values) {
                  // Replies oldest-first reads more naturally as a thread.
                  list.sort((a, b) => byNewest(b, a));
                }

                if (tops.isEmpty) return _emptyState();

                return ListView.builder(
                  // Hanko's 20 dp gutter; replies indent to the text column
                  // (a 28 dp mark and its 10 dp gap).
                  padding: _printRoom
                      ? const EdgeInsets.fromLTRB(
                          AppTheme.hankoGutter, 4, AppTheme.hankoGutter, 16)
                      : const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  itemCount: tops.length,
                  itemBuilder: (context, index) {
                    final comment = tops[index];
                    final replies = repliesByParent[comment.id] ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CommentTile(
                          key: ValueKey(comment.id),
                          commentId: comment.id,
                          data: comment.data() as Map<String, dynamic>,
                          currentUserId: user?.uid,
                          onVote: _vote,
                          onReply: _startReply,
                          formatDate: _formatDate,
                          isReply: false,
                        ),
                        // One level of replies, indented.
                        ...replies.map((r) => Padding(
                              padding: EdgeInsets.only(
                                  left: _printRoom ? 38 : 36),
                              child: _CommentTile(
                                key: ValueKey(r.id),
                                commentId: r.id,
                                data: r.data() as Map<String, dynamic>,
                                currentUserId: user?.uid,
                                onVote: _vote,
                                onReply: _startReply,
                                formatDate: _formatDate,
                                isReply: true,
                              ),
                            )),
                        const SizedBox(height: 6),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ── Composer ──────────────────────────────────────────
          if (_printRoom)
            _hankoComposer()
          else
          SafeArea(
            top: false,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.cardBorder)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reply context bar
                  if (_replyingToId != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(Icons.reply_rounded,
                              size: 14, color: AppTheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Replying to $_replyingToName',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.primary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: _cancelReply,
                            child: const Icon(Icons.close_rounded,
                                size: 16, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: _commentController,
                    focusNode: _composerFocus,
                    maxLines: 3,
                    minLines: 1,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: _replyingToId != null
                          ? 'Write a reply...'
                          : 'Share your thoughts...',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.surfaceLight,
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _containsSpoilers,
                          activeColor: AppTheme.primary,
                          onChanged: (value) => setState(
                              () => _containsSpoilers = value ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Spoiler',
                          style: TextStyle(
                            color: _containsSpoilers
                                ? AppTheme.primary
                                : AppTheme.textMuted,
                            fontSize: 13,
                          )),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submitComment,
                        icon: _isSubmitting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send_rounded, size: 16),
                        label: Text(_isSubmitting ? 'Posting...' : 'Post'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.textInverse, // sumi on coral, 5.64:1
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The bar in Hanko: the show's title in Mincho 16, fading rather than
  /// ending in "⋯", over the episode in stone Jost.
  PreferredSizeWidget _hankoAppBar() {
    return AppBar(
      backgroundColor: AppTheme.hankoSumi,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.anime.titleEnglish ?? widget.anime.title,
              style: AppTheme.hankoSerif(height: 1.3),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade),
          Text(
            widget.episodeNumber == 0
                ? 'Discussion'
                : 'Episode ${widget.episodeNumber} Discussion',
            style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoLabelSize,
                color: AppTheme.hankoStone,
                height: 1.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// The composer in Hanko: sumi 2 under the screen's one hairline, carried
  /// down under the system bar; Hanko's field (sumi 3, edge outline, washi
  /// when focused); a square spoiler box in words; and the screen's main
  /// action, Post, washi with sumi words. Same controller, focus, limits and
  /// handlers as before.
  Widget _hankoComposer() {
    final edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      borderSide: const BorderSide(color: AppTheme.hankoEdge),
    );
    final replying = _replyingToId != null;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.hankoSumi2,
        border: Border(top: BorderSide(color: AppTheme.hankoHairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTheme.hankoGutter, 10, AppTheme.hankoGutter, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply context, with a 48 dp way out of it.
              if (replying)
                Row(
                  children: [
                    const Icon(Icons.reply_rounded,
                        size: 16, color: AppTheme.hankoStone),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Replying to $_replyingToName',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoLabelSize,
                            color: AppTheme.hankoStone),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(8, 0),
                      child: _HankoAction(
                        semanticLabel: 'Cancel reply',
                        onTap: _cancelReply,
                        child: const Icon(Icons.close_sharp,
                            size: 18, color: AppTheme.hankoStone),
                      ),
                    ),
                  ],
                ),
              TextField(
                controller: _commentController,
                focusNode: _composerFocus,
                maxLines: 3,
                minLines: 1,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                cursorColor: AppTheme.hankoWashi,
                style: AppTheme.hankoSans(height: 1.35),
                decoration: InputDecoration(
                  hintText: replying
                      ? 'Write a reply…'
                      : 'Share your thoughts…',
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
              const SizedBox(height: 4),
              Row(
                children: [
                  // The box's edge lines up with the field's.
                  Transform.translate(
                    offset: const Offset(-8, 0),
                    child: _HankoAction(
                      semanticLabel: 'Contains spoilers',
                      checked: _containsSpoilers,
                      onTap: () => setState(
                          () => _containsSpoilers = !_containsSpoilers),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              _containsSpoilers
                                  ? Icons.check_box_sharp
                                  : Icons.check_box_outline_blank_sharp,
                              size: 20,
                              color: _containsSpoilers
                                  ? AppTheme.hankoWashi
                                  : AppTheme.hankoStone),
                          const SizedBox(width: 8),
                          Text('Spoiler',
                              style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoMetaSize,
                                weight: FontWeight.w500,
                                color: _containsSpoilers
                                    ? AppTheme.hankoWashi
                                    : AppTheme.hankoStone,
                              )),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  _hankoPost(),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  /// Post, the screen's one main action: a washi tile with sumi words
  /// (15.34:1), 2 px corners, an 8% sumi wash on press and no ripple, as
  /// Detail's _HankoMainAction. While a post is on its way it reads
  /// "Posting…" with a sumi spinner and can't be pressed again.
  Widget _hankoPost() {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: AppTheme.hankoWashi,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: InkWell(
          onTap: _isSubmitting ? null : _submitComment,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
                minWidth: AppTheme.hankoTouch, minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isSubmitting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.hankoSumi),
                    )
                  else
                    const Icon(Icons.send_sharp,
                        size: 18, color: AppTheme.hankoSumi),
                  const SizedBox(width: 8),
                  Text(
                    _isSubmitting ? 'Posting…' : 'Post',
                    style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoListTitleSize,
                      weight: FontWeight.w600,
                      color: AppTheme.hankoSumi,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    if (_printRoom) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.forum_outlined,
                  color: AppTheme.hankoEdge, size: 40),
              const SizedBox(height: 16),
              Text('No comments yet',
                  textAlign: TextAlign.center,
                  style: AppTheme.hankoSerif(height: 1.3)),
              const SizedBox(height: 6),
              Text('Be the first to comment!',
                  textAlign: TextAlign.center,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      color: AppTheme.hankoStone)),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              color: AppTheme.textMuted.withValues(alpha: 0.5), size: 56),
          const SizedBox(height: 14),
          Text('No comments yet',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Be the first to comment!',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ── Compact comment tile ──────────────────────────────────────
class _CommentTile extends StatefulWidget {
  final String commentId;
  final Map<String, dynamic> data;
  final String? currentUserId;
  final Future<void> Function(String, int) onVote;
  final void Function(String, String) onReply;
  final String Function(Timestamp?) formatDate;
  final bool isReply;

  const _CommentTile({
    super.key,
    required this.commentId,
    required this.data,
    required this.currentUserId,
    required this.onVote,
    required this.onReply,
    required this.formatDate,
    required this.isReply,
  });

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _showSpoilers = false;
  int _myVote = 0; // -1, 0, or +1

  @override
  void initState() {
    super.initState();
    _loadMyVote();
  }

  Future<void> _loadMyVote() async {
    if (widget.currentUserId == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('episodeDiscussions')
          .doc(widget.commentId)
          .collection('votes')
          .doc(widget.currentUserId)
          .get();
      if (mounted && doc.exists) {
        setState(() => _myVote = (doc.data()?['dir'] as int?) ?? 0);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.data['userName'] as String? ?? 'Anonymous';
    final commentText = widget.data['commentText'] as String? ?? '';
    final containsSpoilers =
        widget.data['containsSpoilers'] as bool? ?? false;
    final upvotes = widget.data['upvotes'] as int? ?? 0;
    final downvotes = widget.data['downvotes'] as int? ?? 0;
    final createdAt = widget.data['createdAt'] as Timestamp?;
    final shouldHide = containsSpoilers && !_showSpoilers;

    if (_EpisodeDiscussionScreenState._printRoom) {
      return _printed(
        userName: userName,
        commentText: commentText,
        containsSpoilers: containsSpoilers,
        upvotes: upvotes,
        downvotes: downvotes,
        createdAt: createdAt,
        shouldHide: shouldHide,
      );
    }

    final avatarRadius = widget.isReply ? 12.0 : 14.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.primary,
            radius: avatarRadius,
            child: Text(
              userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
              style: TextStyle(
                  // Sumi on coral, 5.64:1 (Hanko's rule; white was 3.35:1).
                  color: AppTheme.textInverse,
                  fontWeight: FontWeight.bold,
                  fontSize: widget.isReply ? 11 : 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name · time on one compact line
                Row(
                  children: [
                    Flexible(
                      child: Text(userName,
                          style: AppTheme.sans(
                              fontSize: 13, weight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    Text('· ${widget.formatDate(createdAt)}',
                        style: AppTheme.sans(
                            fontSize: 11, color: AppTheme.textMuted)),
                    if (containsSpoilers) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.warning_rounded,
                          size: 12, color: AppTheme.warning),
                    ],
                  ],
                ),
                const SizedBox(height: 3),

                // Body or spoiler veil
                if (shouldHide)
                  GestureDetector(
                    onTap: () => setState(() => _showSpoilers = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility_off_rounded,
                              color: AppTheme.textMuted, size: 14),
                          const SizedBox(width: 6),
                          Text('Tap to reveal spoiler',
                              style: AppTheme.sans(
                                  fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  )
                else
                  Text(commentText,
                      style: AppTheme.sans(
                          fontSize: 14, color: AppTheme.textPrimary)
                          .copyWith(height: 1.35)),

                const SizedBox(height: 6),

                // Action row: up / down / reply — compact icon buttons
                Row(
                  children: [
                    _voteChip(
                      icon: Icons.arrow_upward_rounded,
                      active: _myVote > 0,
                      activeColor: AppTheme.primary,
                      count: upvotes,
                      onTap: () => _castVote(1),
                    ),
                    const SizedBox(width: 14),
                    _voteChip(
                      icon: Icons.arrow_downward_rounded,
                      active: _myVote < 0,
                      activeColor: AppTheme.error,
                      count: downvotes,
                      onTap: () => _castVote(-1),
                    ),
                    const SizedBox(width: 14),
                    // Replies attach to the top-level comment. Replying to a
                    // reply still threads under the same parent.
                    if (!widget.isReply)
                      GestureDetector(
                        onTap: () =>
                            widget.onReply(widget.commentId, userName),
                        child: Row(
                          children: [
                            const Icon(Icons.reply_rounded,
                                size: 15, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Text('Reply',
                                style: AppTheme.sans(
                                    fontSize: 12,
                                    color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The comment in flat Hanko. People are round: a sumi 3 mark ringed in
  /// the edge colour, as other people's marks are, or in washi when the
  /// comment is yours (coral stays your rating seal's alone). The name in
  /// Jost 600 and the time in stone; a spoiler is said in words, not a gold
  /// sign, and veiled under a square sumi 3 tile you press to reveal. Votes
  /// and Reply are stone words in 48 dp targets, washi with a filled mark
  /// for the vote that's yours (no coral, no red).
  Widget _printed({
    required String userName,
    required String commentText,
    required bool containsSpoilers,
    required int upvotes,
    required int downvotes,
    required Timestamp? createdAt,
    required bool shouldHide,
  }) {
    final mine = widget.currentUserId != null &&
        widget.data['userId'] == widget.currentUserId;
    final markSize = widget.isReply ? 24.0 : 28.0;
    final meta = AppTheme.hankoSans(
        fontSize: AppTheme.hankoDataSmallSize,
        weight: FontWeight.w500,
        color: AppTheme.hankoStone,
        height: 1.3);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: markSize,
              height: markSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.hankoSumi3,
                shape: BoxShape.circle,
                border: Border.all(
                    color: mine ? AppTheme.hankoWashi : AppTheme.hankoEdge),
              ),
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : 'A',
                style: AppTheme.hankoSans(
                  fontSize: widget.isReply
                      ? AppTheme.hankoDataSmallSize
                      : AppTheme.hankoMetaSize,
                  weight: FontWeight.w600,
                  height: 1,
                ),
              ),
            ),
          ),
          SizedBox(width: widget.isReply ? 14 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name · time · spoiler on one line
                Row(
                  children: [
                    Flexible(
                      child: Text(userName,
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              weight: FontWeight.w600,
                              height: 1.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    Text('· ${widget.formatDate(createdAt)}', style: meta),
                    if (containsSpoilers) ...[
                      const SizedBox(width: 6),
                      Text('· Spoiler', style: meta),
                    ],
                  ],
                ),
                const SizedBox(height: 4),

                // Body or spoiler veil
                if (shouldHide)
                  _HankoAction(
                    semanticLabel: 'Spoiler hidden. Reveal it',
                    fill: AppTheme.hankoSumi3,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onTap: () => setState(() => _showSpoilers = true),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.visibility_off_outlined,
                            color: AppTheme.hankoStone, size: 16),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text('Spoiler · tap to reveal',
                              style: AppTheme.hankoSans(
                                  fontSize: AppTheme.hankoMetaSize,
                                  color: AppTheme.hankoStone)),
                        ),
                      ],
                    ),
                  )
                else
                  Text(commentText,
                      style: AppTheme.hankoSans(height: 1.4)),

                // Up / down / Reply, their marks in line with the text.
                Transform.translate(
                  offset: const Offset(-8, 0),
                  child: Row(
                    children: [
                      _hankoVote(up: true, count: upvotes),
                      _hankoVote(up: false, count: downvotes),
                      // Replies attach to the top-level comment.
                      if (!widget.isReply)
                        _HankoAction(
                          semanticLabel: 'Reply to $userName',
                          onTap: () =>
                              widget.onReply(widget.commentId, userName),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.reply_rounded,
                                  size: 18, color: AppTheme.hankoStone),
                              const SizedBox(width: 4),
                              Text('Reply',
                                  style: AppTheme.hankoSans(
                                      fontSize: AppTheme.hankoLabelSize,
                                      weight: FontWeight.w500,
                                      color: AppTheme.hankoStone)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One vote in Hanko: stone and outlined, or washi and filled when it's
  /// yours; the count in tabular Jost. A toggle for a screen reader.
  Widget _hankoVote({required bool up, required int count}) {
    final active = up ? _myVote > 0 : _myVote < 0;
    final color = active ? AppTheme.hankoWashi : AppTheme.hankoStone;
    final IconData icon = up
        ? (active ? Icons.arrow_circle_up : Icons.arrow_circle_up_outlined)
        : (active ? Icons.arrow_circle_down : Icons.arrow_circle_down_outlined);
    return _HankoAction(
      semanticLabel: '${up ? 'Upvote' : 'Downvote'}, $count',
      toggled: active,
      onTap: () => _castVote(up ? 1 : -1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text('$count',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  weight: FontWeight.w500,
                  color: color,
                  tabular: true)),
        ],
      ),
    );
  }

  Future<void> _castVote(int dir) async {
    final previous = _myVote;
    // Optimistic local update for snappy feel
    setState(() => _myVote = _myVote == dir ? 0 : dir);
    try {
      await widget.onVote(widget.commentId, dir);
    } catch (_) {
      // Roll back if the write failed, so the arrow doesn't lie.
      if (mounted) setState(() => _myVote = previous);
    }
  }

  Widget _voteChip({
    required IconData icon,
    required bool active,
    required Color activeColor,
    required int count,
    required VoidCallback onTap,
  }) {
    final color = active ? activeColor : AppTheme.textMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text('$count',
              style: AppTheme.sans(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

/// A small Hanko control (a vote, Reply, the spoiler box, a veiled spoiler,
/// cancelling a reply): drawn as its [child] on [fill] (none by default),
/// touched at 48 dp, pressed with an 8% washi wash and no ripple. Its own
/// semantics node, named by [semanticLabel] (a toggle when [toggled] is
/// given, a checkbox when [checked] is), with the InkWell's tap and keyboard
/// focus inside it; keyboard focus draws a washi keyline round the target.
class _HankoAction extends StatefulWidget {
  const _HankoAction({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.toggled,
    this.checked,
    this.fill,
    this.padding = const EdgeInsets.symmetric(horizontal: 8),
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;
  final bool? toggled;
  final bool? checked;
  final Color? fill;
  final EdgeInsetsGeometry padding;

  @override
  State<_HankoAction> createState() => _HankoActionState();
}

class _HankoActionState extends State<_HankoAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.hankoRadius);
    final fill = widget.fill;
    return Semantics(
      container: true,
      button: widget.checked == null,
      toggled: widget.toggled,
      checked: widget.checked,
      label: widget.semanticLabel,
      child: Material(
        type: fill == null ? MaterialType.transparency : MaterialType.canvas,
        color: fill,
        borderRadius: fill == null ? null : radius,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (v) => setState(() => _focused = v),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          focusColor: Colors.transparent,
          borderRadius: radius,
          child: ExcludeSemantics(
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _focused ? AppTheme.hankoWashi : Colors.transparent,
                  width: 2,
                ),
                borderRadius: radius,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    minWidth: AppTheme.hankoTouch,
                    minHeight: AppTheme.hankoTouch),
                child: Padding(
                  padding: widget.padding,
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
