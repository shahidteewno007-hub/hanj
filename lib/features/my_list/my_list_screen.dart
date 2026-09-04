import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';
import '../anime_detail/anime_detail_screen.dart';
import '../../models/anime_model.dart';

class MyListScreen extends StatefulWidget {
  final String? initialStatus;
  const MyListScreen({super.key, this.initialStatus});

  @override
  State<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends State<MyListScreen> {
  final _firestoreService = FirestoreService();
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedStatus = 'ALL';
  String _sortBy = 'recent';

  @override
  void initState() {
    super.initState();
    if (widget.initialStatus != null) {
      _selectedStatus = widget.initialStatus!;
    }
  }

  final _statuses = ['ALL', 'WATCHING', 'COMPLETED', 'PLAN_TO_WATCH', 'DROPPED'];
  final _statusLabels = {
    'ALL': 'All',
    'WATCHING': 'Watching',
    'COMPLETED': 'Completed',
    'PLAN_TO_WATCH': 'Plan',
    'DROPPED': 'Dropped',
  };

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatWatchTime(int totalEpisodes) {
    final minutes = totalEpisodes * 24;
    final days = minutes ~/ (60 * 24);
    final hours = (minutes % (60 * 24)) ~/ 60;
    if (days > 0) return '${days}D ${hours}H';
    return '${hours}H';
  }

  List<QueryDocumentSnapshot> _filterAndSort(
      List<QueryDocumentSnapshot> docs) {
    var filtered = docs;

    if (_selectedStatus != 'ALL') {
      filtered = filtered
          .where((d) =>
              (d.data() as Map)['status'] == _selectedStatus)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((d) {
        final title =
            ((d.data() as Map)['title'] as String? ?? '').toLowerCase();
        return title.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    filtered.sort((a, b) {
      final da = a.data() as Map<String, dynamic>;
      final db = b.data() as Map<String, dynamic>;
      switch (_sortBy) {
        case 'title':
          return (da['title'] as String? ?? '')
              .compareTo(db['title'] as String? ?? '');
        case 'rating':
          final rA = (da['userRating'] as num?)?.toDouble() ?? 0.0;
          final rB = (db['userRating'] as num?)?.toDouble() ?? 0.0;
          return rB.compareTo(rA);
        default:
          final tA = da['addedAt'] as Timestamp?;
          final tB = db['addedAt'] as Timestamp?;
          if (tA == null || tB == null) return 0;
          return tB.compareTo(tA);
      }
    });

    return filtered;
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sort by',
                style: AppTheme.serif(fontSize: 18, weight: FontWeight.w600)),
            const SizedBox(height: 16),
            for (final option in [
              ('recent', 'Recently Added'),
              ('title', 'Title A–Z'),
              ('rating', 'My Rating'),
            ])
              ListTile(
                title: Text(option.$2,
                    style: AppTheme.sans(
                        fontSize: 15,
                        color: _sortBy == option.$1
                            ? AppTheme.primary
                            : AppTheme.textPrimary)),
                trailing: _sortBy == option.$1
                    ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                    : null,
                onTap: () {
                  setState(() => _sortBy = option.$1);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestoreService.getAnimeList(),
        builder: (context, snapshot) {
          final allDocs = snapshot.data?.docs ?? [];
          final filtered = _filterAndSort(allDocs);

          // Count per status
          final counts = <String, int>{'ALL': allDocs.length};
          for (final s in _statuses.skip(1)) {
            counts[s] = allDocs
                .where((d) => (d.data() as Map)['status'] == s)
                .length;
          }

          // Total watch time
          int totalEps = 0;
          for (final d in allDocs) {
            final data = d.data() as Map<String, dynamic>;
            if (data['status'] == 'COMPLETED') {
              totalEps += (data['episodes'] as int?) ?? 0;
            } else {
              totalEps += (data['currentEpisode'] as int?) ?? 0;
            }
          }

          return CustomScrollView(
            slivers: [
              // ── Header ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 4, 20, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('My List',
                                style: AppTheme.serif(
                                    fontSize: 28,
                                    weight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              '${allDocs.length} TITLES · ${_formatWatchTime(totalEps)}',
                              style: AppTheme.mono(
                                  fontSize: 11,
                                  color: AppTheme.textMuted,
                                  letterSpacing: 0.8),
                            ),
                          ],
                        ),
                      ),
                      // Sort button
                      GestureDetector(
                        onTap: _showSortSheet,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Icon(Icons.swap_vert_rounded,
                              color: AppTheme.textSecondary, size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Random pick button
                      GestureDetector(
                        onTap: () {
                          final allDocs = snapshot.data?.docs ?? [];
                          if (allDocs.isEmpty) return;
                          final random = allDocs[DateTime.now().millisecondsSinceEpoch % allDocs.length];
                          final data = random.data() as Map<String, dynamic>;
                          final anime = Anime(
                            id: data['animeId']?.toString() ?? '',
                            title: data['title'] as String? ?? '',
                            imageUrl: data['imageUrl'] as String?,
                            averageScore: (data['averageScore'] as num?)?.toDouble(),
                            episodes: data['episodes'] as int?,
                            genres: (data['genres'] as List<dynamic>?)?.cast<String>() ?? [],
                            status: data['status'] as String?,
                          );
                          Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AnimeDetailScreen(anime: anime),
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Icon(Icons.shuffle_rounded,
                              color: AppTheme.textSecondary, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Search ────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: AppTheme.sans(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search your list...',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppTheme.textMuted, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  color: AppTheme.textMuted, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              // ── Status filter tabs ─────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: _statuses.map((s) {
                        final selected = _selectedStatus == s;
                        final count = counts[s] ?? 0;
                        return MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedStatus = s),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.textPrimary
                                    : AppTheme.surfaceLight,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.textPrimary
                                      : AppTheme.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    _statusLabels[s] ?? s,
                                    style: AppTheme.sans(
                                      fontSize: 13,
                                      weight: FontWeight.w600,
                                      color: selected
                                          ? AppTheme.textInverse
                                          : AppTheme.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: selected
                                          ? AppTheme.textInverse
                                              .withValues(alpha: 0.15)
                                          : AppTheme.surfaceMid,
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: AppTheme.mono(
                                        fontSize: 10,
                                        weight: FontWeight.w600,
                                        color: selected
                                            ? AppTheme.textInverse
                                            : AppTheme.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),

              // ── List ──────────────────────────────────────
              snapshot.connectionState == ConnectionState.waiting
                  ? const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primary, strokeWidth: 1.5),
                      ),
                    )
                  : filtered.isEmpty
                      ? SliverFillRemaining(
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('📭',
                                    style: TextStyle(fontSize: 48)),
                                const SizedBox(height: 16),
                                Text('Nothing here',
                                    style: AppTheme.serif(
                                        fontSize: 20,
                                        weight: FontWeight.w600)),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'No results for "$_searchQuery"'
                                      : 'Add some anime to get started',
                                  style: AppTheme.sans(
                                      fontSize: 14,
                                      color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index == 0) {
                                return const SizedBox(height: 16);
                              }
                              final i = index - 1;
                              if (i >= filtered.length) return null;
                              final data = filtered[i].data()
                                  as Map<String, dynamic>;
                              return _ListRow(
                                key: ValueKey(data['animeId']),
                                data: data,
                                firestoreService: _firestoreService,
                              );
                            },
                            childCount: filtered.length + 1,
                          ),
                        ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          );
        },
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final FirestoreService firestoreService;

  const _ListRow({super.key, required this.data, required this.firestoreService});

  Color _statusColor(String s) {
    switch (s) {
      case 'WATCHING':      return AppTheme.watching;
      case 'COMPLETED':     return AppTheme.completed;
      case 'PLAN_TO_WATCH': return AppTheme.planToWatch;
      case 'DROPPED':       return AppTheme.dropped;
      default:              return AppTheme.textMuted;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'WATCHING':      return 'WATCHING';
      case 'COMPLETED':     return 'COMPLETED';
      case 'PLAN_TO_WATCH': return 'PLAN';
      case 'DROPPED':       return 'DROPPED';
      default:              return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String?;
    final status = data['status'] as String? ?? '';
    final current = (data['currentEpisode'] as int?) ?? 0;
    final total = data['episodes'] as int?;
    final userRating = (data['userRating'] as num?)?.toDouble();
    final genres = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final animeId =
        int.tryParse(data['animeId']?.toString() ?? '0') ?? 0;
    final progress = total != null && total > 0
        ? (current / total).clamp(0.0, 1.0)
        : 0.0;
    final statusColor = _statusColor(status);

    return Dismissible(
      key: ValueKey(animeId),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        decoration: BoxDecoration(
          color: AppTheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_rounded,
            color: Colors.white, size: 24),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.surfaceMid,
            title: Text('Remove from list',
                style: AppTheme.serif(
                    fontSize: 18, weight: FontWeight.w600)),
            content: Text('Remove "$title" from your list?',
                style: AppTheme.sans(
                    fontSize: 14, color: AppTheme.textSecondary)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: AppTheme.sans(color: AppTheme.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Remove',
                    style: AppTheme.sans(color: AppTheme.error)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => firestoreService.removeAnimeFromList(animeId),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            final anime = Anime(
              id: data['animeId']?.toString() ?? '',
              title: title,
              imageUrl: imageUrl,
              episodes: total,
              genres: genres,
              averageScore:
                  (data['averageScore'] as num?)?.toDouble(),
            );
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AnimeDetailScreen(anime: anime)),
            );
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                // Poster
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 72,
                    height: 96,
                    child: imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                Container(color: AppTheme.surfaceMid),
                          )
                        : Container(color: AppTheme.surfaceMid),
                  ),
                ),
                const SizedBox(width: 14),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        title,
                        style: AppTheme.sans(
                            fontSize: 15, weight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      // Genre · Season · Episodes
                      Text(
                        [
                          if (genres.isNotEmpty)
                            genres.first.toUpperCase(),
                          if (total != null) '$total EP',
                        ].join(' · '),
                        style: AppTheme.mono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                            letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      // Status badge
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color:
                                      statusColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              _statusLabel(status),
                              style: AppTheme.mono(
                                  fontSize: 9,
                                  weight: FontWeight.w600,
                                  color: statusColor,
                                  letterSpacing: 0.8),
                            ),
                          ),
                          if (userRating != null) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.star_rounded,
                                color: AppTheme.accent, size: 12),
                            const SizedBox(width: 2),
                            Text(
                              userRating.toStringAsFixed(1),
                              style: AppTheme.mono(
                                  fontSize: 10,
                                  color: AppTheme.accent,
                                  weight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                      // Progress bar (watching only)
                      if (status == 'WATCHING' && total != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  backgroundColor: AppTheme.border,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                          statusColor),
                                  minHeight: 3,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$current/$total',
                              style: AppTheme.mono(
                                  fontSize: 10,
                                  color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.textMuted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
