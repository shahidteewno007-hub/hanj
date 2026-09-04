import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/founder_service.dart';
import 'founder_card.dart';
import '../profile/edit_profile_screen.dart';
import '../stats/stats_screen.dart';
import '../social/activity_feed_screen.dart';
import '../import/anilist_import_screen.dart';
import '../calendar/anime_calendar_screen.dart';
import '../social/social_screen.dart';
import '../profile/notification_preferences_screen.dart';
import '../profile/taste_profile.dart';
import '../profile/ranking_cards.dart';
import '../cards/card_collection_screen.dart';
import '../cards/hanj_card.dart' as hc;
import '../../cadre/screens/cadre_lobby_screen.dart';
import '../auth/delete_account_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _firestoreService = FirestoreService();
  int _avatarColorIndex = 0;
  String? _avatarImageUrl;

  // Founder status
  FounderStatus _founderStatus = const FounderStatus(isFounder: false);
  // False until founder status is known (from disk or Firestore). While false
  // the card's footprint is reserved, so it fills in instead of popping in.
  bool _founderResolved = false;
  Map<String, dynamic>? _featuredCard;

  static const _avatarGradients = [
    [Color(0xFF7C3AED), Color(0xFFE91E8C)],
    [Color(0xFF2196F3), Color(0xFF00BCD4)],
    [Color(0xFFFF6B35), Color(0xFFFF8E53)],
    [Color(0xFF4CAF50), Color(0xFF8BC34A)],
    [Color(0xFFE91E63), Color(0xFFFF5722)],
    [Color(0xFF9C27B0), Color(0xFF3F51B5)],
    [Color(0xFF00BCD4), Color(0xFF4CAF50)],
    [Color(0xFFFF9800), Color(0xFFFFEB3B)],
  ];

  @override
  void initState() {
    super.initState();
    _loadAvatarPrefs();
    _resolveFounderStatus();
    _loadFeaturedCard();
  }

  Future<void> _loadFeaturedCard() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      final pinned = (doc.data()?['pinnedCards'] as List<dynamic>?) ?? [];
      if (pinned.isNotEmpty && mounted) {
        setState(() => _featuredCard = Map<String, dynamic>.from(pinned.first as Map));
      }
    } catch (_) {}
  }

  Future<void> _loadAvatarPrefs() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists && mounted) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _avatarColorIndex = (data['avatarColorIndex'] as int?) ?? 0;
        _avatarImageUrl = data['avatarImageUrl'] as String?;
      });
    }
  }

  /// Claims a founder number for the first 50 users (idempotent — only ever
  /// claims once per user) and loads the resulting status for display.
  ///
  /// Founder status is immutable once granted, so a cached "is a founder"
  /// answer is authoritative forever: it paints on the first frame and no
  /// network work is needed at all. Anyone not yet known to be a founder
  /// still pays for the claim transaction plus the read, because they may
  /// still be eligible for one of the remaining slots.
  Future<void> _resolveFounderStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _founderResolved = true);
      return;
    }

    // 1. Disk first. A granted status can never change, so this is final.
    final cached = await FounderService.instance.getCachedStatus();
    if (cached != null && mounted) {
      setState(() {
        _founderStatus   = cached;
        _founderResolved = true;
      });
      if (cached.isFounder) return; // Immutable — nothing left to check.
    }

    // 2. Not known to be a founder. Attempt the claim (a no-op if they
    //    already hold a number or slots are full), then re-read.
    await FounderService.instance.claimFounderNumber(uid);
    final status = await FounderService.instance.getStatus(uid);
    if (!mounted) return;
    setState(() {
      _founderStatus   = status;
      _founderResolved = true;
    });
  }

  String _formatWatchTime(int totalMinutes) {
    final days = totalMinutes ~/ (60 * 24);
    final hours = (totalMinutes % (60 * 24)) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    return '${hours}h';
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final initial =
        (user?.displayName ?? user?.email ?? 'A')[0].toUpperCase();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestoreService.getAnimeList(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];

          // Compute stats
          int totalAnime = docs.length;
          int completed = 0;
          int watching = 0;
          int planToWatch = 0;
          int dropped = 0;
          double totalRating = 0;
          int ratedCount = 0;
          int totalEpisodes = 0;
          Map<String, int> genreCounts = {};

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            switch (data['status']) {
              case 'COMPLETED':
                completed++;
                totalEpisodes += (data['episodes'] as int?) ?? 0;
                break;
              case 'WATCHING':
                watching++;
                totalEpisodes += (data['currentEpisode'] as int?) ?? 0;
                break;
              case 'PLAN_TO_WATCH':
                planToWatch++;
                break;
              case 'DROPPED':
                dropped++;
                break;
            }
            if (data['userRating'] != null) {
              totalRating +=
                  (data['userRating'] as num).toDouble();
              ratedCount++;
            }
            final genres =
                (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
            for (final g in genres) {
              genreCounts[g] = (genreCounts[g] ?? 0) + 1;
            }
          }

          final avgRating =
              ratedCount > 0 ? totalRating / ratedCount : 0.0;
          final watchTimeMinutes = totalEpisodes * 24;
          final topGenres = (genreCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .take(3)
              .map((e) => e.key)
              .toList();

          return MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: CustomScrollView(
            slivers: [
              // ── AppBar ──────────────────────────────────
              SliverAppBar(
                backgroundColor: AppTheme.background,
                floating: true,
                snap: true,
                titleSpacing: 20,
                title: Text('Profile',
                    style: AppTheme.serif(
                        fontSize: 22, weight: FontWeight.w700)),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download_rounded,
                        color: AppTheme.textSecondary, size: 20),
                    tooltip: 'Import',
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const AnilistImportScreen())),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        color: AppTheme.textSecondary, size: 20),
                    tooltip: 'Edit Profile',
                    onPressed: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const EditProfileScreen()));
                      _loadAvatarPrefs();
                    },
                  ),
                  // Theme toggle hidden — light mode coming soon
                  // (Re-enable when AppTheme.background etc. are made theme-aware)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert_rounded,
                        color: AppTheme.textSecondary, size: 20),
                    color: AppTheme.surfaceMid,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    onSelected: (val) {
                      switch (val) {
                        case 'hanj_collection':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const CardCollectionScreen()));
                          break;
                        case 'cards':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const RankingCardsScreen()));
                          break;
                        case 'taste':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const TasteProfileScreen()));
                          break;
                        case 'stats':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const StatsScreen()));
                          break;
                        case 'feed':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const ActivityFeedScreen()));
                          break;
                        case 'calendar':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const AnimeCalendarScreen()));
                          break;
                        case 'social':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const SocialScreen()));
                          break;
                        case 'notifications':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const NotificationPreferencesScreen()));
                          break;
                        case 'more':
                          _showMoreSheet(context);
                          break;
                        case 'signout':
                          _confirmSignOut(context, authService);
                          break;
                      }
                    },
                    itemBuilder: (_) => [
                      _menuItem('cards', Icons.grid_view_rounded, 'Ranking Cards'),
                      _menuItem('stats', Icons.bar_chart_rounded, 'Advanced Stats'),
                      // 'Your Wrapped' is hidden during beta — a yearly recap
                      // has no meaningful data to show mid-year.
                      _menuItem('feed', Icons.dynamic_feed_rounded, 'Activity Feed'),
                      _menuItem('calendar', Icons.calendar_month_rounded, 'Anime Calendar'),
                      _menuItem('social', Icons.people_rounded, 'Social'),
                      _menuItem('notifications', Icons.notifications_outlined, 'Notifications'),
                      const PopupMenuDivider(),
                      _menuItem('more', Icons.more_horiz_rounded, 'More'),
                      _menuItem('signout', Icons.logout_rounded, 'Sign Out',
                          color: AppTheme.error),
                    ],
                  ),
                  const SizedBox(width: 4),
                ],
              ),

              // ── Profile Hero Card ────────────────────────
              SliverToBoxAdapter(
                key: const ValueKey('profile-header'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: GestureDetector(
                    onTap: () async {
                      await Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const EditProfileScreen()));
                      _loadAvatarPrefs();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          Stack(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: _avatarImageUrl == null
                                      ? LinearGradient(
                                          colors: _avatarGradients[
                                              _avatarColorIndex],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),
                                child: _avatarImageUrl != null
                                    ? ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        child: Image.network(
                                          _avatarImageUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              Center(
                                            child: Text(initial,
                                                style: AppTheme.serif(
                                                    fontSize: 24,
                                                    weight:
                                                        FontWeight.w700,
                                                    color: Colors.white)),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(initial,
                                            style: AppTheme.serif(
                                                fontSize: 24,
                                                weight: FontWeight.w700,
                                                color: Colors.white)),
                                      ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName ?? 'Anime Fan',
                                  style: AppTheme.serif(
                                      fontSize: 20,
                                      weight: FontWeight.w700),
                                ),
                                if (_founderStatus.isFounder &&
                                    _founderStatus.number != null) ...[
                                  const SizedBox(height: 6),
                                  FounderBadge(number: _founderStatus.number!),
                                ],
                                const SizedBox(height: 2),
                                Text(
                                  'MEMBER SINCE ${user?.metadata.creationTime?.year ?? '—'} · ★ ${avgRating.toStringAsFixed(1)} AVG',
                                  style: AppTheme.mono(
                                      fontSize: 10,
                                      color: AppTheme.textMuted,
                                      letterSpacing: 0.8),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    _PillBadge(
                                      'PACE · ${watching > 0 ? "$watching" : "0"} WATCHING',
                                      AppTheme.watching,
                                    ),
                                    const SizedBox(width: 8),
                                    _PillBadge(
                                      '$completed DONE',
                                      AppTheme.completed,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Founder Card (first 50 users only) ───────
              // Until status is known, hold the card's footprint so it fills
              // in rather than appearing and pushing everything below it down.
              if (!_founderResolved)
                const SliverToBoxAdapter(
                  key: ValueKey('profile-founder'),
                  child: FounderCardPlaceholder(),
                )
              else if (_founderStatus.isFounder)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-founder'),
                  child: FounderCard(status: _founderStatus),
                ),

              // ── Collection Hero Card ─────────────────────
              SliverToBoxAdapter(
                key: const ValueKey('profile-collection'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 16, 20),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left — stats
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'COLLECTION',
                                style: AppTheme.mono(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '$totalAnime',
                                    style: AppTheme.mono(
                                      fontSize: 52,
                                      weight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Titles',
                                    style: AppTheme.serif(
                                      fontSize: 18,
                                      weight: FontWeight.w600,
                                      color: AppTheme.textMuted,
                                      style: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tracked on Hanj',
                                style: AppTheme.sans(
                                  fontSize: 12,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right — real HanjCard or faint logo
                        if (_featuredCard != null)
                          GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const CardCollectionScreen())),
                            // Square corners: HanjCard is square by design
                            // (_CardShell paints square, HanjCard clips with
                            // ClipRect). This was the only place one got
                            // rounded off.
                            child: ClipRect(
                              child: SizedBox(
                                width:  hc.HanjCard.kWidth  * 0.52,
                                height: hc.HanjCard.kHeight * 0.52,
                                // Render the card at its natural 200x300 and scale the
                                // whole thing down. The card has fixed-pixel internals
                                // (footer text, paddings) that don't shrink on their own,
                                // so sizing it directly overflows at small sizes.
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: hc.HanjCard(
                                    isUnlocked: true,
                                    card: hc.HanjCardData(
                                      id: (_featuredCard!['id'] as String?) ?? '',
                                      name: ((_featuredCard!['name'] ?? _featuredCard!['cardName']) as String?) ?? '',
                                      description: (_featuredCard!['description'] as String?) ?? '',
                                      rarity: hc.CardRarity.values.firstWhere(
                                        (r) => r.name == ((_featuredCard!['rarity'] as String?) ?? 'common'),
                                        orElse: () => hc.CardRarity.common,
                                      ),
                                      category: ((_featuredCard!['category'] as String?) ?? 'ÆTHER').toUpperCase(),
                                      kanji: (_featuredCard!['kanji'] as String?) ?? '道',
                                      cardNumber: (_featuredCard!['cardNumber'] as int?) ?? 0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Opacity(
                            opacity: 0.07,
                            child: Image.asset(
                              'assets/images/hanj_wing_transparent.png',
                              width: 78, height: 78,
                              fit: BoxFit.contain,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Stat tiles ───────────────────────────────
              SliverToBoxAdapter(
                key: const ValueKey('profile-section-a'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: 'EPISODES',
                          value: '$totalEpisodes',
                          sub: 'watched',
                          icon: Icons.play_arrow_rounded,
                          iconColor: AppTheme.watching,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          label: 'AVG RATING',
                          value: avgRating.toStringAsFixed(1),
                          sub: 'of 10',
                          icon: Icons.star_rounded,
                          iconColor: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                key: const ValueKey('profile-section-b'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          label: 'WATCH TIME',
                          value: _formatWatchTime(watchTimeMinutes),
                          sub: 'lifetime',
                          icon: Icons.access_time_rounded,
                          iconColor: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          label: 'COMPLETED',
                          value: '$completed',
                          sub: 'series',
                          icon: Icons.check_rounded,
                          iconColor: AppTheme.completed,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Hanj Cards ───────────────────────────────
              SliverToBoxAdapter(
                key: const ValueKey('profile-section-c'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _HanjCardsBanner(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const CardCollectionScreen())),
                  ),
                ),
              ),

              // ── Cadre ────────────────────────────────────
              SliverToBoxAdapter(
                key: const ValueKey('profile-section-d'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: _CadreBanner(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => const CadreLobbyScreen())),
                  ),
                ),
              ),

              // ── Anime Taste Profile ──────────────────────
              if (totalAnime > 0)
                const SliverToBoxAdapter(
                  key: ValueKey('profile-stats-header'),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: TasteProfileCard(),
                  ),
                ),

              // ── By Status bar ────────────────────────────
              if (totalAnime > 0)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-stats'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: _StatusBreakdown(
                      watching: watching,
                      completed: completed,
                      planToWatch: planToWatch,
                      dropped: dropped,
                      total: totalAnime,
                    ),
                  ),
                ),

              // ── Top Genres ───────────────────────────────
              if (topGenres.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-genres'),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Top genres',
                              style: AppTheme.serif(
                                  fontSize: 18,
                                  weight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: topGenres
                                .map((g) => Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primary
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color: AppTheme.primary
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: Text(g,
                                          style: AppTheme.sans(
                                              fontSize: 13,
                                              color: AppTheme.primary)),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
        },
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String val, IconData icon, String label,
      {Color? color}) {
    return PopupMenuItem(
      value: val,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? AppTheme.textSecondary),
          const SizedBox(width: 10),
          Text(label,
              style: AppTheme.sans(
                  fontSize: 14, color: color ?? AppTheme.textPrimary)),
        ],
      ),
    );
  }

  /// Secondary "More" menu — holds rarely-used and destructive actions so
  /// they aren't surfaced in the main menu on every tap.
  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('More',
                      style: AppTheme.serif(
                          fontSize: 18, weight: FontWeight.w700)),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded,
                    color: AppTheme.error, size: 20),
                title: Text('Delete Account',
                    style: AppTheme.sans(
                        fontSize: 14, color: AppTheme.error)),
                subtitle: Text('Permanently remove your account and data',
                    style: AppTheme.sans(
                        fontSize: 12, color: AppTheme.textMuted)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(context, MaterialPageRoute(
                      builder: (_) => const DeleteAccountScreen()));
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmSignOut(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceMid,
        title: Text('Sign Out',
            style: AppTheme.serif(
                fontSize: 18, weight: FontWeight.w600)),
        content: Text('Are you sure you want to sign out?',
            style: AppTheme.sans(
                fontSize: 14, color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: AppTheme.sans(color: AppTheme.textMuted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await authService.signOut();
            },
            child: Text('Sign Out',
                style: AppTheme.sans(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

// ── Helper Widgets ───────────────────────────────────────────

class _PillBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _PillBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: AppTheme.mono(
              fontSize: 9,
              weight: FontWeight.w600,
              color: color,
              letterSpacing: 0.8)),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final Color iconColor;

  const _StatTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: AppTheme.mono(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      letterSpacing: 0.8)),
              Icon(icon, color: iconColor, size: 14),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: AppTheme.mono(
                  fontSize: 28, weight: FontWeight.w700, color: AppTheme.textPrimary)),
          Text(sub,
              style: AppTheme.sans(
                  fontSize: 12, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

// ── Status Breakdown (replaces donut) ────────────────────────
class _StatusBreakdown extends StatelessWidget {
  final int watching, completed, planToWatch, dropped, total;
  const _StatusBreakdown({
    required this.watching,
    required this.completed,
    required this.planToWatch,
    required this.dropped,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('By status',
              style: AppTheme.serif(fontSize: 18, weight: FontWeight.w600)),
          const SizedBox(height: 16),

          // ── Stacked bar ──
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  if (completed > 0)
                    Flexible(
                      flex: completed,
                      child: Container(color: AppTheme.completed),
                    ),
                  if (watching > 0)
                    Flexible(
                      flex: watching,
                      child: Container(color: AppTheme.watching),
                    ),
                  if (planToWatch > 0)
                    Flexible(
                      flex: planToWatch,
                      child: Container(color: AppTheme.planToWatch),
                    ),
                  if (dropped > 0)
                    Flexible(
                      flex: dropped,
                      child: Container(color: AppTheme.dropped),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Four stat columns ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StatusStat('Completed', completed, AppTheme.completed),
              _StatusStat('Watching', watching, AppTheme.watching),
              _StatusStat('Plan', planToWatch, AppTheme.planToWatch),
              _StatusStat('Dropped', dropped, AppTheme.dropped),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _StatusStat(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label,
                style: AppTheme.mono(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.6)),
          ],
        ),
        const SizedBox(height: 4),
        Text('$count',
            style: AppTheme.mono(
                fontSize: 20,
                weight: FontWeight.w700,
                color: AppTheme.textPrimary)),
      ],
    );
  }
}

// ── Mini bar chart (Total in Library card) ────────────────────
class _MiniBarChart extends StatelessWidget {
  final int watching;
  final int completed;
  final int planToWatch;
  final int dropped;

  const _MiniBarChart({
    required this.watching,
    required this.completed,
    required this.planToWatch,
    required this.dropped,
  });

  @override
  Widget build(BuildContext context) {
    final total = watching + completed + planToWatch + dropped;
    if (total == 0) return const SizedBox(width: 80);

    return SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              width: 80,
              child: Row(
                children: [
                  if (completed > 0)
                    Flexible(flex: completed,
                        child: Container(color: AppTheme.completed)),
                  if (watching > 0)
                    Flexible(flex: watching,
                        child: Container(color: AppTheme.watching)),
                  if (planToWatch > 0)
                    Flexible(flex: planToWatch,
                        child: Container(color: AppTheme.planToWatch)),
                  if (dropped > 0)
                    Flexible(flex: dropped,
                        child: Container(color: AppTheme.dropped)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Dot legend
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (completed > 0) _Dot(AppTheme.completed),
              if (watching > 0)  _Dot(AppTheme.watching),
              if (planToWatch > 0) _Dot(AppTheme.planToWatch),
              if (dropped > 0)   _Dot(AppTheme.dropped),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot(this.color);
  @override
  Widget build(BuildContext context) => Container(
        width: 6, height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

// ── Card Showcase ─────────────────────────────────────────────────────────────
// Shows up to 3 pinned cards on the profile. Reads from users/{uid}/pinnedCards.
// If no cards pinned yet, falls back to the plain banner.

// ── Hanj Cards Banner ─────────────────────────────────────────────────────────
class _HanjCardsBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _HanjCardsBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0C09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD4A96A).withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD4A96A).withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFD4A96A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFFD4A96A).withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.style_rounded,
                  color: Color(0xFFD4A96A), size: 18),
            ),
            const SizedBox(width: 14),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hanj Cards',
                    style: AppTheme.sans(
                        fontSize: 14,
                        weight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Collect rare cards by watching anime',
                    style: AppTheme.sans(
                        fontSize: 11,
                        color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppTheme.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Cadre entry ───────────────────────────────────────────────
// Styled off _HanjCardsBanner so the two sit together, but coral
// instead of gold so they don't read as the same feature.
class _CadreBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _CadreBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    const coral = Color(0xFFE8624A);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0C09),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: coral.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: coral.withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: coral.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: coral.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.local_fire_department_rounded,
                  color: coral, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cadre',
                    style: AppTheme.sans(
                        fontSize: 14,
                        weight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Draft a deck from any cast and clash',
                    style: AppTheme.sans(
                        fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: AppTheme.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Mini card preview ─────────────────────────────────────────
// Shows the user's first pinned card in the Collection stat tile.
// Uses the rarity colour as a border accent and the card name as
// the only text — keeps it readable at 72×108.
class _HanjCardMini extends StatelessWidget {
  final Map<String, dynamic> cardData;
  const _HanjCardMini({required this.cardData});

  static const _rarityColors = {
    'common':    Color(0xFF9E9E9E),
    'rare':      Color(0xFF5B8DEF),
    'epic':      Color(0xFFB06EE8),
    'legendary': Color(0xFFD4A96A),
    'seasonal':  Color(0xFF4CAF7D),
    'secret':    Color(0xFF9E9E9E),
  };

  @override
  Widget build(BuildContext context) {
    final name   = (cardData['name'] ?? cardData['cardName']) as String? ?? '';
    final rarity = cardData['rarity'] as String? ?? 'common';
    final kanji  = cardData['kanji'] as String? ?? '道';
    final color  = _rarityColors[rarity] ?? const Color(0xFF9E9E9E);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0B09),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 1.5),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Kanji watermark
          Center(
            child: Text(
              kanji,
              style: TextStyle(
                fontSize: 52,
                color: color.withValues(alpha: 0.18),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          // Card name at bottom
          Positioned(
            bottom: 6, left: 4, right: 4,
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.2,
              ),
            ),
          ),
          // Rarity glow dot top right
          Positioned(
            top: 5, right: 5,
            child: Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
