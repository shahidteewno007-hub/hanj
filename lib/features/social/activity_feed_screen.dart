import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';

class ActivityFeedScreen extends StatefulWidget {
  const ActivityFeedScreen({super.key});

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen>
    with SingleTickerProviderStateMixin {
  final _firestoreService = FirestoreService();
  late TabController _tabController;

  List<Map<String, dynamic>> _friendsActivity = [];
  bool _isLoadingFriends = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadFriendsActivity();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFriendsActivity() async {
    setState(() => _isLoadingFriends = true);
    try {
      final activity = await _firestoreService.getFriendsActivity();
      setState(() {
        _friendsActivity = activity;
        _isLoadingFriends = false;
      });
    } catch (e) {
      setState(() => _isLoadingFriends = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Feed'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'My Activity'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(),
          _buildMyActivityTab(),
        ],
      ),
    );
  }

  Widget _buildFriendsTab() {
    if (_isLoadingFriends) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_friendsActivity.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('👥', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 20),
            const Text(
              'No activity yet',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Follow friends to see what\nthey\'re watching',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadFriendsActivity,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFriendsActivity,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _friendsActivity.length,
        itemBuilder: (context, index) =>
            _ActivityCard(data: _friendsActivity[index]),
      ),
    );
  }

  Widget _buildMyActivityTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.getMyActivity(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: AppTheme.textMuted, size: 48),
                const SizedBox(height: 12),
                Text('Could not load activity',
                    style: AppTheme.sans(color: AppTheme.textSecondary)),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.history_rounded,
                    size: 56, color: AppTheme.textMuted),
                const SizedBox(height: 20),
                Text(
                  'No activity yet',
                  style: AppTheme.serif(
                      fontSize: 20,
                      weight: FontWeight.bold,
                      color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start adding anime to your list\nto see your activity here',
                  textAlign: TextAlign.center,
                  style: AppTheme.sans(
                      color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _ActivityCard(data: data, showUser: false);
          },
        );
      },
    );
  }
}

class _ActivityCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool showUser;

  const _ActivityCard({required this.data, this.showUser = true});

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String? ?? '';
    final title = data['animeTitle'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String?;
    final displayName = data['displayName'] as String? ?? 'Someone';
    final rating = (data['rating'] as num?)?.toDouble();
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          // Anime poster
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 52,
                    height: 72,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholderPoster(),
                  )
                : _placeholderPoster(),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action line
                RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14, height: 1.4),
                    children: [
                      if (showUser)
                        TextSpan(
                          text: '$displayName ',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      TextSpan(
                        text: _getActionText(type),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7)),
                      ),
                      TextSpan(
                        text: ' $title',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Type badge + rating
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _getTypeColor(type).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                _getTypeColor(type).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_getTypeEmoji(type),
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 4),
                          Text(
                            _getTypeLabel(type),
                            style: TextStyle(
                              color: _getTypeColor(type),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (rating != null) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.star_rounded,
                          color: Colors.amber, size: 13),
                      const SizedBox(width: 2),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                    const Spacer(),
                    if (createdAt != null)
                      Text(
                        _formatTime(createdAt),
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.4),
                            fontSize: 11),
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

  Widget _placeholderPoster() => Container(
        width: 52,
        height: 72,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.movie_outlined,
            color: AppTheme.textMuted, size: 20),
      );

  String _getActionText(String type) {
    switch (type) {
      case 'WATCHING':
        return 'started watching';
      case 'COMPLETED':
        return 'completed';
      case 'PLAN_TO_WATCH':
        return 'added to watchlist:';
      case 'DROPPED':
        return 'dropped';
      case 'RATED':
        return 'rated';
      default:
        return 'added';
    }
  }

  String _getTypeEmoji(String type) {
    switch (type) {
      case 'WATCHING':      return '👀';
      case 'COMPLETED':     return '✅';
      case 'PLAN_TO_WATCH': return '📌';
      case 'DROPPED':       return '❌';
      case 'RATED':         return '⭐';
      default:              return '📋';
    }
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'WATCHING':      return 'Watching';
      case 'COMPLETED':     return 'Completed';
      case 'PLAN_TO_WATCH': return 'Plan to Watch';
      case 'DROPPED':       return 'Dropped';
      case 'RATED':         return 'Rated';
      default:              return 'Added';
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'WATCHING':      return AppTheme.watching;
      case 'COMPLETED':     return AppTheme.success;
      case 'PLAN_TO_WATCH': return AppTheme.warning;
      case 'DROPPED':       return AppTheme.error;
      case 'RATED':         return Colors.amber;
      default:              return AppTheme.primary;
    }
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
