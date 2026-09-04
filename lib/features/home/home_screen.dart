import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../core/theme/app_theme.dart';
import '../../services/anilist_service.dart';
import '../../services/firestore_service.dart';
import '../../services/offline_cache_service.dart';
import '../../services/connectivity_service.dart';
import '../../models/anime_model.dart';
import '../anime_detail/anime_detail_screen.dart';
import 'tonight_watch.dart';
import 'upcoming_anime.dart';
import '../calendar/anime_calendar_screen.dart';
import '../discovery/discovery_screen.dart';
import '../my_list/my_list_screen.dart';
import '../import/anilist_import_screen.dart';
import '../search/search_screen.dart';
import '../companion/tomo_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _aniListService = AnilistService();
  final _firestoreService = FirestoreService();

  List<Anime> _trendingAnime = [];
  List<Map<String, dynamic>> _continueWatching = [];
  List<Map<String, dynamic>> _planToWatch = [];
  Set<String> _reminderIds = {}; // persisted reminder animeIds
  Anime? _animeOfDay;
  List<Map<String, dynamic>> _recommendationRows = [];
  bool _isLoading = true;
  bool _isFromCache = false;
  bool _importPending = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final isOnline = ConnectivityService.instance.isOnline;

    try {
      // Trending — always uses cache fallback automatically via OfflineCacheService
      final trending = await OfflineCacheService.instance.getTrending();

      // Firestore — has built-in offline persistence, so these still work offline
      final results = await Future.wait([
        _firestoreService.getAnimeByStatus('WATCHING').first,
        _firestoreService.getAnimeList().first,
      ]);

      final importPending = await _firestoreService.getImportPending();

      if (!mounted) return;

      final watchingSnapshot = results[0];
      final allWatching = watchingSnapshot.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .where((d) => d['animeId'] != null)
          .toList();

      // ── Auto-complete already-finished anime ──────────────────
      // Anything where currentEpisode has reached the total (e.g. a
      // 1-episode movie added at 1/1, or anything finished outside the
      // tap-to-increment flow) should be COMPLETED and drop out of
      // Continue arc. Heal Firestore in the background.
      final List<Map<String, dynamic>> continueWatching = [];
      final uidForHeal = FirebaseAuth.instance.currentUser?.uid;
      for (final d in allWatching) {
        final cur   = (d['currentEpisode'] as int?) ?? 0;
        final total = (d['episodes'] as int?) ?? 0;
        final finished = total > 0 && cur >= total;
        if (finished) {
          // Heal status → COMPLETED (fire-and-forget, don't block load)
          final id = d['animeId']?.toString();
          if (uidForHeal != null && id != null) {
            FirebaseFirestore.instance
                .collection('users').doc(uidForHeal)
                .collection('animeList').doc(id)
                .update({'status': 'COMPLETED'})
                .catchError((_) {});
          }
          continue; // exclude from Continue arc
        }
        continueWatching.add(d);
      }

      continueWatching.sort((a, b) {
        final aTime = a['lastWatched'] as Timestamp?;
        final bTime = b['lastWatched'] as Timestamp?;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      Anime? animeOfDay;
      if (trending.isNotEmpty) {
        final dayOfYear = DateTime.now()
            .difference(DateTime(DateTime.now().year, 1, 1))
            .inDays;
        animeOfDay = trending[dayOfYear % trending.length];
      }

      final userSnapshot = results[1];

      // ── Plan to Watch ──────────────────────────────────────
      final allDocs = userSnapshot.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .where((d) => d['animeId'] != null && d['status'] == 'PLAN_TO_WATCH')
          .toList();
      // Sort by most recently added
      allDocs.sort((a, b) {
        final aTime = a['addedAt'] as Timestamp?;
        final bTime = b['addedAt'] as Timestamp?;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      // Load reminders
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          final remSnap = await FirebaseFirestore.instance
              .collection('users').doc(uid)
              .collection('alerts')
              .get();
          _reminderIds = remSnap.docs.map((d) => d.id).toSet();
        } catch (_) {}
      }

      if (!mounted) return;
      // ── Render immediately with cached + Firestore data ──────────
      // Recommendations are fetched separately so a throttled AniList
      // call never blocks the whole screen from showing.
      setState(() {
        _trendingAnime = trending;
        _continueWatching = continueWatching;
        _planToWatch = allDocs;
        _animeOfDay = animeOfDay;
        _isLoading = false;
        _isFromCache = !isOnline;
        _importPending = importPending;
      });

      // Fire recommendations in the background (non-blocking)
      if (isOnline && userSnapshot.docs.isNotEmpty) {
        _loadRecommendations(userSnapshot);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isFromCache = !isOnline;
      });
    }
  }

  /// Fetches recommendation rows after the screen has already rendered,
  /// so the throttled AniList call never delays first paint.
  Future<void> _loadRecommendations(dynamic userSnapshot) async {
    final userAnimeIds = userSnapshot.docs
        .map((d) => (d.data() as Map)['animeId'].toString())
        .toSet();
    final seedDocs = userSnapshot.docs
        .map((d) => d.data() as Map<String, dynamic>)
        .where((d) =>
            (d['status'] == 'COMPLETED' || d['status'] == 'WATCHING') &&
            (d['genres'] as List?)?.isNotEmpty == true)
        .take(1)
        .toList();

    final List<Map<String, dynamic>> rows = [];
    for (final seed in seedDocs) {
      final genres = (seed['genres'] as List).cast<String>();
      final sourceTitle = seed['title'] as String? ?? 'your list';
      try {
        final recs = await _aniListService.searchAnime(
            '', genre: genres.first, sort: 'SCORE_DESC');
        final filtered =
            recs.where((a) => !userAnimeIds.contains(a.id)).take(10).toList();
        if (filtered.isNotEmpty) {
          rows.add({
            'genre': genres.first,
            'sourceTitle': sourceTitle,
            'anime': filtered,
          });
        }
      } catch (_) {}
    }

    if (mounted && rows.isNotEmpty) {
      setState(() => _recommendationRows = rows);
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'GOOD MORNING';
    if (hour < 17) return 'GOOD AFTERNOON';
    if (hour < 21) return 'GOOD EVENING';
    return 'GOOD NIGHT';
  }

  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'MORNING';
    if (hour < 17) return 'AFTERNOON';
    if (hour < 21) return 'EVENING';
    return 'NIGHT';
  }

  String _getTodayLabel() {
    return DateFormat('EEEE · MMM d').format(DateTime.now()).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.primary,
            strokeWidth: 1.5,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppTheme.primary,
        backgroundColor: AppTheme.surfaceMid,
        child: CustomScrollView(
          slivers: [
            // ── Header ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Greeting row with search icon
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '${_getGreeting()} · ${_getTodayLabel()}',
                          style: AppTheme.mono(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                              letterSpacing: 1.2),
                        ),
                        Row(
                          children: [
                            // Tomo — AI anime companion
                            GestureDetector(
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(
                                      builder: (_) => const TomoScreen())),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFF97316), Color(0xFFE8624A)],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFF97316).withValues(alpha: 0.4),
                                      blurRadius: 10,
                                      spreadRadius: -2,
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  '友',
                                  style: TextStyle(
                                    color: Color(0xFF0A0A0A),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            GestureDetector(
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(
                                      builder: (_) => const SearchScreen())),
                              child: const Icon(Icons.search_rounded,
                                  color: AppTheme.textSecondary, size: 22),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Dynamic headline
                    _buildHeadline(),
                  ],
                ),
              ),
            ),

            // ── Import Pending Banner ────────────────────────
            if (_importPending)
              SliverToBoxAdapter(
                child: _ImportPendingBanner(
                  onDismiss: () async {
                    await _firestoreService.dismissImportBanner();
                    if (mounted) setState(() => _importPending = false);
                  },
                ),
              ),

            // ── Tonight's Drop / Anime of Day ────────────────
            if (_animeOfDay != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: _TonightCard(anime: _animeOfDay!),
                ),
              ),

            // ── Tonight's Watch ──────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(0, 16, 0, 0),
                child: TonightWatchCard(),
              ),
            ),

            // ── Continue Watching ────────────────────────────
            if (_continueWatching.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Continue arc',
                          style: AppTheme.serif(
                              fontSize: 20, weight: FontWeight.w600)),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const MyListScreen(initialStatus: 'WATCHING'))),
                          child: Text(
                            'SEE ALL →',
                            style: AppTheme.mono(
                                fontSize: 11,
                                color: AppTheme.primary,
                                letterSpacing: 1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 310,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _continueWatching.length,
                    itemBuilder: (context, index) => _ContinueCard(
                      data: _continueWatching[index],
                      firestoreService: _firestoreService,
                      onUpdated: _loadData,
                    ),
                  ),
                ),
              ),
            ],

            // ── Plan to Watch ────────────────────────────────
            if (_planToWatch.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Up next',
                          style: AppTheme.serif(
                              fontSize: 20, weight: FontWeight.w600)),
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(
                                  builder: (_) => const MyListScreen(initialStatus: 'PLAN_TO_WATCH'))),
                          child: Text(
                            'SEE ALL →',
                            style: AppTheme.mono(
                                fontSize: 11,
                                color: AppTheme.primary,
                                letterSpacing: 1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 260,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _planToWatch.length,
                    itemBuilder: (context, index) => _PlanCard(
                      data: _planToWatch[index],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],

            // ── Trending ─────────────────────────────────────
            if (_trendingAnime.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_fire_department_rounded,
                              color: AppTheme.primary, size: 16),
                          const SizedBox(width: 8),
                          Text('Trending this week',
                              style: AppTheme.serif(
                                  fontSize: 20, weight: FontWeight.w600)),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const DiscoveryScreen(initialTab: 'TRENDING'))),
                        child: Text('MORE →',
                            style: AppTheme.mono(
                                fontSize: 11,
                                color: AppTheme.primary,
                                letterSpacing: 1)),
                      ),
                    ],
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= _trendingAnime.length) return null;
                    return _TrendingRow(
                      anime: _trendingAnime[index],
                      rank: index + 1,
                    );
                  },
                  childCount: _trendingAnime.length.clamp(0, 10),
                ),
              ),
            ],

            // ── Coming Up ─────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 32, 20, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            color: AppTheme.textMuted, size: 14),
                        const SizedBox(width: 8),
                        Text('Coming up',
                            style: AppTheme.serif(
                                fontSize: 20, weight: FontWeight.w600)),
                      ],
                    ),
                    InkWell(
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const AnimeCalendarScreen())),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Text('CALENDAR →',
                            style: AppTheme.mono(
                                fontSize: 11,
                                color: AppTheme.primary,
                                letterSpacing: 1)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: _ComingUpSection(
                    continueWatching: _continueWatching,
                    reminderIds: _reminderIds,
                    onToggleReminder: (animeId, val) {
                      setState(() {
                        if (val) {
                          _reminderIds.add(animeId);
                        } else {
                          _reminderIds.remove(animeId);
                        }
                      });
                    }),
              ),
            ),

            // ── Recommendations ──────────────────────────────
            for (final row in _recommendationRows) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 44, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BECAUSE YOU LOVED',
                        style: AppTheme.mono(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                            letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        row['sourceTitle'] as String,
                        style: AppTheme.serif(
                            fontSize: 20, weight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 260,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    physics: const BouncingScrollPhysics(),
                    itemCount: (row['anime'] as List<Anime>).length,
                    itemBuilder: (context, index) => _TrendingCard(
                      anime: (row['anime'] as List<Anime>)[index],
                      rank: index + 1,
                    ),
                  ),
                ),
              ),
            ],

            // ── Upcoming This Season ─────────────────────────
            // Keyed on purpose. The recommendation slivers above are inserted
            // later, when _loadRecommendations finishes. Without a key, the
            // sliver list is matched positionally — every entry is an unkeyed
            // SliverToBoxAdapter, so canUpdate() returns true — and this
            // sliver's element gets handed a recommendation row instead,
            // unmounting UpcomingAnimeRow and remounting it further down. That
            // cost a second identical AniList request on every Home load.
            const SliverToBoxAdapter(
              key: ValueKey('upcoming-this-season'),
              child: Padding(
                padding: EdgeInsets.only(top: 24),
                child: UpcomingAnimeRow(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeadline() {
    final count = _continueWatching.length;
    if (count == 0) {
      return RichText(
        text: TextSpan(
          style: AppTheme.serif(fontSize: 28, weight: FontWeight.w700, height: 1.2),
          children: [
            const TextSpan(text: 'Discover something\n'),
            TextSpan(
              text: 'new tonight.',
              style: AppTheme.serif(
                  fontSize: 28,
                  weight: FontWeight.w700,
                  color: AppTheme.primary,
                  style: FontStyle.italic),
            ),
          ],
        ),
      );
    }
    return RichText(
      text: TextSpan(
        text: '$count new episode${count > 1 ? 's' : ''} aired\ntonight.',
        style: AppTheme.serif(
            fontSize: 28,
            weight: FontWeight.w700,
            height: 1.2,
            color: AppTheme.textPrimary),
      ),
    );
  }
}

// ── Quick Add Sheet ──────────────────────────────────────────
Future<String?> _showQuickAddSheet(BuildContext context, Anime anime) {
  return showHanjListSheet(context: context, anime: anime);
}

// ── Unified Hanj List Sheet — used by home + anime detail ───
Future<String?> showHanjListSheet({
  required BuildContext context,
  required Anime anime,
  String? currentStatus,
}) {
  final firestoreService = FirestoreService();

  const statuses = [
    ('WATCHING',      'Watching',      Icons.play_circle_rounded,  Color(0xFFE8624A)),
    ('PLAN_TO_WATCH', 'Plan to Watch', Icons.bookmark_rounded,      Color(0xFF5B8DEF)),
    ('COMPLETED',     'Completed',     Icons.check_circle_rounded,  Color(0xFF4CAF7D)),
    ('DROPPED',       'Dropped',       Icons.cancel_rounded,        Color(0xFFEF5B5B)),
  ];

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      String? selected = currentStatus;

      return StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF13100D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                anime.titleEnglish ?? anime.title,
                style: AppTheme.serif(fontSize: 18, weight: FontWeight.w700, color: AppTheme.textPrimary),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Where does this one live?',
                style: AppTheme.sans(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 24),
              // 2×2 grid
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.4,
                children: statuses.map((s) {
                  final isSelected = selected == s.$1;
                  return GestureDetector(
                    onTap: () async {
                      // 1. Highlight immediately
                      setLocal(() => selected = s.$1);
                      // 2. Close sheet and return result
                      await Future.delayed(const Duration(milliseconds: 180));
                      Navigator.pop(ctx, s.$1);
                      // 3. Save to Firestore (fire and forget — UI already updated)
                      firestoreService.addAnimeToList(anime: anime, status: s.$1);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? s.$4.withValues(alpha: 0.22)
                            : s.$4.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? s.$4 : s.$4.withValues(alpha: 0.3),
                          width: isSelected ? 2 : 1,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(
                                color: s.$4.withValues(alpha: 0.45),
                                blurRadius: 12,
                                spreadRadius: 0,
                              )]
                            : [],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(s.$3,
                              color: isSelected ? s.$4 : s.$4.withValues(alpha: 0.6),
                              size: 17),
                          const SizedBox(width: 8),
                          Text(
                            s.$2,
                            style: AppTheme.sans(
                              fontSize: 13,
                              weight: FontWeight.w600,
                              color: isSelected ? s.$4 : s.$4.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (currentStatus != null) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx, '__REMOVE__'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      'Remove from list',
                      textAlign: TextAlign.center,
                      style: AppTheme.sans(fontSize: 13, color: AppTheme.textMuted),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

// ── Import Pending Banner ─────────────────────────────────────
class _ImportPendingBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _ImportPendingBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1508),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.download_rounded,
                  color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Finish your import',
                    style: AppTheme.sans(
                        fontSize: 13,
                        weight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your AniList/MAL import is pending. We\'ll notify you when it\'s ready.',
                    style: AppTheme.sans(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AnilistImportScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Go →',
                      style: AppTheme.sans(
                          fontSize: 11,
                          weight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onDismiss,
                  child: Text(
                    'Dismiss',
                    style: AppTheme.sans(
                        fontSize: 10, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tonight's Drop Card ──────────────────────────────────────
class _TonightCard extends StatefulWidget {
  final Anime anime;
  const _TonightCard({required this.anime});

  @override
  State<_TonightCard> createState() => _TonightCardState();
}

class _TonightCardState extends State<_TonightCard>
    with SingleTickerProviderStateMixin {
  String? _savedStatus; // null = not saved
  late AnimationController _bookmarkCtrl;
  late Animation<double> _bookmarkScale;

  // Maps status → icon + color for the bookmark button
  static const _statusMeta = {
    'WATCHING':     (Icons.play_circle_rounded,     AppTheme.primary),
    'PLAN_TO_WATCH':(Icons.bookmark_rounded,         Colors.blueAccent),
    'COMPLETED':    (Icons.check_circle_rounded,     Colors.green),
    'DROPPED':      (Icons.cancel_rounded,           Colors.redAccent),
  };

  @override
  void initState() {
    super.initState();
    _bookmarkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _bookmarkScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _bookmarkCtrl, curve: Curves.easeOut));
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('animeList').doc(widget.anime.id)
        .get();
    if (mounted && doc.exists) {
      setState(() => _savedStatus = doc.data()?['status'] as String?);
    }
  }

  @override
  void dispose() {
    _bookmarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _onBookmarkTap() async {
    final status = await _showQuickAddSheet(context, widget.anime);
    if (status != null && mounted) {
      setState(() => _savedStatus = status);
      _bookmarkCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = _savedStatus != null;
    final meta = isSaved ? _statusMeta[_savedStatus] : null;
    final bookmarkIcon = meta?.$1 ?? Icons.bookmark_border_rounded;
    final bookmarkColor = meta?.$2 ?? AppTheme.textSecondary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: widget.anime))),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              // Poster
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                ),
                child: SizedBox(
                  width: 140,
                  height: 200,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.anime.imageUrl != null)
                        CachedNetworkImage(
                          imageUrl: widget.anime.imageUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              Container(color: AppTheme.surfaceMid),
                        )
                      else
                        Container(color: AppTheme.surfaceMid),
                      // Genre badge
                      if (widget.anime.genres.isNotEmpty)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: _Badge(widget.anime.genres.first.toUpperCase()),
                        ),
                      // Title overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.8),
                              ],
                            ),
                          ),
                          child: Text(
                            widget.anime.titleEnglish ?? widget.anime.title,
                            style: AppTheme.sans(
                                fontSize: 12,
                                weight: FontWeight.w600,
                                color: Colors.white),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "TONIGHT'S DROP",
                        style: AppTheme.mono(
                            fontSize: 10,
                            color: AppTheme.primary,
                            letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.anime.titleEnglish ?? widget.anime.title,
                        style: AppTheme.serif(
                            fontSize: 16,
                            weight: FontWeight.w600,
                            height: 1.3),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (widget.anime.averageScore != null) ...[
                            const Icon(Icons.star_rounded,
                                color: AppTheme.primary, size: 13),
                            const SizedBox(width: 3),
                            Text(
                              (widget.anime.averageScore! / 10).toStringAsFixed(1),
                              style: AppTheme.sans(
                                  fontSize: 12,
                                  weight: FontWeight.w600,
                                  color: AppTheme.primary),
                            ),
                            Text(' · ',
                                style: AppTheme.sans(
                                    color: AppTheme.textMuted, fontSize: 12)),
                          ],
                          if (widget.anime.genres.isNotEmpty)
                            Flexible(
                              child: Text(
                                widget.anime.genres.first,
                                style: AppTheme.sans(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Action buttons
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Container(
                            padding: const EdgeInsets.only(
                                left: 10, right: 14, top: 10, bottom: 10),
                            decoration: BoxDecoration(
                              color: AppTheme.textPrimary,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow_rounded,
                                    color: AppTheme.textInverse, size: 16),
                                const SizedBox(width: 5),
                                Text(
                                  'Continue',
                                  style: AppTheme.sans(
                                      fontSize: 13,
                                      weight: FontWeight.w600,
                                      color: AppTheme.textInverse),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _onBookmarkTap,
                            child: ScaleTransition(
                              scale: _bookmarkScale,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: isSaved
                                      ? bookmarkColor.withValues(alpha: 0.15)
                                      : AppTheme.surfaceMid,
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(
                                    color: isSaved ? bookmarkColor : AppTheme.border,
                                  ),
                                ),
                                child: Icon(
                                  bookmarkIcon,
                                  color: isSaved ? bookmarkColor : AppTheme.textSecondary,
                                  size: 16,
                                ),
                              ),
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
        ),
      ),
    );
  }
}

// ── Continue Watching Card ───────────────────────────────────
class _ContinueCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final FirestoreService firestoreService;
  final VoidCallback onUpdated;

  const _ContinueCard({
    required this.data,
    required this.firestoreService,
    required this.onUpdated,
  });

  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  late int _current;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _current = (widget.data['currentEpisode'] as int?) ?? 0;
  }

  @override
  void didUpdateWidget(_ContinueCard old) {
    super.didUpdateWidget(old);
    // Sync if the parent reloaded with a different value (e.g. set on detail screen).
    final incoming = (widget.data['currentEpisode'] as int?) ?? 0;
    final previous = (old.data['currentEpisode'] as int?) ?? 0;
    if (incoming != previous) {
      _current = incoming;
    }
  }

  Future<void> _bump(int total) async {
    final next = total > 0 ? (_current + 1).clamp(0, total) : _current + 1;
    if (next == _current) return; // already at the cap

    // Optimistic: update UI instantly.
    setState(() {
      _current = next;
      _saving = true;
    });

    final animeId = widget.data['animeId']?.toString() ?? '';
    if (animeId.isEmpty) {
      setState(() => _saving = false);
      return;
    }

    // Write in the background — no full refetch, so no stutter.
    try {
      await widget.firestoreService
          .updateEpisodeProgress(int.parse(animeId), next);
      // Keep the parent's cached map in sync without triggering a reload.
      widget.data['currentEpisode'] = next;

      // ── Auto-complete ────────────────────────────────────────
      // If the user just watched the final episode, flip status to
      // COMPLETED and remove the card from the Continue arc.
      if (total > 0 && next >= total) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('animeList')
              .doc(animeId)
              .update({'status': 'COMPLETED'});
        }
        widget.data['status'] = 'COMPLETED';
        // onUpdated triggers _loadData() in HomeScreen, which re-queries
        // getAnimeByStatus('WATCHING') — COMPLETED entries won't appear.
        widget.onUpdated();
      }
    } catch (_) {
      // Revert on failure.
      if (mounted) setState(() => _current = next - 1);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final title = data['title'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final total = data['episodes'] as int?;
    final animeId = data['animeId']?.toString() ?? '';
    final genres = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final hasTotal = total != null && total > 0;
    final progress = hasTotal ? (_current / total).clamp(0.0, 1.0) : 0.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final anime = Anime(
            id: animeId,
            title: title,
            imageUrl: imageUrl,
            episodes: total,
            genres: genres,
          );
          Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => AnimeDetailScreen(anime: anime)));
        },
        child: Container(
          width: 140,
          margin: const EdgeInsets.only(right: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster with episode badge
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 140,
                      height: 196,
                      child: imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  Container(color: AppTheme.surfaceLight),
                            )
                          : Container(color: AppTheme.surfaceLight),
                    ),
                  ),
                  // Episode badge — animated, display only (set on detail screen)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppTheme.background.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, -0.4),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: Text(
                          'EP $_current',
                          key: ValueKey(_current),
                          style: AppTheme.sans(
                              fontSize: 10,
                              weight: FontWeight.w700,
                              color: AppTheme.textPrimary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Progress bar — animates smoothly between values
              if (hasTotal)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: progress, end: progress),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (_, value, _) => LinearProgressIndicator(
                      value: value,
                      backgroundColor: AppTheme.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppTheme.primary),
                      minHeight: 2,
                    ),
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                title,
                style: AppTheme.sans(
                    fontSize: 12,
                    weight: FontWeight.w500,
                    color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                hasTotal ? 'EP $_current OF $total' : 'EP $_current',
                style: AppTheme.mono(fontSize: 10, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 6),
              // +1 episode button — optimistic, no full reload
              GestureDetector(
                onTap: animeId.isEmpty ? null : () => _bump(total ?? 0),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _saving
                        ? AppTheme.primary.withValues(alpha: 0.18)
                        : AppTheme.surfaceMid,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _saving ? AppTheme.primary : AppTheme.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('+1 episode',
                          style: AppTheme.mono(
                              fontSize: 10,
                              color: _saving
                                  ? AppTheme.primary
                                  : AppTheme.textMuted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Trending Card ────────────────────────────────────────────
class _TrendingCard extends StatefulWidget {
  final Anime anime;
  final int? rank;
  const _TrendingCard({required this.anime, this.rank});

  @override
  State<_TrendingCard> createState() => _TrendingCardState();
}

class _TrendingCardState extends State<_TrendingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AnimeDetailScreen(anime: widget.anime)),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 140,
          margin: const EdgeInsets.only(right: 14),
          transform: Matrix4.identity()
            ..scale(_hovered ? 1.03 : 1.0),
          transformAlignment: Alignment.center,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 140,
                      height: 196,
                      child: widget.anime.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: widget.anime.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  Container(color: AppTheme.surfaceLight),
                            )
                          : Container(color: AppTheme.surfaceLight),
                    ),
                  ),
                  if (widget.rank != null)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomLeft: Radius.circular(14),
                          ),
                        ),
                        child: Text(
                          '${widget.rank}',
                          style: AppTheme.mono(
                              fontSize: 13,
                              weight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ),
                    ),
                  // NEW badge for airing anime
                  if (widget.anime.status == 'RELEASING')
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          'NEW',
                          style: AppTheme.mono(
                              fontSize: 8,
                              weight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.anime.titleEnglish ?? widget.anime.title,
                style: AppTheme.sans(
                    fontSize: 12,
                    weight: FontWeight.w500,
                    color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.anime.genres.isNotEmpty)
                Text(
                  widget.anime.genres.first.toUpperCase(),
                  style: AppTheme.mono(
                      fontSize: 10, color: AppTheme.textMuted, letterSpacing: 0.8),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Badge ────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String label;
  const _Badge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTheme.mono(fontSize: 9, color: AppTheme.textMuted, letterSpacing: 1),
      ),
    );
  }
}

