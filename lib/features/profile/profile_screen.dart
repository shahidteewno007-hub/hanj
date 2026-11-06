import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../models/anime_model.dart';
import '../../models/hanj_shelves.dart';
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
import '../anime_detail/anime_detail_screen.dart';
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
          // The list's state (stage H5). Until the first snapshot the list
          // isn't known, and Profile claims nothing about it: no "0 titles"
          // for someone with a long list. A failed read says so.
          //
          // An empty answer from the device's cache counts as known. It
          // can't be told from an unread list, but every setState here
          // makes a new stream (getAnimeList() in build), and the listener
          // that replaces the first one answers from the cache at once and
          // never hears the server confirm an empty result (that change is
          // metadata only), so waiting for it left an empty list blank
          // forever. Only a first load offline with nothing cached could
          // say "Nothing logged yet." wrongly, as the old "0 Titles" did.
          final listFailed = snapshot.hasError;
          final listKnown = !listFailed && snapshot.hasData;

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
          // The entries themselves, for favourites (item c).
          final entries = <Map<String, dynamic>>[];

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            entries.add(data);
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
          final shelves = _shelves(entries);

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
                      // The identity tools are rows on the page now (question
                      // 55); see _identityToolsInMenu.
                      if (_identityToolsInMenu) ...[
                        _menuItem('cards', Icons.grid_view_rounded, 'Ranking Cards'),
                        _menuItem('stats', Icons.bar_chart_rounded, 'Advanced Stats'),
                        // 'Your Wrapped' is hidden during beta — a yearly recap
                        // has no meaningful data to show mid-year.
                        _menuItem('feed', Icons.dynamic_feed_rounded, 'Activity Feed'),
                        _menuItem('calendar', Icons.calendar_month_rounded, 'Anime Calendar'),
                        _menuItem('social', Icons.people_rounded, 'Social'),
                      ],
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

              // ── The list couldn't be read ────────────────
              if (listFailed)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-list-failed'),
                  child: _column(_buildListFailed()),
                ),

              // ── Favourites (Hanko stage H5, item c) ──────
              if (listKnown && totalAnime > 0)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-favourites'),
                  child: _column(_buildFavourites(_topRated(entries))),
                ),

              // ── The counts (Hanko stage H5, item e) ──────
              // In words, in place of the four stat tiles, "By status" and
              // "Top genres". With an empty list, the page's one sentence.
              if (listKnown)
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
              if (listKnown && totalAnime > 0)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-ratings'),
                  child: _column(_buildRatings(ratings)),
                ),

              // ── Recent diary (Hanko stage H5, item f) ────
              if (listKnown && totalAnime > 0)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-diary'),
                  child: _column(_buildDiary(_diary(entries))),
                ),

              // ── Shelves (Hanko stage H5, item g) ─────────
              // Only once a shelf exists: nothing in the app makes one
              // until stage H7, so for now this never shows.
              if (listKnown && shelves.isNotEmpty)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-shelves'),
                  child: _column(_buildShelves(shelves)),
                ),

              // ── The ways on from Profile ─────────────────
              // Quiet Hanko rows below the screen's one hairline, which
              // closes your record. Hanj Cards and Cadre came first (stage
              // H5); the identity tools joined them from the ⋮ menu
              // (question 55), each opening exactly what its menu entry
              // opened. Grouped by space alone, no headings: your record in
              // more depth; what you collect and play; then other people
              // and the season.
              //
              // Your taste leads them (question 57): the Taste card, now one
              // of these rows (taste_profile.dart), since taste comes first
              // on Profile (question 2). It reads your list itself, so it
              // shows once the list has titles, as the card did.
              SliverToBoxAdapter(
                key: const ValueKey('profile-section-c'),
                child: _column(Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.hankoGutter, 30, AppTheme.hankoGutter, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ColoredBox(
                        color: AppTheme.hankoHairline,
                        child: SizedBox(height: 1),
                      ),
                      const SizedBox(height: 10),
                      if (totalAnime > 0) ...[
                        const TasteProfileCard(
                            key: ValueKey('profile-taste')),
                        const SizedBox(height: _rowGap),
                      ],
                      _EntryRow(
                        icon: Icons.bar_chart_sharp,
                        title: 'Advanced Stats',
                        line: 'See your list in charts and numbers',
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const StatsScreen())),
                      ),
                      const SizedBox(height: _rowGap),
                      _EntryRow(
                        icon: Icons.dynamic_feed_sharp,
                        title: 'Activity Feed',
                        line: 'Look back at everything you\'ve logged',
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const ActivityFeedScreen())),
                      ),
                      const SizedBox(height: _groupGap),
                      // With the card out of the header (see
                      // _pinnedCardInHeader), the row names your pinned
                      // card in words, with no card art.
                      _EntryRow(
                        icon: Icons.style_sharp,
                        title: 'Hanj Cards',
                        line: _pinnedName.isEmpty
                            ? 'Collect rare cards by watching anime'
                            : 'Pinned: $_pinnedName',
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const CardCollectionScreen())),
                      ),
                      const SizedBox(height: _rowGap),
                      _EntryRow(
                        icon: Icons.grid_view_sharp,
                        title: 'Ranking Cards',
                        line: 'Save your Top 9 and taste as images',
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const RankingCardsScreen())),
                      ),
                      const SizedBox(height: _rowGap),
                      // Tier lists take Cadre's place among what you make
                      // and collect (Shahid, 2026-11-03). The screen and its
                      // /tierlist route are the tier-list feature's own.
                      _EntryRow(
                        icon: Icons.table_rows_sharp,
                        title: 'Tier lists',
                        line: 'Rank characters from god tier down',
                        onTap: () =>
                            Navigator.pushNamed(context, '/tierlist'),
                      ),
                      if (_cadreRow) ...[
                        const SizedBox(height: _rowGap),
                        _EntryRow(
                          icon: Icons.local_fire_department_sharp,
                          title: 'Cadre',
                          line: 'Draft a deck from any cast and clash',
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                              builder: (_) => const CadreLobbyScreen())),
                        ),
                      ],
                      const SizedBox(height: _groupGap),
                      _EntryRow(
                        icon: Icons.people_sharp,
                        title: 'Social',
                        line: 'Compare your taste with a friend\'s',
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const SocialScreen())),
                      ),
                      const SizedBox(height: _rowGap),
                      _EntryRow(
                        icon: Icons.calendar_month_sharp,
                        title: 'Anime Calendar',
                        line: 'See what airs next, day by day',
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => const AnimeCalendarScreen())),
                      ),
                    ],
                  ),
                )),
              ),

              // ── Founder Card (first 50 users only) ───────
              // Moved below the record (stage H5): the Founder pill stays
              // under the name, and the full card no longer pushes the
              // record out of the first screen. Collapsed to a short note,
              // the page's last word (question 57, founder_card.dart).
              // Until status is known the placeholder stands in; in Hanko it
              // reserves nothing, since nothing sits below the note.
              if (!_founderResolved)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-founder'),
                  child: _column(const FounderCardPlaceholder()),
                )
              else if (_founderStatus.isFounder)
                SliverToBoxAdapter(
                  key: const ValueKey('profile-founder'),
                  child: _column(FounderCard(status: _founderStatus)),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        );
        },
      ),
    );
  }

  /// Ranking Cards, Advanced Stats, Activity Feed, Anime Calendar and Social
  /// sat behind the unlabelled ⋮ menu, where most people never find them.
  /// Since question 55 they are rows on the page instead, and the menu keeps
  /// Notifications, More and Sign Out. Their entries and routes are kept
  /// here, switched off, so the menu's history stays readable; switching
  /// this on would list each tool twice.
  static const bool _identityToolsInMenu = false;

  /// The counts closed with "Top genres: A, B and C." until question 71.
  /// The Taste row below says the same thing, as the first of the ways on
  /// from Profile, so the line is kept here, switched off, rather than
  /// said twice on one page.
  static const bool _genresInCounts = false;

  /// Your pinned Hanj Card stood beside your name in the header (stage H5,
  /// item b) until Shahid's call of 2026-10-29. It was the loudest thing on
  /// a calm page, its frame and glow competing with your name and your
  /// seal; it pushed the name onto two lines; it was Profile's costliest
  /// frame to paint (PERF.md S2-3); and the Hanj Cards row below already
  /// leads to the collection. So the header gives your name the whole
  /// width, and that row names your pinned card in words. The card's code
  /// is kept below (_pinnedCard), switched off here.
  static const bool _pinnedCardInHeader = false;

  /// Cadre's row, "Draft a deck from any cast and clash", stood where the
  /// Tier lists row is until Shahid's call of 2026-11-03: "Maybe add a new
  /// feature instead of cadre where you make your tier list". The row is
  /// kept here, switched off, and Cadre itself (lib/cadre/ and its /cadre
  /// route) is untouched.
  static const bool _cadreRow = false;

  /// Space between the rows below the hairline: 4 between rows in a group,
  /// as H5 set it, and 16 between groups, so the groups read without
  /// headings.
  static const double _rowGap = 4;
  static const double _groupGap = 16;

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
  /// sliver beside the seal. A word too long for even the whole column sets
  /// the name a little smaller (_nameScaler), so it is never broken.
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
                style: _nameStyle,
                textScaler: _nameScaler(context, name, constraints.maxWidth)),
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
      // Beside the monogram when there are 200 px there and the name's
      // longest word fits them; otherwise under it.
      final room = constraints.maxWidth - _Monogram.size - 14;
      final beside = room >= 200 && _longestWord(context, name) <= room;
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

    final card = _pinnedCardInHeader ? _featuredCard : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 4, AppTheme.hankoGutter, 0),
      // Switched off (_pinnedCardInHeader): your pinned Hanj Card stood
      // beside your name (item b), as hanko.html places it, at the right of
      // the header. When the column left beside it couldn't hold the name's
      // longest word (large text, a long name), the card moved under the
      // name instead, so no word was ever broken in the middle.
      child: card == null
          ? editable
          : LayoutBuilder(builder: (context, constraints) {
              const cardWidth = hc.HanjCard.kWidth * _pinnedScale;
              final column = constraints.maxWidth - 16 - cardWidth;
              if (_longestWord(context, name) > column) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    editable,
                    const SizedBox(height: 16),
                    _pinnedCard(card),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: editable),
                  const SizedBox(width: 16),
                  _pinnedCard(card),
                ],
              );
            }),
    );
  }

  /// How wide the name's longest word sets, at the text size in use (or at
  /// [scaler]), so the header can keep every word whole. A line may break
  /// after a hyphen, so "Kristoffersen-Okonkwo" counts as two words.
  static double _longestWord(BuildContext context, String name,
      {TextScaler? scaler}) {
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: scaler ?? MediaQuery.textScalerOf(context),
      maxLines: 1,
    );
    var longest = 0.0;
    for (final word in name.replaceAll('-', '- ').split(RegExp(r'\s+'))) {
      painter
        ..text = TextSpan(text: word, style: _nameStyle)
        ..layout();
      if (painter.width > longest) longest = painter.width;
    }
    painter.dispose();
    return longest;
  }

  /// The text size for the name in a column [width] wide: the reader's own,
  /// unless the name's longest word is wider than the whole column even on
  /// a line of its own, as a long surname can be at 2.0x. Then the whole
  /// name is set just small enough for that word to fit, so no word is ever
  /// broken in the middle (question 76). Every name that fits keeps the
  /// reader's size exactly.
  static TextScaler _nameScaler(
      BuildContext context, String name, double width) {
    final reader = MediaQuery.textScalerOf(context);
    if (width <= 0) return reader;
    final longest = _longestWord(context, name);
    if (longest <= width) return reader;
    // A word's width grows in step with its size. Start from the size that
    // should just fit, rounded down to a half pixel, and step down until
    // the word measures inside the column.
    final size = _nameStyle.fontSize!;
    var fitted = (reader.scale(size) * width / longest * 2).floorToDouble() / 2;
    while (fitted > 1 &&
        _longestWord(context, name,
                scaler: TextScaler.linear(fitted / size)) >
            width) {
      fitted -= 0.5;
    }
    return TextScaler.linear((fitted < 1 ? 1 : fitted) / size);
  }

  /// The name's style: Shippori 28, as hanko.html sets it.
  static final TextStyle _nameStyle =
      AppTheme.hankoSerif(fontSize: 28, height: 1.15);

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

  /// Your pinned card's name, as the Hanj Cards row says it ("Pinned: The
  /// Critic"), or '' when no card is pinned.
  String get _pinnedName {
    final card = _featuredCard;
    if (card == null) return '';
    return ((card['name'] ?? card['cardName']) as String?) ?? '';
  }

  Widget _pinnedCard(Map<String, dynamic> card) {
    final name = ((card['name'] ?? card['cardName']) as String?) ?? '';
    // One screen-reader button with a tap and focus, as the favourites'
    // covers (question 104; see _favourite), with its focus seen on the
    // card (question 155; see _CoverButton).
    return _CoverButton(
      label: name.isEmpty
          ? 'Your pinned Hanj Card'
          : 'Your pinned Hanj Card, $name',
      hint: 'Opens your collection',
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const CardCollectionScreen())),
      // Square corners: HanjCard is square by design
      // (_CardShell paints square, HanjCard clips with
      // ClipRect). This was the only place one got
      // rounded off.
      radius: 0,
      child: ClipRect(
        child: SizedBox(
          width:  hc.HanjCard.kWidth  * _pinnedScale,
          height: hc.HanjCard.kHeight * _pinnedScale,
          // Render the card at its natural 200x300 and scale the
          // whole thing down. The card has fixed-pixel internals
          // (footer text, paddings) that don't shrink on their own,
          // so sizing it directly overflows at small sizes.
          // The card is drawn like a picture, so the text-size setting
          // doesn't reach inside it: at 1.3x its footer wrapped and was
          // cut off. Its name is in the spoken label above.
          child: FittedBox(
            fit: BoxFit.contain,
            child: MediaQuery.withNoTextScaling(
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

  /// Favourites (Hanko stage H5, item c; question 26): three covers across,
  /// filled from your top-rated shows, since hand-picking them needs a
  /// field on your user document that isn't approved yet. They are the art
  /// for "what you chose", so they carry no words; the aside says how they
  /// were chosen, and each says its title and rating to a screen reader.
  ///
  /// Three across fill the column: 101 x 143 on a 360 px phone, at the
  /// covers' own 230 : 325, so nothing is cropped. Fewer than three rated:
  /// the rest are empty dashed slots, Hanko's mark for "not yet". None: the
  /// three slots and a line saying how to fill them. A cover opens its show.
  Widget _buildFavourites(List<Map<String, dynamic>> favourites) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 26, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHead('Favourites', aside: 'Your highest rated'),
          LayoutBuilder(builder: (context, constraints) {
            const gap = 8.0;
            final width = (constraints.maxWidth - 2 * gap) / 3;
            final height = width * 325 / 230;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: gap),
                  if (i < favourites.length)
                    _favourite(favourites[i], width, height)
                  else
                    HankoSeal.unrated(
                      size: height,
                      width: width,
                      showAdd: false,
                      semanticLabel: 'Empty favourite',
                    ),
                ],
              ],
            );
          }),
          if (favourites.isEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Rate shows on their pages to fill these.',
              style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoMetaSize,
                color: AppTheme.hankoStone,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A favourite's cover is one screen-reader button (question 104): its
  /// own semantics node (container), named by its label, with the InkWell's
  /// tap and focus inside it, so a screen reader can press it and, on the
  /// web, it can take focus. A label over excluded semantics made a node
  /// with neither. The cover is left out of the tree, since the label names
  /// the show. Its ink lies over the art, so focus shows (question 155;
  /// see _CoverButton).
  Widget _favourite(Map<String, dynamic> entry, double width, double height) {
    final title = entry['title'] as String? ?? 'Unknown';
    final rating = HankoSeal.formatScore((entry['userRating'] as num).toDouble());
    return _CoverButton(
      label: 'Favourite: $title, your rating $rating',
      onTap: () => _openEntry(entry),
      child: _Cover(
          url: entry['imageUrl'] as String?, width: width, height: height),
    );
  }

  /// Your top three for Favourites. Candidates are shows you rated on
  /// Hanj's 1–10 scale that you are watching or have finished: a show on
  /// your watchlist isn't seen yet, a dropped one isn't a favourite, and an
  /// imported rating on another scale (D20) can't be compared. Ties break
  /// in this order:
  ///  1. the higher rating;
  ///  2. a finished show before one still in progress, since a verdict on
  ///     the whole show is the firmer one;
  ///  3. the more recent rating, with undated ones (imports) last;
  ///  4. the title, A to Z, so the order never shuffles between visits.
  static List<Map<String, dynamic>> _topRated(
      List<Map<String, dynamic>> entries) {
    final rated = [
      for (final e in entries)
        if (e['userRating'] is num &&
            _onScale((e['userRating'] as num).toDouble()) &&
            (e['status'] == 'COMPLETED' || e['status'] == 'WATCHING'))
          e,
    ];
    rated.sort((a, b) {
      final byRating =
          (b['userRating'] as num).compareTo(a['userRating'] as num);
      if (byRating != 0) return byRating;
      final aDone = a['status'] == 'COMPLETED', bDone = b['status'] == 'COMPLETED';
      if (aDone != bDone) return aDone ? -1 : 1;
      final aAt = _when(a['ratedAt']), bAt = _when(b['ratedAt']);
      if (aAt != bAt) {
        if (aAt == null) return 1;
        if (bAt == null) return -1;
        final byDate = bAt.compareTo(aAt);
        if (byDate != 0) return byDate;
      }
      return ((a['title'] as String?) ?? '')
          .toLowerCase()
          .compareTo(((b['title'] as String?) ?? '').toLowerCase());
    });
    return rated.take(3).toList();
  }

  /// The recent diary (Hanko stage H5, item f): your latest dated moments,
  /// newest first, five at most. It is partial until the list keeps watch
  /// dates (question 27), so each row says only what its date can prove:
  ///  - "Rated": the date of your rating (ratedAt), with your seal.
  ///  - "Updated": lastWatched, which adds, status changes, imports and
  ///    episodes all write, so it can't say which; the row adds what the
  ///    show is now ("now watching, 7 of 28").
  /// An update within six hours of the rating is the same sitting (you
  /// finished it and sealed it), so only the rating shows. More than three
  /// updates on one day read as one batch row ("148 titles updated"), the
  /// shape an import leaves, rather than filling the diary with it.
  /// Entries with neither date (a write still pending, or an older entry)
  /// can't be placed in time and are left out.
  Widget _buildDiary(List<_DiaryItem> items) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 26, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHead('Recent diary'),
          if (items.isEmpty)
            Text(
              'Nothing dated yet.',
              style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoMetaSize,
                color: AppTheme.hankoStone,
                height: 1.4,
              ),
            ),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _DiaryRow(
              item: items[i],
              onTap: items[i].entry == null
                  ? null
                  : () => _openEntry(items[i].entry!),
            ),
          ],
        ],
      ),
    );
  }

  static List<_DiaryItem> _diary(List<Map<String, dynamic>> entries) {
    final items = <_DiaryItem>[];
    final updated = <_DiaryItem>[];
    for (final e in entries) {
      final ratedAt = e['userRating'] is num ? _when(e['ratedAt']) : null;
      final updatedAt = _when(e['lastWatched']);
      if (ratedAt != null) items.add(_DiaryItem(ratedAt, e, rated: true));
      if (updatedAt != null &&
          (ratedAt == null ||
              updatedAt.difference(ratedAt).abs() > const Duration(hours: 6))) {
        updated.add(_DiaryItem(updatedAt, e, rated: false));
      }
    }
    final byDay = <DateTime, List<_DiaryItem>>{};
    for (final u in updated) {
      byDay
          .putIfAbsent(DateTime(u.at.year, u.at.month, u.at.day), () => [])
          .add(u);
    }
    for (final day in byDay.values) {
      if (day.length > 3) {
        final latest =
            day.map((u) => u.at).reduce((a, b) => a.isAfter(b) ? a : b);
        items.add(_DiaryItem(latest, null, rated: false, count: day.length));
      } else {
        items.addAll(day);
      }
    }
    items.sort((a, b) => b.at.compareTo(a.at));
    return items.take(5).toList();
  }

  /// Shelves (Hanko stage H5, item g): your list entries grouped by their
  /// tags, the field the tags API writes (firestore_service.dart's
  /// updateTags), read from the list Profile already has, so it costs no
  /// request. Shelving an anime arrives in round seven's Home; until a list
  /// has a tag this section doesn't show, and it promises nothing in the
  /// meantime. It sits under the privacy line the repo rules call for: list
  /// entries are readable by any signed-in user (firestore.rules,
  /// animeList).
  ///
  /// Since 2026-11-05 only Masterpiece and Favourites, in that order
  /// (_shelves), each drawn as a reel of all its covers on a ledge
  /// (_shelfReel). The line counting more shelves past three no longer
  /// shows.
  Widget _buildShelves(List<_Shelf> shelves) {
    final quiet = AppTheme.hankoSans(
      fontSize: AppTheme.hankoLabelSize,
      color: AppTheme.hankoStone,
      height: 1.35,
    );
    final more = shelves.length - 3;
    // The words keep the gutter on both sides; a reel runs on to the
    // column's right edge.
    Widget gutter(Widget child) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
          child: child,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gutter(const _SectionHead('Shelves', bottom: 8)),
          gutter(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.visibility_sharp,
                    size: 16, color: AppTheme.hankoStone),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Shelves are visible to signed-in Hanj users.',
                    style: quiet),
              ),
            ],
          )),
          const SizedBox(height: 14),
          for (var i = 0; i < shelves.length && i < 3; i++) ...[
            if (i > 0) const SizedBox(height: _shelvesAsReels ? 22 : 18),
            _shelvesAsReels
                ? _shelfReel(shelves[i], quiet)
                : gutter(_shelf(shelves[i], quiet)),
          ],
          if (more > 0) ...[
            const SizedBox(height: 14),
            gutter(Text(
                more == 1 ? 'and 1 more shelf' : 'and $more more shelves',
                style: quiet)),
          ],
        ],
      ),
    );
  }

  /// Shelves as reels on a ledge (round seven: Shahid asked for richer
  /// designs than "letters with black background"). H5's shelf, three
  /// 64 x 90 posters and "and N more" as hanko.html drew it, is kept as
  /// _shelf, switched off here.
  static const bool _shelvesAsReels = true;

  /// A shelf as a reel: its name and how many titles it holds, then every
  /// cover on it, newest first, 78 x 110 at the covers' own 230 : 325,
  /// standing side by side on a ledge (an edge-colour lip on a sumi 3
  /// board, with a soft shade under it). The reel scrolls sideways and runs
  /// on to the column's right edge, so a long shelf shows that it goes on;
  /// the ledge stays put while the covers slide along it. Each cover opens
  /// its show and shows keyboard focus, as Favourites' do (_CoverButton).
  /// No blur and no new reads: the covers are the list's own.
  Widget _shelfReel(_Shelf shelf, TextStyle quiet) {
    const coverWidth = 78.0, coverHeight = 110.0;
    // Room around the covers for the focus ring, 3 px outside the art,
    // which the reel's clip would otherwise cut.
    const ringRoom = 4.0;
    const lip = 1.0, board = 4.0, shade = 6.0;
    final count = shelf.entries.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(shelf.name,
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoListTitleSize, height: 1.25)),
                Text(count == 1 ? '1 title' : '$count titles', style: quiet),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10 - ringRoom),
        SizedBox(
          height: ringRoom + coverHeight + lip + board + shade,
          child: Stack(
            children: [
              // The ledge, from the gutter to the column's edge.
              const Positioned(
                left: AppTheme.hankoGutter,
                right: 0,
                top: ringRoom + coverHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ColoredBox(
                      color: AppTheme.hankoEdge,
                      child: SizedBox(height: lip),
                    ),
                    ColoredBox(
                      color: AppTheme.hankoSumi3,
                      child: SizedBox(height: board),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Color(0x00000000)],
                        ),
                      ),
                      child: SizedBox(height: shade),
                    ),
                  ],
                ),
              ),
              ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.hankoGutter, ringRoom, AppTheme.hankoGutter, 0),
                itemCount: count,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) => Align(
                  alignment: Alignment.topCenter,
                  child: _CoverButton(
                    label: (shelf.entries[i]['title'] as String?) ?? 'Unknown',
                    onTap: () => _openEntry(shelf.entries[i]),
                    child: _Cover(
                      url: shelf.entries[i]['imageUrl'] as String?,
                      width: coverWidth,
                      height: coverHeight,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// H5's shelf (hanko.html): the name and count, then the first three
  /// covers at 64 x 90 and "and N more". Switched off by _shelvesAsReels.
  Widget _shelf(_Shelf shelf, TextStyle quiet) {
    final count = shelf.entries.length;
    final rest = count - 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(shelf.name,
                  style: AppTheme.hankoSerif(
                      fontSize: AppTheme.hankoListTitleSize, height: 1.25)),
              Text(count == 1 ? '1 title' : '$count titles', style: quiet),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < count && i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              // One screen-reader button with a tap and focus, as the
              // favourites' covers (question 104; see _favourite), with
              // its focus seen on the art (question 155).
              _CoverButton(
                label: (shelf.entries[i]['title'] as String?) ?? 'Unknown',
                onTap: () => _openEntry(shelf.entries[i]),
                child: _Cover(
                  url: shelf.entries[i]['imageUrl'] as String?,
                  width: 64,
                  height: 90,
                ),
              ),
            ],
            if (rest > 0)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text('and $rest more', style: quiet),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// The two shelves (HanjShelves), Masterpiece then Favourites, each with
  /// its entries in the list's order. An entry sits on one at most. Tags
  /// from before that rule are read, not rewritten: any spelling of
  /// Favourites counts as it, every other name is hidden, and an entry
  /// tagged with both is under Masterpiece only. An empty shelf isn't shown.
  static List<_Shelf> _shelves(List<Map<String, dynamic>> entries) {
    final byShelf = {
      for (final name in HanjShelves.all) name: <Map<String, dynamic>>[],
    };
    for (final e in entries) {
      final shelf = HanjShelves.shelfOf(e['tags']);
      if (shelf != null) byShelf[shelf]!.add(e);
    }
    return [
      for (final name in HanjShelves.all)
        if (byShelf[name]!.isNotEmpty) _Shelf(name, byShelf[name]!),
    ];
  }

  /// Whether a stored rating lands on Hanj's 1–10 scale at its nearest
  /// half step, as the seal register places it.
  static bool _onScale(double rating) {
    final step = (rating * 2).round() / 2;
    return step >= 1 && step <= 10;
  }

  /// A Firestore timestamp as a date; null when missing or still pending.
  static DateTime? _when(Object? value) =>
      value is Timestamp ? value.toDate() : null;

  /// Opens a list entry's show, as My List's rows do.
  void _openEntry(Map<String, dynamic> data) {
    final id = data['animeId']?.toString() ?? '';
    if (id.isEmpty) return;
    final anime = Anime(
      id: id,
      title: data['title'] as String? ?? 'Unknown',
      imageUrl: data['imageUrl'] as String?,
      episodes: (data['episodes'] as num?)?.toInt(),
      genres: (data['genres'] as List<dynamic>?)?.whereType<String>().toList() ??
          const [],
      averageScore: (data['averageScore'] as num?)?.toDouble(),
    );
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)));
  }

  /// The counts you can trust now (Hanko stage H5, item e), in words: titles
  /// all time and episodes, as one sentence in Shippori, then the statuses
  /// in Jost. "This year" and hours wait for completion dates and episode
  /// lengths, which the list doesn't keep (question 27). The top genres
  /// left this block (question 71): the Taste row a little further down
  /// already names them; see _genresInCounts.
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
    // Each number keeps its word here too (question 110): a no-break space
    // joins them, so the sentence never ends a line on a number whose word
    // went on to the next ("23 / titles" at 2.0x), as the statuses below.
    String count(int value, String one, String many) =>
        '${n.format(value)}\u00A0${value == 1 ? one : many}';

    // The sentence is Shippori, which draws the typewriter apostrophe as a
    // straight tick, so "You’ve" takes the typographic one (as the failure
    // line below, question 109). "and watched" is joined by a no-break
    // space too (question 125): with each count glued to its word, at 2.0x
    // "watched" sat alone on a line before "318 episodes".
    final sentence = titles == 0
        ? 'Nothing logged yet.'
        : episodes == 0
            ? 'You’ve logged ${count(titles, 'title', 'titles')}.'
            : 'You’ve logged ${count(titles, 'title', 'titles')} '
                'and\u00A0watched ${count(episodes, 'episode', 'episodes')}.';
    // Each number keeps its word (question 89): a no-break space joins
    // them, so a line never ends on a number whose word went on to the
    // next line ("1 / dropped.").
    final statuses = [
      if (watching > 0) '${n.format(watching)}\u00A0watching',
      if (completed > 0) '${n.format(completed)}\u00A0completed',
      if (planned > 0) '${n.format(planned)}\u00A0on your watchlist',
      if (dropped > 0) '${n.format(dropped)}\u00A0dropped',
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
          if (titles == 0) ...[
            const SizedBox(height: 6),
            Text('Add a show from Discover or Search to start your journal.',
                style: quiet),
          ],
          if (statuses.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${statuses.join(', ')}.', style: quiet),
          ],
          if (_genresInCounts && genres.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('Top genres: ${_inList(genres)}.', style: quiet),
          ],
        ],
      ),
    );
  }

  /// The list couldn't be read: say so, naming no cause the app can't
  /// verify (ANILIST-OFFLINE-0908-REPORT.md's rule), rather than showing an
  /// empty record. Retry rebuilds, which listens to the list afresh.
  ///
  /// The line takes the typographic apostrophe (question 109): Shippori
  /// draws the typewriter one as a straight tick, as the Taste page found.
  Widget _buildListFailed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 22, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Couldn’t load your list just now.',
              style: AppTheme.hankoSerif(fontSize: 17, height: 1.5)),
          const SizedBox(height: 12),
          _TextTile(label: 'Retry', onTap: () => setState(() {})),
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
    final offScale = ratings.where((r) => !_onScale(r)).length;
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

