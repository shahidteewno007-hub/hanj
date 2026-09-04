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
        'userName':
            user.displayName ?? user.email?.split('@')[0] ?? 'Anonymous',
        'userEmail': user.email,
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
    if (diff.inDays > 7) return DateFormat('MMM d').format(date);
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
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.anime.title,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis),
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
                          style: Theme.of(context).textTheme.bodyMedium),
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
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
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
                              padding: const EdgeInsets.only(left: 36),
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
                          foregroundColor: Colors.white,
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

  Widget _emptyState() {
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
                  color: Colors.white,
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
