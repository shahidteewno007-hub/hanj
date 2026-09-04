import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// Arcs Screen — list of all arcs
// ─────────────────────────────────────────────────────────────

class ArcsScreen extends StatefulWidget {
  const ArcsScreen({super.key});

  @override
  State<ArcsScreen> createState() => _ArcsScreenState();
}

class _ArcsScreenState extends State<ArcsScreen>
    with SingleTickerProviderStateMixin {
  // ── Beta gate ──────────────────────────────────────────────
  // Arcs (community groups) is a full social feature, kept hidden behind a
  // "Coming soon" placeholder during beta. All the live code below is intact
  // and fully wired — flip this to `false` post-beta to enable it.
  static const bool _comingSoon = true;

  late TabController _tabController;
  final _uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_comingSoon) return _buildComingSoon();
    return _buildLive();
  }

  // ── Coming-soon placeholder (beta) ─────────────────────────
  Widget _buildComingSoon() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        title: Row(
          children: [
            Text('Arcs',
                style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Text('SOON',
                  style: AppTheme.mono(
                      fontSize: 9,
                      color: AppTheme.primary,
                      letterSpacing: 1)),
            ),
          ],
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                      width: 1.2),
                ),
                child: Icon(Icons.groups_2_outlined,
                    color: AppTheme.primary, size: 40),
              ),
              const SizedBox(height: 28),
              Text(
                'Arcs are coming',
                style: AppTheme.serif(fontSize: 26, weight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Join communities around the series you love — '
                'discuss episodes, theories, and find your people.',
                style: AppTheme.sans(
                    fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_outlined,
                        size: 14, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text('Arriving after beta',
                        style: AppTheme.mono(
                            fontSize: 11,
                            color: AppTheme.primary,
                            letterSpacing: 1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Live feature (post-beta) ───────────────────────────────
  Widget _buildLive() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            Text('Arcs', style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Text('BETA',
                  style: AppTheme.mono(fontSize: 9, color: AppTheme.primary, letterSpacing: 1)),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          tabs: const [Tab(text: 'DISCOVER'), Tab(text: 'MY ARCS')],
          labelStyle: AppTheme.mono(fontSize: 11, color: AppTheme.primary, letterSpacing: 1),
          unselectedLabelStyle: AppTheme.mono(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateArcSheet(context),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('Create Arc', style: AppTheme.sans(color: Colors.white, weight: FontWeight.w600)),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ArcsListTab(showAll: true, uid: _uid),
          _ArcsListTab(showAll: false, uid: _uid),
        ],
      ),
    );
  }

  void _showCreateArcSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateArcSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Arcs List Tab
// ─────────────────────────────────────────────────────────────

class _ArcsListTab extends StatelessWidget {
  final bool showAll;
  final String? uid;

  const _ArcsListTab({required this.showAll, required this.uid});

  @override
  Widget build(BuildContext context) {
    final query = showAll
        ? FirebaseFirestore.instance
            .collection('arcs')
            .orderBy('memberCount', descending: true)
            .limit(30)
        : FirebaseFirestore.instance
            .collection('arcs')
            .where('members', arrayContains: uid ?? '')
            .limit(30);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(
              color: AppTheme.primary, strokeWidth: 2));
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🏛️', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text(
                  showAll ? 'No arcs yet' : 'You haven\'t joined any arcs',
                  style: AppTheme.serif(fontSize: 18, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  showAll
                      ? 'Be the first to create one!'
                      : 'Discover and join arcs to discuss anime',
                  style: AppTheme.sans(color: AppTheme.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final data = docs[i].data() as Map<String, dynamic>;
            return _ArcCard(
              arcId: docs[i].id,
              data: data,
              uid: uid,
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Arc Card
// ─────────────────────────────────────────────────────────────

class _ArcCard extends StatelessWidget {
  final String arcId;
  final Map<String, dynamic> data;
  final String? uid;

  const _ArcCard({required this.arcId, required this.data, required this.uid});

  bool get _isMember {
    final members = (data['members'] as List<dynamic>?) ?? [];
    return members.contains(uid);
  }

  @override
  Widget build(BuildContext context) {
    final name        = data['name'] as String? ?? 'Unnamed Arc';
    final description = data['description'] as String? ?? '';
    final memberCount = data['memberCount'] as int? ?? 0;
    final postCount   = data['postCount'] as int? ?? 0;
    final emoji       = data['emoji'] as String? ?? '🎌';
    final colorHex    = data['color'] as String? ?? 'E8624A';
    final color       = Color(int.parse('FF$colorHex', radix: 16));
    final tags        = (data['tags'] as List<dynamic>?)?.cast<String>() ?? [];

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ArcDetailScreen(
              arcId: arcId, data: data, uid: uid))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isMember
                ? color.withValues(alpha: 0.4)
                : AppTheme.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Emoji avatar
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Center(child: Text(emoji,
                      style: const TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                style: AppTheme.serif(
                                    fontSize: 16, weight: FontWeight.w700)),
                          ),
                          if (_isMember)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('JOINED',
                                  style: AppTheme.mono(
                                      fontSize: 9,
                                      color: color,
                                      letterSpacing: 1)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.people_outline_rounded,
                              color: AppTheme.textMuted, size: 12),
                          const SizedBox(width: 4),
                          Text('$memberCount members',
                              style: AppTheme.mono(fontSize: 10,
                                  color: AppTheme.textMuted)),
                          const SizedBox(width: 12),
                          Icon(Icons.chat_bubble_outline_rounded,
                              color: AppTheme.textMuted, size: 12),
                          const SizedBox(width: 4),
                          Text('$postCount posts',
                              style: AppTheme.mono(fontSize: 10,
                                  color: AppTheme.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(description,
                  style: AppTheme.sans(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],

            if (tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                children: tags.take(4).map((tag) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text('#$tag',
                      style: AppTheme.mono(
                          fontSize: 10, color: AppTheme.textMuted)),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Arc Detail Screen
// ─────────────────────────────────────────────────────────────

class ArcDetailScreen extends StatefulWidget {
  final String arcId;
  final Map<String, dynamic> data;
  final String? uid;

  const ArcDetailScreen({
    super.key,
    required this.arcId,
    required this.data,
    required this.uid,
  });

  @override
  State<ArcDetailScreen> createState() => _ArcDetailScreenState();
}

class _ArcDetailScreenState extends State<ArcDetailScreen> {
  bool _isMember = false;
  bool _isJoining = false;

  @override
  void initState() {
    super.initState();
    final members = (widget.data['members'] as List<dynamic>?) ?? [];
    _isMember = members.contains(widget.uid);
  }

  Future<void> _toggleMembership() async {
    if (widget.uid == null) return;
    setState(() => _isJoining = true);

    final ref = FirebaseFirestore.instance
        .collection('arcs').doc(widget.arcId);

    try {
      if (_isMember) {
        await ref.update({
          'members': FieldValue.arrayRemove([widget.uid]),
          'memberCount': FieldValue.increment(-1),
        });
        setState(() { _isMember = false; _isJoining = false; });
      } else {
        await ref.update({
          'members': FieldValue.arrayUnion([widget.uid]),
          'memberCount': FieldValue.increment(1),
        });
        setState(() { _isMember = true; _isJoining = false; });
      }
    } catch (_) {
      setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name        = widget.data['name'] as String? ?? 'Arc';
    final description = widget.data['description'] as String? ?? '';
    final emoji       = widget.data['emoji'] as String? ?? '🎌';
    final colorHex    = widget.data['color'] as String? ?? 'E8624A';
    final color       = Color(int.parse('FF$colorHex', radix: 16));
    final memberCount = widget.data['memberCount'] as int? ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, _) => [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppTheme.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.3),
                      AppTheme.background,
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Text(emoji, style: const TextStyle(fontSize: 56)),
                      const SizedBox(height: 8),
                      Text(name,
                          style: AppTheme.serif(
                              fontSize: 24, weight: FontWeight.w700)),
                      Text('$memberCount members',
                          style: AppTheme.mono(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                              letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _isJoining
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: AppTheme.primary, strokeWidth: 2))
                    : GestureDetector(
                        onTap: _toggleMembership,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _isMember
                                ? AppTheme.surfaceMid
                                : AppTheme.primary,
                            borderRadius: BorderRadius.circular(20),
                            border: _isMember
                                ? Border.all(color: AppTheme.border)
                                : null,
                          ),
                          child: Text(
                            _isMember ? 'Leave' : 'Join Arc',
                            style: AppTheme.sans(
                                fontSize: 13,
                                weight: FontWeight.w600,
                                color: _isMember
                                    ? AppTheme.textSecondary
                                    : Colors.white),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
        body: Column(
          children: [
            if (description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(description,
                    style: AppTheme.sans(
                        color: AppTheme.textSecondary, height: 1.6)),
              ),

            const SizedBox(height: 16),

            // Post button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GestureDetector(
                onTap: _isMember
                    ? () => _showPostSheet(context)
                    : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined,
                          color: AppTheme.textMuted, size: 16),
                      const SizedBox(width: 10),
                      Text(
                        _isMember
                            ? 'Start a discussion...'
                            : 'Join to post',
                        style: AppTheme.sans(
                            color: AppTheme.textMuted, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Posts list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('arcs')
                    .doc(widget.arcId)
                    .collection('posts')
                    .orderBy('createdAt', descending: true)
                    .limit(50)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(
                        color: AppTheme.primary, strokeWidth: 2));
                  }

                  final posts = snapshot.data?.docs ?? [];

                  if (posts.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('💬', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 16),
                          Text('No discussions yet',
                              style: AppTheme.serif(fontSize: 18)),
                          const SizedBox(height: 8),
                          Text(
                            _isMember
                                ? 'Start the first one!'
                                : 'Join the arc to start discussions',
                            style: AppTheme.sans(
                                color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    itemCount: posts.length,
                    itemBuilder: (_, i) {
                      final postData =
                          posts[i].data() as Map<String, dynamic>;
                      return _PostCard(
                        postId: posts[i].id,
                        arcId: widget.arcId,
                        data: postData,
                        uid: widget.uid,
                        accentColor: color,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPostSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePostSheet(
          arcId: widget.arcId, uid: widget.uid),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Post Card
// ─────────────────────────────────────────────────────────────

class _PostCard extends StatelessWidget {
  final String postId;
  final String arcId;
  final Map<String, dynamic> data;
  final String? uid;
  final Color accentColor;

  const _PostCard({
    required this.postId,
    required this.arcId,
    required this.data,
    required this.uid,
    required this.accentColor,
  });

  Future<void> _toggleLike() async {
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('arcs').doc(arcId)
        .collection('posts').doc(postId);
    final likes = (data['likes'] as List<dynamic>?) ?? [];
    if (likes.contains(uid)) {
      await ref.update({
        'likes': FieldValue.arrayRemove([uid]),
        'likeCount': FieldValue.increment(-1),
      });
    } else {
      await ref.update({
        'likes': FieldValue.arrayUnion([uid]),
        'likeCount': FieldValue.increment(1),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title       = data['title'] as String? ?? '';
    final body        = data['body'] as String? ?? '';
    final authorName  = data['authorName'] as String? ?? 'Anonymous';
    final likeCount   = data['likeCount'] as int? ?? 0;
    final replyCount  = data['replyCount'] as int? ?? 0;
    final createdAt   = (data['createdAt'] as Timestamp?)?.toDate();
    final likes       = (data['likes'] as List<dynamic>?) ?? [];
    final isLiked     = likes.contains(uid);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author + time
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    authorName.isNotEmpty
                        ? authorName[0].toUpperCase()
                        : 'A',
                    style: TextStyle(
                        color: accentColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(authorName,
                  style: AppTheme.sans(
                      fontSize: 13, weight: FontWeight.w600)),
              const Spacer(),
              if (createdAt != null)
                Text(_formatTime(createdAt),
                    style: AppTheme.mono(
                        fontSize: 10, color: AppTheme.textMuted)),
            ],
          ),

          const SizedBox(height: 10),

          if (title.isNotEmpty) ...[
            Text(title,
                style: AppTheme.serif(
                    fontSize: 15, weight: FontWeight.w700)),
            const SizedBox(height: 6),
          ],

          if (body.isNotEmpty)
            Text(body,
                style: AppTheme.sans(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.5),
                maxLines: 4,
                overflow: TextOverflow.ellipsis),

          const SizedBox(height: 12),

          // Actions
          Row(
            children: [
              GestureDetector(
                onTap: _toggleLike,
                child: Row(
                  children: [
                    Icon(
                      isLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: isLiked ? AppTheme.primary : AppTheme.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text('$likeCount',
                        style: AppTheme.mono(
                            fontSize: 11,
                            color: isLiked
                                ? AppTheme.primary
                                : AppTheme.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PostDetailScreen(
                        arcId: arcId, postId: postId,
                        data: data, uid: uid,
                        accentColor: accentColor))),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded,
                        color: AppTheme.textMuted, size: 16),
                    const SizedBox(width: 4),
                    Text('$replyCount',
                        style: AppTheme.mono(
                            fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(dt);
  }
}

// ─────────────────────────────────────────────────────────────
// Post Detail Screen (with replies)
// ─────────────────────────────────────────────────────────────

class PostDetailScreen extends StatefulWidget {
  final String arcId;
  final String postId;
  final Map<String, dynamic> data;
  final String? uid;
  final Color accentColor;

  const PostDetailScreen({
    super.key,
    required this.arcId,
    required this.postId,
    required this.data,
    required this.uid,
    required this.accentColor,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _replyCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReply() async {
    if (_replyCtrl.text.trim().isEmpty || widget.uid == null) return;
    setState(() => _sending = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(widget.uid).get();
      final name = userDoc.data()?['displayName'] as String? ?? 'Anonymous';

      await FirebaseFirestore.instance
          .collection('arcs').doc(widget.arcId)
          .collection('posts').doc(widget.postId)
          .collection('replies').add({
        'body': _replyCtrl.text.trim(),
        'authorId': widget.uid,
        'authorName': name,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('arcs').doc(widget.arcId)
          .collection('posts').doc(widget.postId)
          .update({'replyCount': FieldValue.increment(1)});

      _replyCtrl.clear();
    } catch (_) {}

    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.data['title'] as String? ?? '';
    final body  = widget.data['body'] as String? ?? '';
    final authorName = widget.data['authorName'] as String? ?? 'Anonymous';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Discussion',
            style: AppTheme.serif(fontSize: 18, weight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Original post
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: widget.accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: widget.accentColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Center(child: Text(
                              authorName.isNotEmpty ? authorName[0].toUpperCase() : 'A',
                              style: TextStyle(color: widget.accentColor,
                                  fontWeight: FontWeight.w700),
                            )),
                          ),
                          const SizedBox(width: 8),
                          Text(authorName,
                              style: AppTheme.sans(
                                  fontSize: 14, weight: FontWeight.w600)),
                        ],
                      ),
                      if (title.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(title,
                            style: AppTheme.serif(
                                fontSize: 18, weight: FontWeight.w700)),
                      ],
                      if (body.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(body,
                            style: AppTheme.sans(
                                color: AppTheme.textSecondary, height: 1.6)),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                Text('Replies',
                    style: AppTheme.serif(
                        fontSize: 16, weight: FontWeight.w600)),
                const SizedBox(height: 12),

                // Replies
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('arcs').doc(widget.arcId)
                      .collection('posts').doc(widget.postId)
                      .collection('replies')
                      .orderBy('createdAt')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final replies = snapshot.data?.docs ?? [];
                    if (replies.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: Text('No replies yet — be the first!',
                            style: AppTheme.sans(color: AppTheme.textMuted))),
                      );
                    }
                    return Column(
                      children: replies.map((r) {
                        final d = r.data() as Map<String, dynamic>;
                        return _ReplyCard(data: d, accentColor: widget.accentColor);
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          // Reply input
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16,
                MediaQuery.of(context).viewInsets.bottom + 12),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    style: AppTheme.sans(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Write a reply...',
                      hintStyle: AppTheme.sans(
                          color: AppTheme.textMuted, fontSize: 14),
                      filled: true,
                      fillColor: AppTheme.surfaceLight,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sending ? null : _sendReply,
                  child: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: _sending
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.send_rounded,
                            color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accentColor;
  const _ReplyCard({required this.data, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final body       = data['body'] as String? ?? '';
    final authorName = data['authorName'] as String? ?? 'Anonymous';
    final createdAt  = (data['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(child: Text(
              authorName.isNotEmpty ? authorName[0].toUpperCase() : 'A',
              style: TextStyle(color: accentColor, fontSize: 11,
                  fontWeight: FontWeight.w700),
            )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(authorName,
                        style: AppTheme.sans(
                            fontSize: 12, weight: FontWeight.w600)),
                    const Spacer(),
                    if (createdAt != null)
                      Text(_formatTime(createdAt),
                          style: AppTheme.mono(
                              fontSize: 9, color: AppTheme.textMuted)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(body, style: AppTheme.sans(
                    fontSize: 13, color: AppTheme.textSecondary, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

// ─────────────────────────────────────────────────────────────
// Create Arc Sheet
// ─────────────────────────────────────────────────────────────

class _CreateArcSheet extends StatefulWidget {
  const _CreateArcSheet();

  @override
  State<_CreateArcSheet> createState() => _CreateArcSheetState();
}

class _CreateArcSheetState extends State<_CreateArcSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagCtrl  = TextEditingController();

  String _selectedEmoji = '🎌';
  String _selectedColor = 'E8624A';
  final List<String> _tags = [];
  bool _creating = false;

  static const _emojis = ['🎌', '⚔️', '🔥', '💙', '🌙', '🧠', '👁️',
      '🌊', '✨', '💀', '👨‍👩‍👧', '🎭', '🏆', '🎵', '🌸', '⚡'];

  static const _colors = [
    ('E8624A', Color(0xFFE8624A)),
    ('4A7FB5', Color(0xFF4A7FB5)),
    ('4A9B6F', Color(0xFF4A9B6F)),
    ('D4A96A', Color(0xFFD4A96A)),
    ('CF6679', Color(0xFFCF6679)),
    ('9B59B6', Color(0xFF9B59B6)),
    ('00BCD4', Color(0xFF00BCD4)),
    ('FF8C00', Color(0xFFFF8C00)),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _creating = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _creating = false); return; }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final name = userDoc.data()?['displayName'] as String? ?? 'Anonymous';

      await FirebaseFirestore.instance.collection('arcs').add({
        'name':        _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'emoji':       _selectedEmoji,
        'color':       _selectedColor,
        'tags':        _tags,
        'createdBy':   uid,
        'creatorName': name,
        'members':     [uid],
        'memberCount': 1,
        'postCount':   0,
        'createdAt':   FieldValue.serverTimestamp(),
      });

      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF110C08),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Create an Arc',
                    style: AppTheme.serif(
                        fontSize: 20, weight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded,
                      color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emoji picker
                  Text('Pick an emoji',
                      style: AppTheme.sans(
                          fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _emojis.map((e) => GestureDetector(
                      onTap: () => setState(() => _selectedEmoji = e),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: e == _selectedEmoji
                              ? AppTheme.primary.withValues(alpha: 0.2)
                              : AppTheme.surfaceLight,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: e == _selectedEmoji
                                ? AppTheme.primary
                                : AppTheme.border,
                          ),
                        ),
                        child: Center(child: Text(e,
                            style: const TextStyle(fontSize: 20))),
                      ),
                    )).toList(),
                  ),

                  const SizedBox(height: 20),

                  // Color picker
                  Text('Arc color',
                      style: AppTheme.sans(
                          fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: _colors.map((c) => GestureDetector(
                      onTap: () => setState(() => _selectedColor = c.$1),
                      child: Container(
                        width: 32, height: 32,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: c.$2,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedColor == c.$1
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    )).toList(),
                  ),

                  const SizedBox(height: 20),

                  // Name
                  Text('Arc name *',
                      style: AppTheme.sans(
                          fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    style: AppTheme.sans(fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'e.g. Attack on Titan Discussion',
                      hintStyle: AppTheme.sans(
                          color: AppTheme.textMuted, fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Description
                  Text('Description',
                      style: AppTheme.sans(
                          fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 3,
                    style: AppTheme.sans(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'What is this arc about?',
                      hintStyle: AppTheme.sans(
                          color: AppTheme.textMuted, fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Tags
                  Text('Tags',
                      style: AppTheme.sans(
                          fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagCtrl,
                          style: AppTheme.sans(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Add a tag...',
                            hintStyle: AppTheme.sans(
                                color: AppTheme.textMuted, fontSize: 14),
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              setState(() {
                                _tags.add(val.trim());
                                _tagCtrl.clear();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: _tags.map((t) => Chip(
                        label: Text('#$t'),
                        onDeleted: () => setState(() => _tags.remove(t)),
                        deleteIconColor: AppTheme.textMuted,
                      )).toList(),
                    ),
                  ],

                  const SizedBox(height: 32),

                  // Create button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _creating ? null : _create,
                      child: _creating
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Create Arc'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Create Post Sheet
// ─────────────────────────────────────────────────────────────

class _CreatePostSheet extends StatefulWidget {
  final String arcId;
  final String? uid;
  const _CreatePostSheet({required this.arcId, required this.uid});

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl  = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    if (_bodyCtrl.text.trim().isEmpty || widget.uid == null) return;
    setState(() => _posting = true);

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(widget.uid).get();
      final name = userDoc.data()?['displayName'] as String? ?? 'Anonymous';

      await FirebaseFirestore.instance
          .collection('arcs').doc(widget.arcId)
          .collection('posts').add({
        'title':      _titleCtrl.text.trim(),
        'body':       _bodyCtrl.text.trim(),
        'authorId':   widget.uid,
        'authorName': name,
        'likes':      [],
        'likeCount':  0,
        'replyCount': 0,
        'createdAt':  FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('arcs').doc(widget.arcId)
          .update({'postCount': FieldValue.increment(1)});

      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF110C08),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('New Discussion',
                style: AppTheme.serif(fontSize: 18, weight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              style: AppTheme.sans(fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Title (optional)',
                hintStyle: AppTheme.sans(color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              maxLines: 4,
              autofocus: true,
              style: AppTheme.sans(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'What\'s on your mind?',
                hintStyle: AppTheme.sans(color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _posting ? null : _post,
                child: _posting
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