/// A Hanko section head (hanko.html's .sec-h): Shippori 16 in washi, with
/// an optional aside in Jost 12 stone at the line's end. The aside wraps
/// under the head when the line is too short, so large text never pushes
/// it off the edge.
class _SectionHead extends StatelessWidget {
  const _SectionHead(this.title, {this.aside, this.bottom = 12});

  final String title;
  final String? aside;

  /// Space below the head; 8 where a caption follows it.
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final aside = this.aside;
    final head = Semantics(
      header: true,
      child: Text(title,
          style: AppTheme.hankoSerif(
              fontSize: AppTheme.hankoSectionSize, height: 1.3)),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      // The Wrap takes the full width, or it would shrink to its children
      // and spaceBetween would leave the aside beside the head.
      child: aside == null
          ? head
          : SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                runSpacing: 2,
                children: [
                  head,
                  Text(aside,
                      style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoLabelSize,
                        color: AppTheme.hankoStone,
                        height: 1.3,
                      )),
                ],
              ),
            ),
    );
  }
}

/// A cover from the list entry's stored URL (AniList's `large`, 230 px
/// wide), with Hanko's 2 px corners on a sumi 3 ground, which is also what
/// shows while it loads or when it fails.
class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.width, required this.height});

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: ColoredBox(
          color: AppTheme.hankoSumi3,
          child: u == null || u.isEmpty
              ? const SizedBox.expand()
              : CachedNetworkImage(
                  imageUrl: u,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.expand(),
                ),
        ),
      ),
    );
  }
}