// ── Trending Row ─────────────────────────────────────────────
class _TrendingRow extends StatefulWidget {
  final Anime anime;
  final int rank;
  const _TrendingRow({required this.anime, required this.rank});

  @override
  State<_TrendingRow> createState() => _TrendingRowState();
}

class _TrendingRowState extends State<_TrendingRow>
    with SingleTickerProviderStateMixin {
  String? _savedStatus;
  late AnimationController _ctrl;
  late Animation<double> _scale;

  static const _statusMeta = {
    'WATCHING':      (Icons.play_circle_rounded,    Color(0xFFE8624A)),
    'PLAN_TO_WATCH': (Icons.bookmark_rounded,        Color(0xFF5B8DEF)),
    'COMPLETED':     (Icons.check_circle_rounded,    Color(0xFF4CAF7D)),
    'DROPPED':       (Icons.cancel_rounded,          Color(0xFFEF5B5B)),
  };

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('animeList').doc(widget.anime.id)
        .get();
    if (mounted && doc.exists) {
      setState(() => _savedStatus = doc.data()?['status'] as String?);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _onBookmarkTap() async {
    final status = await showHanjListSheet(context: context, anime: widget.anime, currentStatus: _savedStatus);
    if (status != null && status != '__REMOVE__' && mounted) {
      setState(() => _savedStatus = status);
      _ctrl.forward(from: 0);
    } else if (status == '__REMOVE__' && mounted) {
      setState(() => _savedStatus = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSaved = _savedStatus != null;
    final meta = isSaved ? _statusMeta[_savedStatus] : null;
    final icon = meta?.$1 ?? Icons.bookmark_border_rounded;
    final color = meta?.$2 ?? AppTheme.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: widget.anime))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    // Rank number
                    SizedBox(
                      width: 48,
                      child: Text(
                        widget.rank.toString().padLeft(2, '0'),
                        style: AppTheme.serif(
                          fontSize: 28,
                          weight: FontWeight.w700,
                          color: AppTheme.border,
                          height: 1,
                        ),
                      ),
                    ),
                    // Poster
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 52,
                        height: 72,
                        child: widget.anime.imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: widget.anime.imageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) =>
                                    Container(color: AppTheme.surfaceLight),
                              )
                            : Container(color: AppTheme.surfaceLight),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.anime.titleEnglish ?? widget.anime.title,
                            style: AppTheme.sans(
                                fontSize: 15, weight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            [
                              if (widget.anime.genres.isNotEmpty)
                                widget.anime.genres.first.toUpperCase(),
                              if (widget.anime.seasonYear != null) 'S1',
                            ].join(' · '),
                            style: AppTheme.mono(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                                letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: AppTheme.primary, size: 12),
                              const SizedBox(width: 3),
                              Text(
                                widget.anime.averageScore != null
                                    ? (widget.anime.averageScore! / 10)
                                        .toStringAsFixed(1)
                                    : '—',
                                style: AppTheme.sans(
                                    fontSize: 12,
                                    weight: FontWeight.w600,
                                    color: AppTheme.primary),
                              ),
                              if (widget.anime.episodes != null) ...[
                                Text(' · ',
                                    style: AppTheme.sans(
                                        color: AppTheme.textMuted,
                                        fontSize: 12)),
                                Text(
                                  '${widget.anime.episodes} ep',
                                  style: AppTheme.sans(
                                      fontSize: 12,
                                      color: AppTheme.textMuted),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Animated bookmark
                    GestureDetector(
                      onTap: _onBookmarkTap,
                      child: ScaleTransition(
                        scale: _scale,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSaved
                                ? color.withValues(alpha: 0.15)
                                : AppTheme.surfaceLight,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSaved ? color : AppTheme.border,
                            ),
                            boxShadow: isSaved
                                ? [BoxShadow(
                                    color: color.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  )]
                                : [],
                          ),
                          child: Icon(icon, color: isSaved ? color : AppTheme.textMuted, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.rank < 10)
                const Divider(height: 1, color: AppTheme.border),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Coming Up Section ─────────────────────────────────────────
Future<void> _saveReminder(BuildContext context, String animeId, bool val) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final ref = FirebaseFirestore.instance
      .collection('users').doc(uid)
      .collection('alerts').doc(animeId);
  if (val) {
    await ref.set({
      'animeId': animeId,
      'addedAt': FieldValue.serverTimestamp(),
    });
  } else {
    await ref.delete();
  }
}


class _ComingUpSection extends StatefulWidget {
  final List<Map<String, dynamic>> continueWatching;
  final Set<String> reminderIds;
  final void Function(String animeId, bool val) onToggleReminder;

  const _ComingUpSection({
    required this.continueWatching,
    required this.reminderIds,
    required this.onToggleReminder,
  });

  @override
  State<_ComingUpSection> createState() => _ComingUpSectionState();
}

class _ComingUpSectionState extends State<_ComingUpSection> {
  static const _days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadAiring();
  }

  @override
  void didUpdateWidget(_ComingUpSection old) {
    super.didUpdateWidget(old);
    // Re-fetch if the watching list changed.
    if (old.continueWatching.length != widget.continueWatching.length) {
      _loadAiring();
    }
  }

  Future<void> _loadAiring() async {
    if (_items.isEmpty) setState(() => _loading = true);

    final watching = widget.continueWatching;
    if (watching.isEmpty) {
      if (mounted) setState(() { _items = []; _loading = false; });
      return;
    }

    // Collect all anime IDs and fetch their airing schedules in ONE
    // batched request instead of one call per anime.
    final idToData = <int, Map<String, dynamic>>{};
    for (final data in watching) {
      final idStr = (data['animeId'] ?? data['id'] ?? '').toString();
      final id = int.tryParse(idStr);
      if (id != null) idToData[id] = data;
    }
    if (idToData.isEmpty) {
      if (mounted) setState(() { _items = []; _loading = false; });
      return;
    }

    final airingById = await _fetchAiringBatch(idToData.keys.toList());

    final results = <Map<String, dynamic>>[];
    airingById.forEach((id, airing) {
      final data = idToData[id];
      if (data == null) return;
      final episode  = (airing['episode'] as num?)?.toInt();
      final airingAt = (airing['airingAt'] as num?)?.toInt();
      if (episode == null || airingAt == null) return;
      results.add({
        'title':    data['title'] as String? ?? 'Unknown',
        'animeId':  id.toString(),
        'episode':  episode,
        'date':     DateTime.fromMillisecondsSinceEpoch(airingAt * 1000),
        'imageUrl': data['imageUrl'] as String? ?? '',
      });
    });

    results.sort((a, b) =>
        (a['date'] as DateTime).compareTo(b['date'] as DateTime));
    final top = results.take(3).toList();

    if (mounted) {
      setState(() {
        _items = top;
        _loading = false;
      });
    }
  }

  /// Fetches next-airing-episode for many anime in a single AniList
  /// request. Paginated (perPage 50) to cover large watching lists.
  Future<Map<int, Map<String, dynamic>>> _fetchAiringBatch(
      List<int> ids) async {
    final out = <int, Map<String, dynamic>>{};
    const url = 'https://graphql.anilist.co';
    const query = r'''
    query ($ids: [Int]) {
      Page(page: 1, perPage: 50) {
        media(id_in: $ids, type: ANIME) {
          id
          nextAiringEpisode { episode airingAt }
        }
      }
    }
    ''';

    try {
      await AnilistService.throttle();
      final resp = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query, 'variables': {'ids': ids}}),
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode == 429) {
        final retryAfter =
            int.tryParse(resp.headers['retry-after'] ?? '') ?? 3;
        AnilistService.backoff(retryAfter);
        return out; // skip this cycle; next refresh will retry
      }
      if (resp.statusCode != 200) return out;

      final body = jsonDecode(resp.body);
      final media = body['data']?['Page']?['media'] as List? ?? [];
      for (final m in media) {
        final id = m['id'] as int?;
        final airing = m['nextAiringEpisode'] as Map<String, dynamic>?;
        if (id != null && airing != null) out[id] = airing;
      }
    } catch (_) {}
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;

    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Center(
          child: Text(
            'Add anime to your watching list\nto see upcoming episodes',
            textAlign: TextAlign.center,
            style: AppTheme.sans(
                fontSize: 13, color: AppTheme.textMuted, height: 1.5),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: items.asMap().entries.map((e) {
          final i = e.key;
          final item = e.value;
          final date = item['date'] as DateTime;
          final animeId = (item['animeId'] ?? '').toString();
          final isOn = animeId.isNotEmpty && widget.reminderIds.contains(animeId);
          return Column(
            children: [
              InkWell(
                onTap: () => _openDetail(context, animeId),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // Anime cover
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 40,
                        height: 56,
                        child: (item['imageUrl'] as String).isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item['imageUrl'] as String,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) =>
                                    Container(color: AppTheme.surfaceMid),
                              )
                            : Container(color: AppTheme.surfaceMid),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Date badge
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceMid,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _days[date.weekday - 1],
                            style: AppTheme.mono(
                                fontSize: 8,
                                color: AppTheme.primary,
                                letterSpacing: 0.5,
                                weight: FontWeight.w600),
                          ),
                          Text(
                            '${date.day}',
                            style: AppTheme.sans(
                                fontSize: 15,
                                weight: FontWeight.w700,
                                color: AppTheme.textPrimary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title + episode
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'] as String,
                            style: AppTheme.serif(
                                fontSize: 13, weight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Ep ${item['episode']} · ${_formatTime(date)}',
                            style: AppTheme.mono(
                                fontSize: 10, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    // Bell toggle
                    GestureDetector(
                      onTap: () {
                        final newVal = !isOn;
                        if (animeId.isNotEmpty) {
                          widget.onToggleReminder(animeId, newVal);
                          _saveReminder(context, animeId, newVal);
                        }
                        final animeTitle = item['title'] as String;
                        final episode = item['episode'] as int;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(newVal
                                ? 'Reminder set for $animeTitle Ep $episode'
                                : 'Reminder removed for $animeTitle Ep $episode'),
                            backgroundColor: AppTheme.surfaceLight,
                            behavior: SnackBarBehavior.floating,
                            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isOn
                              ? AppTheme.primary
                              : AppTheme.surfaceMid,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isOn
                                ? AppTheme.primary
                                : AppTheme.border,
                          ),
                          boxShadow: isOn
                              ? [BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )]
                              : [],
                        ),
                        child: Icon(
                          isOn
                              ? Icons.notifications_rounded
                              : Icons.notifications_none_rounded,
                          color: isOn ? Colors.white : AppTheme.textMuted,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
              if (i < items.length - 1)
                const Divider(height: 1, color: AppTheme.border),
            ],
          );
        }).toList(),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    // dt is already device-local (converted from AniList's epoch).
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool _opening = false;

  Future<void> _openDetail(BuildContext context, String animeId) async {
    if (_opening || animeId.isEmpty) return;
    _opening = true;

    // Try the cached detail first for an instant open, else fetch by id.
    Anime? anime =
        await OfflineCacheService.instance.getCachedAnimeDetail(animeId);
    anime ??= await AnilistService().getAnimeById(animeId);

    _opening = false;
    if (anime != null && mounted) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime!)));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open right now — try again')),
      );
    }
  }
}

// ── Plan to Watch Card ───────────────────────────────────────
// Simple poster + title card for the "Up next" row on Home.
// Tapping opens the anime detail screen.
class _PlanCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PlanCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final title    = data['title'] as String? ?? 'Unknown';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final animeId  = data['animeId']?.toString() ?? '';
    final genres   = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
    final episodes = data['episodes'] as int?;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnimeDetailScreen(
              anime: Anime(
                id: animeId,
                title: title,
                imageUrl: imageUrl,
                episodes: episodes,
                genres: genres,
              ),
            ),
          ),
        ),
        child: Container(
          width: 140,
          margin: const EdgeInsets.only(right: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 140,
                  height: 196,
                  child: imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) =>
                              Container(color: AppTheme.surfaceLight),
                        )
                      : Container(color: AppTheme.surfaceLight),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: AppTheme.sans(
                    fontSize: 11,
                    weight: FontWeight.w500,
                    color: AppTheme.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (episodes != null)
                Text(
                  '$episodes EP',
                  style:
                      AppTheme.mono(fontSize: 9, color: AppTheme.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
