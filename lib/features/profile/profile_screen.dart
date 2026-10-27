import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/hanko_seal.dart';
import '../../widgets/hanko_seal_register.dart';
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
          // Episodes under one definition (stage H5, item e), the one
          // Advanced Stats uses (stats_screen.dart): a completed show counts
          // its episode total, and any other show the episode you logged,
          // dropped and paused ones included, since you watched those too.
          // Rewatches aren't counted: the list keeps no rewatch count.
          int totalEpisodes = 0;
          Map<String, int> genreCounts = {};
          // Every rating as stored, for the seal register (item d).
          final ratings = <double>[];

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            switch (data['status']) {
              case 'COMPLETED':
                completed++;
                break;
              case 'WATCHING':
                watching++;
                break;
              case 'PLAN_TO_WATCH':
                planToWatch++;
                break;
              case 'DROPPED':
                dropped++;
                break;
            }
            final total = (data['episodes'] as num?)?.toInt();
            final current = (data['currentEpisode'] as num?)?.toInt();
            if (data['status'] == 'COMPLETED' && total != null) {
              totalEpisodes += total;
            } else if (current != null) {
              totalEpisodes += current;
            }
            if (data['userRating'] != null) {
              ratings.add((data['userRating'] as num).toDouble());
            }
            final genres =
                (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
            for (final g in genres) {
              genreCounts[g] = (genreCounts[g] ?? 0) + 1;
            }
          }

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
              // Name first (Hanko stage H5): the name below heads the page, so
              // the bar keeps only its actions, as hanko.html draws it.
              SliverAppBar(
                backgroundColor: AppTheme.background,
                floating: true,
                snap: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.download_sharp,
                        color: AppTheme.hankoWashi, size: 22),
                    tooltip: 'Import',
                    style: _hankoIconButtonStyle,
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const AnilistImportScreen())),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_sharp,
                        color: AppTheme.hankoWashi, size: 22),
                    tooltip: 'Edit Profile',
                    style: _hankoIconButtonStyle,
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
                    icon: const Icon(Icons.more_vert_sharp,
                        color: AppTheme.hankoWashi, size: 22),
                    style: _hankoIconButtonStyle,
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

              // ── The header (Hanko stage H5, item a) ──────
              SliverToBoxAdapter(
                key: const ValueKey('profile-header'),
                child: _column(_buildHeader(user, initial)),
              ),

              // ── The counts (Hanko stage H5, item e) ──────
              // In words, in place of the four stat tiles, "By status" and
              // "Top genres".
              SliverToBoxAdapter(
                key: const ValueKey('profile-counts'),
                child: _column(_buildCounts(
                  titles: totalAnime,
                  episodes: totalEpisodes,
                  watching: watching,
                  completed: completed,
                  planned: planToWatch,
                  dropped: dropped,
                  genres: topGenres,
                )),
              ),

              // ── Your ratings (Hanko stage H5, item d) ────
              SliverToBoxAdapter(
                key: const ValueKey('profile-ratings'),
                child: _column(_buildRatings(ratings)),
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

              // ── Founder Card (first 50 users only) ───────
              // Moved below the record (stage H5): the Founder pill stays
              // under the name, and the full card no longer pushes the
              // record out of the first screen.
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

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
        },
      ),
    );
  }

  // Hanko's press: an 8% washi wash, no ripple, square corners.
  static const ButtonStyle _hankoIconButtonStyle = ButtonStyle(
    overlayColor: WidgetStatePropertyAll(AppTheme.hankoPressWash),
    splashFactory: NoSplash.splashFactory,
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
    )),
  );

  /// On a wide window (1024 px and up) each block keeps the phone's column
  /// instead of stretching: Responsive.proseMaxWidth, 440 px, plus the
  /// gutters, hung on the left edge as Home's record column is (stage H4,
  /// item i). Below 1024 it does nothing, so a phone keeps its layout in
  /// either orientation (WEB.md §9.2).
  Widget _column(Widget child) {
    if (!Responsive.isDesktop(context)) return child;
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
            maxWidth: Responsive.proseMaxWidth + 2 * AppTheme.hankoGutter),
        child: child,
      ),
    );
  }

  /// The header (Hanko stage H5, item a): your monogram, your name, the
  /// Founder pill under it, and "Logging anime since 2025" from the
  /// account's creation date. Hanj keeps no handle (no username field), so
  /// none is drawn. Tapping it opens Edit Profile, as the old header card
  /// did.
  ///
  /// The name sits beside the monogram when it has 200 px there, and under
  /// it when the column is narrower, so a long name never squeezes into a
  /// sliver beside the seal.
  Widget _buildHeader(User? user, String initial) {
    final name = user?.displayName ?? 'Anime Fan';
    final since = user?.metadata.creationTime?.year;
    final founder = _founderStatus.isFounder && _founderStatus.number != null;

    final identity = LayoutBuilder(builder: (context, constraints) {
      final words = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(name,
                style: AppTheme.hankoSerif(fontSize: 28, height: 1.15)),
          ),
          if (founder) ...[
            const SizedBox(height: 8),
            FounderBadge(number: _founderStatus.number!),
          ],
          if (since != null) ...[
            const SizedBox(height: 6),
            Text(
              'Logging anime since $since',
              style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoMetaSize,
                color: AppTheme.hankoStone,
                height: 1.3,
              ),
            ),
          ],
        ],
      );
      final monogram = _Monogram(initial: initial, imageUrl: _avatarImageUrl);
      final beside =
          constraints.maxWidth - _Monogram.size - 14 >= 200;
      return beside
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                monogram,
                const SizedBox(width: 14),
                Expanded(child: words),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                monogram,
                const SizedBox(height: 14),
                words,
              ],
            );
    });

    final editable = Semantics(
      hint: 'Edit profile',
      child: InkWell(
        onTap: () async {
          await Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) =>
                      const EditProfileScreen()));
          _loadAvatarPrefs();
        },
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: identity,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 4, AppTheme.hankoGutter, 0),
      // Your pinned Hanj Card stands beside your name (item b), as
      // hanko.html places it, at the right of the header.
      child: _featuredCard == null
          ? editable
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: editable),
                const SizedBox(width: 16),
                _pinnedCard(_featuredCard!),
              ],
            ),
    );
  }

  /// Your pinned Hanj Card (Hanko stage H5, item b), drawn at 0.7 of its
  /// 200 x 300 (140 x 210), so its name sets at about 12.6 px; at the old
  /// 0.52 it was about 9.4 px, below one device pixel per hairline on the
  /// CPH2573 (DESIGN.md §3.3.2). Tapping it opens your collection, as
  /// before.
  ///
  /// It is the live card, glow and all, as before. PERF.md S2-3 measured
  /// Profile's worst raster frame (40.1 ms) on this card at 0.52; at 0.7
  /// and in the header it needs measuring again on the phone.
  static const double _pinnedScale = 0.7;

  Widget _pinnedCard(Map<String, dynamic> card) {
    final name = ((card['name'] ?? card['cardName']) as String?) ?? '';
    return Semantics(
      button: true,
      label: name.isEmpty
          ? 'Your pinned Hanj Card'
          : 'Your pinned Hanj Card, $name',
      hint: 'Opens your collection',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CardCollectionScreen())),
        // Square corners: HanjCard is square by design
        // (_CardShell paints square, HanjCard clips with
        // ClipRect). This was the only place one got
        // rounded off.
        child: ClipRect(
          child: SizedBox(
            width:  hc.HanjCard.kWidth  * _pinnedScale,
            height: hc.HanjCard.kHeight * _pinnedScale,
            // Render the card at its natural 200x300 and scale the
            // whole thing down. The card has fixed-pixel internals
            // (footer text, paddings) that don't shrink on their own,
            // so sizing it directly overflows at small sizes.
            child: FittedBox(
              fit: BoxFit.contain,
              child: hc.HanjCard(
                isUnlocked: true,
                card: hc.HanjCardData(
                  id: (card['id'] as String?) ?? '',
                  name: name,
                  description: (card['description'] as String?) ?? '',
                  rarity: hc.CardRarity.values.firstWhere(
                    (r) => r.name == ((card['rarity'] as String?) ?? 'common'),
                    orElse: () => hc.CardRarity.common,
                  ),
                  category: ((card['category'] as String?) ?? 'ÆTHER').toUpperCase(),
                  kanji: (card['kanji'] as String?) ?? '道',
                  cardNumber: (card['cardNumber'] as int?) ?? 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The counts you can trust now (Hanko stage H5, item e), in words: titles
  /// all time and episodes, as one sentence in Shippori, then the statuses
  /// and the top genres in Jost. "This year" and hours wait for completion
  /// dates and episode lengths, which the list doesn't keep (question 27).
  ///
  /// Words, not tiles or pills: this is what "By status", "Top genres" and
  /// the header's "PACE · 6 WATCHING" and "7 DONE" pills said. As text on
  /// the page it reads in washi and stone on sumi (15.3:1 and 6.9:1) and
  /// wraps at any text size, where the pills measured 4.51:1 and 4.42:1 at
  /// 9 px and overflowed by 15 px at 1.3x (H2 QA, N8 and S2).
  Widget _buildCounts({
    required int titles,
    required int episodes,
    required int watching,
    required int completed,
    required int planned,
    required int dropped,
    required List<String> genres,
  }) {
    final n = NumberFormat.decimalPattern();
    String count(int value, String one, String many) =>
        '${n.format(value)} ${value == 1 ? one : many}';

    final sentence = titles == 0
        ? 'Nothing logged yet.'
        : episodes == 0
            ? 'You\'ve logged ${count(titles, 'title', 'titles')}.'
            : 'You\'ve logged ${count(titles, 'title', 'titles')} and '
                'watched ${count(episodes, 'episode', 'episodes')}.';
    final statuses = [
      if (watching > 0) '${n.format(watching)} watching',
      if (completed > 0) '${n.format(completed)} completed',
      if (planned > 0) '${n.format(planned)} on your watchlist',
      if (dropped > 0) '${n.format(dropped)} dropped',
    ];
    final quiet = AppTheme.hankoSans(
      fontSize: AppTheme.hankoMetaSize,
      color: AppTheme.hankoStone,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 22, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(sentence, style: AppTheme.hankoSerif(fontSize: 17, height: 1.5)),
          if (statuses.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${statuses.join(', ')}.', style: quiet),
          ],
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('Top genres: ${_inList(genres)}.', style: quiet),
          ],
        ],
      ),
    );
  }

  /// "A", "A and B", "A, B and C".
  static String _inList(List<String> items) => items.length < 2
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

  /// Your ratings as Hanko's seal register (stage H5, item d; question 39):
  /// each score keeps its place on Hanj's 1–10 ruler in half steps, and how
  /// often you gave it becomes the size of its impression. Its caption
  /// sentence ("12 rated, average 8.9, most often 10.") sits above it.
  ///
  /// Ratings imported on another scale (D20: an 85 from a 100-point list)
  /// can't be placed on the ruler. The register leaves them out of the
  /// drawing and of the caption's numbers, and a line under it says how
  /// many. With no ratings at all, the register's own empty ruler says
  /// "No ratings yet." and no caption repeats it.
  Widget _buildRatings(List<double> ratings) {
    final offScale = ratings.where((r) {
      final step = (r * 2).round() / 2;
      return step < 1 || step > 10;
    }).length;
    final drawn = ratings.length - offScale;
    final register = HankoSealRegister.fromRatings(ratings);
    final quiet = AppTheme.hankoSans(
      fontSize: AppTheme.hankoMetaSize,
      color: AppTheme.hankoStone,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 26, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHead('Your ratings', bottom: drawn > 0 ? 8 : 12),
          if (drawn > 0) ...[
            Text(register.summary, style: quiet),
            const SizedBox(height: 10),
          ],
          // Only imported ratings: an empty ruler saying "No ratings yet."
          // would contradict the line below, so it is left out.
          if (drawn > 0 || offScale == 0) register,
          if (offScale > 0) ...[
            if (drawn > 0) const SizedBox(height: 8),
            Text(
              offScale == 1
                  ? '1 imported rating is on another scale, so it isn\'t '
                      'drawn here.'
                  : '$offScale imported ratings are on another scale, so '
                      'they aren\'t drawn here.',
              style: quiet,
            ),
          ],
        ],
      ),
    );
  }

  /// The avatar before Hanko: the picked character image, or the initial on
  /// one of eight stock gradients chosen in Edit Profile. Stage H5's monogram
  /// replaced it on Profile; kept as design history and a deletion
  /// candidate. Edit Profile still offers the colours.
  Widget _legacyAvatarTile(String initial) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        gradient: _avatarImageUrl == null
            ? LinearGradient(
                colors: _avatarGradients[_avatarColorIndex],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: _avatarImageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                _avatarImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Center(
                  child: Text(initial,
                      style: AppTheme.serif(
                          fontSize: 24,
                          weight: FontWeight.w700,
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

/// Your monogram (Hanko stage H5, item a): your initial pressed in your seal,
/// 64 px with Shippori at 30 as hanko.html draws it. A character picked in
/// Edit Profile takes its place, in the same square; if that image fails, the
/// seal shows instead. The name beside it says who this is, so it is left
/// out of the screen-reader tree.
class _Monogram extends StatelessWidget {
  const _Monogram({required this.initial, this.imageUrl});

  final String initial;
  final String? imageUrl;

  static const double size = 64;

  @override
  Widget build(BuildContext context) {
    final seal = HankoSeal(label: initial, size: size, fontSize: 30);
    final url = imageUrl;
    return ExcludeSemantics(
      child: url == null || url.isEmpty
          ? seal
          : ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              child: SizedBox.square(
                dimension: size,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => seal,
                ),
              ),
            ),
    );
  }
}

/// A Hanko section head (hanko.html's .sec-h): Shippori 16 in washi.
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.title, {this.bottom = 12});

  final String title;

  /// Space below the head; 8 where a caption follows it.
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Semantics(
        header: true,
        child: Text(title,
            style: AppTheme.hankoSerif(
                fontSize: AppTheme.hankoSectionSize, height: 1.3)),
      ),
    );
  }
}

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
        color: const Color(0xFF121110),
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