/// Art that opens something: a favourite's or a shelf's cover, or the
/// pinned card. One screen-reader button (question 104), named by [label],
/// with the InkWell's tap and focus in its node and the art left out of the
/// tree.
///
/// The InkWell used to wrap the art, so its ink was painted on the Material
/// below it, under an opaque picture, and keyboard focus on a cover could
/// not be seen (question 155). Now the ink lies over the art, on a
/// transparent Material: focus shows the theme's focus wash on the art and,
/// for a keyboard, a 1 px washi ring 3 px outside it, as the rating ruler
/// rings its own (a finger's tap draws none). Press and hover take Hanko's
/// 8% wash, which the art used to hide too.
class _CoverButton extends StatefulWidget {
  const _CoverButton({
    required this.label,
    required this.onTap,
    required this.child,
    this.hint,
    this.radius = AppTheme.hankoRadius,
  });

  final String label;
  final String? hint;
  final VoidCallback onTap;
  final Widget child;

  /// The art's corner radius, so the ink and the ring follow its shape: a
  /// cover's 2 px, or 0 for a Hanj Card, which is square.
  final double radius;

  @override
  State<_CoverButton> createState() => _CoverButtonState();
}

class _CoverButtonState extends State<_CoverButton> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  // A switch between keyboard and touch shows or hides the ring at once.
  void _onHighlightMode(FocusHighlightMode _) {
    if (_focused && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ring = _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      hint: widget.hint,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ExcludeSemantics(child: widget.child),
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                onFocusChange: (focused) => setState(() => _focused = focused),
                splashFactory: NoSplash.splashFactory,
                highlightColor: AppTheme.hankoPressWash,
                hoverColor: AppTheme.hankoPressWash,
                borderRadius: BorderRadius.circular(widget.radius),
              ),
            ),
          ),
          if (ring)
            Positioned(
              left: -3,
              top: -3,
              right: -3,
              bottom: -3,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.hankoWashi),
                    borderRadius: BorderRadius.circular(widget.radius + 3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A way on from Profile (Hanj Cards, Cadre and, since question 55, the
/// identity tools from the ⋮ menu) as a quiet Hanko row: an icon in stone,
/// the name in Jost 15 500 washi, a line in Jost 13 stone and a chevron.
/// No box, no glow, no colour of its own: coral now means your
/// seal, so neither the gold nor the coral banner it replaces survives. At
/// least 56 px tall, pressed with the 8% wash.
///
/// One screen-reader button (question 104): its own semantics node
/// (container), named by its title and its line, with the InkWell's tap
/// and focus inside it, so a screen reader can open the row and, on the
/// web, it can take focus. The label used to sit over excluded semantics,
/// which left the row's node with neither: a screen reader found the row
/// but had no tap to send it. The row's own words are left out of the
/// tree, since the label already says them.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.icon,
    required this.title,
    required this.line,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: '$title. $line',
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: AppTheme.hankoStone),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: AppTheme.hankoSans(
                                fontSize: 15,
                                weight: FontWeight.w500,
                                height: 1.25)),
                        const SizedBox(height: 2),
                        Text(line,
                            style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              color: AppTheme.hankoStone,
                              height: 1.3,
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.chevron_right_sharp,
                      size: 20, color: AppTheme.hankoStone),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A Shippori title on up to [maxLines] lines whose last line fades out at
/// its end when the title runs longer, instead of an ellipsis: Shippori
/// draws "…" as the centred Japanese ⋯ (AppTheme.hankoSerif). Flutter's own
/// TextOverflow.fade on a multi-line Text fades the bottom half of the last
/// line instead, so the title is split after its last full line and that
/// line is set on its own, one line with TextOverflow.fade.
///
/// The same as Home's (stage H4, home_screen.dart on its branch), which this
/// file can't import: widgets are private to their file, and a shared one
/// needs its own approval. It finds the last line's start with
/// getPositionForOffset, because on CanvasKit getLineBoundary at a line's
/// first offset answers with the line before (H4's emulator run).
class _FadeTitle extends StatelessWidget {
  const _FadeTitle(this.text, {required this.style, required this.maxLines});

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: constraints.maxWidth);
      final overflows = painter.didExceedMaxLines;
      final lines = overflows ? painter.computeLineMetrics() : null;
      final lastStart = lines == null || lines.length < maxLines
          ? 0
          : painter
              .getPositionForOffset(Offset(
                  0, lines[maxLines - 1].baseline - lines[maxLines - 1].ascent / 2))
              .offset;
      painter.dispose();
      if (!overflows || lastStart <= 0) {
        return Text(text,
            style: style,
            maxLines: maxLines,
            softWrap: maxLines > 1,
            overflow: TextOverflow.fade);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text.substring(0, lastStart).trimRight(),
              style: style, maxLines: maxLines - 1),
          Text(text.substring(lastStart).trimLeft(),
              style: style,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade),
        ],
      );
    });
  }
}

/// A Hanko secondary tile with a word on it ("Retry"), as Home's: sumi 3
/// with a 1 px edge outline, Jost 600 15 washi, 48 dp tall. Its own
/// semantics node (container; question 102, as the Calendar's and
/// Activity's tiles since dd45bd1), so a screen reader finds one button
/// named for its word, with its own tap, wherever the tile is placed. Here
/// the page already gave it a node of its own (checked on 2026-10-30); in
/// the Calendar's and Activity's notes, a tile without it folded into the
/// note, which then read as one long button.
class _TextTile extends StatelessWidget {
  const _TextTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: AppTheme.hankoSumi3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          side: const BorderSide(color: AppTheme.hankoEdge),
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Text(
                  label,
                  style: AppTheme.hankoSans(
                      fontSize: 15, weight: FontWeight.w600, height: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A shelf: one of your tags and the list entries that carry it.
class _Shelf {
  const _Shelf(this.name, this.entries);

  final String name;
  final List<Map<String, dynamic>> entries;
}

/// One line of the recent diary: a rating, an update, or a day's batch of
/// updates ([entry] null, [count] titles).
class _DiaryItem {
  const _DiaryItem(this.at, this.entry, {required this.rated, this.count = 1});

  final DateTime at;
  final Map<String, dynamic>? entry;
  final bool rated;
  final int count;
}

/// A diary row (hanko.html's .pdia): the day and the weekday (or the year,
/// before this one) in Jost, the cover at 30 x 42, the title in Shippori 15
/// on one line fading at its end, what the date means under it, and, on a
/// "Rated" row, your seal. The date column grows with the text size.
class _DiaryRow extends StatelessWidget {
  const _DiaryRow({required this.item, this.onTap});

  final _DiaryItem item;
  final VoidCallback? onTap;

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  /// "Updated · now watching, 7 of 28": lastWatched can't say what the
  /// update was, so the row says what the show is now. Each number keeps
  /// its words (question 131, question 110's rule): no-break spaces join
  /// "1 watched" and "7 of 28", so a line never ends on the number and
  /// leaves "watched" alone on the next.
  static String _updatedLine(Map<String, dynamic> e) {
    final current = (e['currentEpisode'] as num?)?.toInt() ?? 0;
    final total = (e['episodes'] as num?)?.toInt();
    final String? now = switch (e['status']) {
      'WATCHING' => total != null && total > 0
          ? 'watching, $current\u00A0of\u00A0$total'
          : 'watching, $current\u00A0watched',
      'COMPLETED' => 'completed',
      'PLAN_TO_WATCH' => 'on your watchlist',
      'DROPPED' => 'dropped',
      _ => null,
    };
    return now == null ? 'Updated' : 'Updated · now $now';
  }

  @override
  Widget build(BuildContext context) {
    final at = item.at;
    final thisYear = at.year == DateTime.now().year;
    final entry = item.entry;
    final title = entry == null
        ? '${NumberFormat.decimalPattern().format(item.count)} titles updated'
        : (entry['title'] as String?) ?? 'Unknown';
    final meta = entry == null
        ? null
        : item.rated
            ? 'Rated'
            : _updatedLine(entry);
    // Only a "Rated" row carries your seal (question 132). A list entry
    // keeps one rating, the latest (updateRating overwrites userRating and
    // ratedAt, and the activity log records no ratings), so an "Updated"
    // row can't know what your rating was on its day: a 29 Oct row showed
    // the 8.5 sealed on 30 Oct. It shows no seal rather than a later one.
    final rating = entry != null && item.rated && entry['userRating'] is num
        ? (entry['userRating'] as num).toDouble()
        : null;
    final spoken = [
      '${_weekdayNames[at.weekday - 1]} ${at.day} ${_monthNames[at.month - 1]}'
          '${thisYear ? '' : ' ${at.year}'}',
      if (entry == null) title else '${item.rated ? 'rated' : 'updated'} $title',
      if (entry != null && !item.rated) _updatedLine(entry).replaceFirst('Updated · ', ''),
      if (rating != null) 'your rating ${HankoSeal.formatScore(rating)}',
    ].join(', ');

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
      child: Row(
        children: [
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(46),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${at.day} ${_months[at.month - 1]}',
                  maxLines: 1,
                  softWrap: false,
                  style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoMetaSize,
                    weight: FontWeight.w500,
                    height: 1.15,
                    tabular: true,
                  ),
                ),
                Text(
                  thisYear ? _weekdays[at.weekday - 1] : '${at.year}',
                  maxLines: 1,
                  softWrap: false,
                  style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoDataSmallSize,
                    color: AppTheme.hankoAsh,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          entry == null
              ? const SizedBox(width: 30, height: 42)
              : _Cover(url: entry['imageUrl'] as String?, width: 30, height: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _FadeTitle(
                  title,
                  maxLines: 2,
                  style: AppTheme.hankoSerif(
                      fontSize: AppTheme.hankoListTitleSize, height: 1.25),
                ),
                if (meta != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    maxLines: 2,
                    overflow: TextOverflow.fade,
                    style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      color: AppTheme.hankoStone,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (rating != null) ...[
            const SizedBox(width: 12),
            HankoSeal.score(rating, size: 28),
          ],
        ],
      ),
    );

    // Its own semantics node (container), named by the spoken line. A row
    // that opens its show is a screen-reader button with the InkWell's tap
    // and focus inside it (question 104, as Profile's other rows); a batch
    // row ("148 titles updated") opens nothing and stays a plain line. The
    // label used to sit over excluded semantics, which dropped the InkWell's
    // tap and focus: a screen reader heard "button" with nothing to press.
    return Semantics(
      container: true,
      button: onTap != null,
      label: spoken,
      child: onTap == null
          ? ExcludeSemantics(child: row)
          : InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              child: ExcludeSemantics(child: row),
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
