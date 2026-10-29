import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme/app_theme.dart';
import '../../models/anime_model.dart';
import '../../services/anilist_service.dart';
import '../anime_detail/anime_detail_screen.dart';

// ─────────────────────────────────────────────────────────────
// Upcoming Anime Screen — full page
// ─────────────────────────────────────────────────────────────

class UpcomingAnimeScreen extends StatefulWidget {
  const UpcomingAnimeScreen({super.key});

  @override
  State<UpcomingAnimeScreen> createState() => _UpcomingAnimeScreenState();
}

class _UpcomingAnimeScreenState extends State<UpcomingAnimeScreen>
    with SingleTickerProviderStateMixin {
  final _anilist = AnilistService();
  late TabController _tabController;

  // ── Static cache so data survives screen rebuilds ──
  static List<Anime> _cachedThis = [];
  static List<Anime> _cachedNext = [];

  List<Anime> _thisSeasonAnime = [];
  List<Anime> _nextSeasonAnime = [];
  bool _isLoadingThis = true;
  bool _isLoadingNext = true;

  Set<String> _alertedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Seed from cache immediately — no blank flash
    if (_cachedThis.isNotEmpty) {
      _thisSeasonAnime = List.of(_cachedThis);
      _isLoadingThis = false;
    }
    if (_cachedNext.isNotEmpty) {
      _nextSeasonAnime = List.of(_cachedNext);
      _isLoadingNext = false;
    }

    _loadAnime();
    _loadAlerts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _currentSeason() {
    final month = DateTime.now().month;
    if (month >= 1 && month <= 3) return 'WINTER';
    if (month >= 4 && month <= 6) return 'SPRING';
    if (month >= 7 && month <= 9) return 'SUMMER';
    return 'FALL';
  }

  String _nextSeason() {
    final seasons = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
    final current = _currentSeason();
    final idx = seasons.indexOf(current);
    return seasons[(idx + 1) % 4];
  }

  int _nextSeasonYear() {
    final current = _currentSeason();
    if (current == 'FALL') return DateTime.now().year + 1;
    return DateTime.now().year;
  }

  Future<void> _loadAnime() async {
    final year = DateTime.now().year;
    final thisSeason = _currentSeason();
    final nextSeason = _nextSeason();
    final nextYear = _nextSeasonYear();

    // Only show spinner if we have no cached data to display
    if (_thisSeasonAnime.isEmpty && mounted) {
      setState(() => _isLoadingThis = true);
    }

    try {
      final this_ = await _anilist.getSeasonal(thisSeason, year);
      if (this_.isNotEmpty) {
        _cachedThis = this_; // update cache only on success
        if (mounted) setState(() { _thisSeasonAnime = this_; _isLoadingThis = false; });
      } else {
        // AniList returned empty — keep existing data, just stop spinner
        if (mounted) setState(() => _isLoadingThis = false);
      }
    } catch (_) {
      // Rate-limited or network error — keep existing data visible
      if (mounted) setState(() => _isLoadingThis = false);
    }

    // Stagger next-season call to avoid rate limiting
    await Future.delayed(const Duration(milliseconds: 400));

    if (_nextSeasonAnime.isEmpty && mounted) {
      setState(() => _isLoadingNext = true);
    }

    try {
      final next_ = await _anilist.getSeasonal(nextSeason, nextYear);
      if (next_.isNotEmpty) {
        _cachedNext = next_;
        if (mounted) setState(() { _nextSeasonAnime = next_; _isLoadingNext = false; });
      } else {
        if (mounted) setState(() => _isLoadingNext = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingNext = false);
    }
  }

  Future<void> _loadAlerts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('alerts').get();
      if (mounted) {
        setState(() {
          _alertedIds = doc.docs.map((d) => d.id).toSet();
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleAlert(Anime anime) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .collection('alerts').doc(anime.id);

    if (_alertedIds.contains(anime.id)) {
      try {
        await ref.delete();
      } catch (_) {
        _alertNotSaved(removing: true);
        return;
      }
      if (!mounted) return;
      setState(() => _alertedIds.remove(anime.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alert removed for ${anime.title}'),
            backgroundColor: AppTheme.surfaceMid,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      try {
        await ref.set({
          'animeId':    anime.id,
          'title':      anime.titleEnglish ?? anime.title,
          'imageUrl':   anime.imageUrl,
          'season':     anime.season,
          'seasonYear': anime.seasonYear,
          'addedAt':    FieldValue.serverTimestamp(),
        });
      } catch (_) {
        _alertNotSaved(removing: false);
        return;
      }
      if (!mounted) return;
      setState(() => _alertedIds.add(anime.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.notifications_active_rounded,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(
                    "You'll be notified when ${anime.titleEnglish ?? anime.title} airs!")),
              ],
            ),
            backgroundColor: AppTheme.surfaceMid,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Question 84, with question 83's pattern: a refused alert write (by the
  /// rules, say) is caught in _toggleAlert. Uncaught, it went to
  /// PlatformDispatcher.onError, which main.dart reports to Crashlytics as
  /// fatal. This bell only moves once its write has landed, so there is no
  /// bell to put back: it still shows what is saved, and no confirmation
  /// was shown. The message says so, naming no cause, in place of any
  /// message still showing, in this screen's own message style. Offline,
  /// the write waits for the connection, as before.
  void _alertNotSaved({required bool removing}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(removing
              ? "Couldn't remove the reminder. Try again."
              : "Couldn't set the reminder. Try again."),
          backgroundColor: AppTheme.surfaceMid,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Upcoming Anime',
            style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelStyle: AppTheme.mono(
              fontSize: 11, color: AppTheme.primary, letterSpacing: 1),
          unselectedLabelStyle: AppTheme.mono(
              fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1),
          tabs: [
            Tab(text: '${_currentSeason()} ${DateTime.now().year}'),
            Tab(text: '${_nextSeason()} ${_nextSeasonYear()}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAnimeGrid(_thisSeasonAnime, _isLoadingThis),
          _buildAnimeGrid(_nextSeasonAnime, _isLoadingNext),
        ],
      ),
    );
  }

  Widget _buildAnimeGrid(List<Anime> anime, bool isLoading) {
    if (isLoading && anime.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(
              color: AppTheme.primary, strokeWidth: 2));
    }

    if (anime.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today_rounded,
                color: AppTheme.textMuted, size: 48),
            const SizedBox(height: 16),
            Text('No anime found for this season',
                style: AppTheme.sans(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAnime,
      color: AppTheme.primary,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.62,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: anime.length,
        itemBuilder: (_, i) => _UpcomingCard(
          anime: anime[i],
          isAlerted: _alertedIds.contains(anime[i].id),
          onAlertToggle: () => _toggleAlert(anime[i]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Upcoming Card
// ─────────────────────────────────────────────────────────────

class _UpcomingCard extends StatelessWidget {
  final Anime anime;
  final bool isAlerted;
  final VoidCallback onAlertToggle;

  const _UpcomingCard({
    required this.anime,
    required this.isAlerted,
    required this.onAlertToggle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime))),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isAlerted
                ? AppTheme.primary.withValues(alpha: 0.5)
                : AppTheme.cardBorder,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Poster
              anime.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: anime.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                          color: AppTheme.surfaceLight,
                          child: const Icon(Icons.movie_outlined,
                              color: AppTheme.textMuted)),
                    )
                  : Container(color: AppTheme.surfaceLight),

              // Gradient overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ),

              // Alert button top right
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: onAlertToggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: isAlerted
                          ? AppTheme.primary
                          : Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isAlerted
                            ? AppTheme.primary
                            : Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      isAlerted
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ),

              // Season badge top left
              if (anime.season != null)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _seasonLabel(anime.season!),
                      style: AppTheme.mono(
                          fontSize: 9,
                          color: AppTheme.accent,
                          letterSpacing: 0.5),
                    ),
                  ),
                ),

              // Bottom info
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        anime.titleEnglish ?? anime.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (anime.genres.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          anime.genres.take(2).join(' · '),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 10,
                          ),
                        ),
                      ],
                      if (anime.averageScore != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded,
                                color: Colors.amber, size: 11),
                            const SizedBox(width: 3),
                            Text(
                              (anime.averageScore! / 10)
                                  .toStringAsFixed(1),
                              style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
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

  String _seasonLabel(String season) {
    switch (season) {
      case 'WINTER': return 'WINTER';
      case 'SPRING': return 'SPRING';
      case 'SUMMER': return 'SUMMER';
      case 'FALL':   return 'FALL';
      default:       return season;
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Home Screen Widget — compact upcoming row
// ─────────────────────────────────────────────────────────────

class UpcomingAnimeRow extends StatefulWidget {
  const UpcomingAnimeRow({super.key, this.skip = const {}});

  /// The shows Home's season chart already lists, by AniList id. The chart
  /// and this strip read the same request, the season's most popular shows
  /// (Hanko H4 f), so the strip leaves those out and starts after them
  /// (question 44). Matched by id, not by position: the chart's copy can be
  /// up to an hour older than this one and ranked a little differently, and
  /// when the chart couldn't load at all, nothing is skipped.
  final Set<String> skip;

  @override
  State<UpcomingAnimeRow> createState() => _UpcomingAnimeRowState();
}

class _UpcomingAnimeRowState extends State<UpcomingAnimeRow> {
  final _anilist = AnilistService();

  // ── Static cache — persists across home screen rebuilds ──
  static List<Anime> _cache = [];

  List<Anime> _anime = [];
  Set<String> _alertedIds = {};
  bool _isLoading = true;

  String _currentSeason() {
    final month = DateTime.now().month;
    if (month >= 1 && month <= 3) return 'WINTER';
    if (month >= 4 && month <= 6) return 'SPRING';
    if (month >= 7 && month <= 9) return 'SUMMER';
    return 'FALL';
  }

  @override
  void initState() {
    super.initState();

    // Show cached data immediately — no blank flash on rebuild
    if (_cache.isNotEmpty) {
      _anime = List.of(_cache);
      _isLoading = false;
    }

    _load();
  }

  Future<void> _load() async {
    try {
      final results = await _anilist.getSeasonal(
          _currentSeason(), DateTime.now().year);
      if (results.isNotEmpty) {
        // The whole page (up to 20): the strip shows ten once the chart's
        // shows are left out (widget.skip), so ten alone could fall short.
        _cache = List.of(results); // update cache only on success
        if (mounted) setState(() { _anime = _cache; _isLoading = false; });
      } else {
        // Empty response — keep existing data, just stop spinner
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      // Rate-limited or network error — keep cached data visible
      if (mounted) setState(() => _isLoading = false);
    }

    // Load alerts in parallel (non-blocking)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('alerts').get();
      if (mounted) setState(() => _alertedIds = doc.docs.map((d) => d.id).toSet());
    } catch (_) {}
  }

  Future<void> _toggleAlert(Anime anime) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('alerts').doc(anime.id);

    if (_alertedIds.contains(anime.id)) {
      await ref.delete();
      if (!mounted) return;
      setState(() => _alertedIds.remove(anime.id));
    } else {
      await ref.set({
        'animeId':    anime.id,
        'title':      anime.titleEnglish ?? anime.title,
        'imageUrl':   anime.imageUrl,
        'season':     anime.season,
        'seasonYear': anime.seasonYear,
        'addedAt':    FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _alertedIds.add(anime.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Alert set for ${anime.titleEnglish ?? anime.title}!'),
            backgroundColor: AppTheme.surfaceMid,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hanko (stage H4, item h; hanko.html's poster strip, .mlt): 72 × 102
    // covers with square 2 px corners on sumi 3 while they load, each title
    // under its cover in Jost 500 12 on up to two lines, and "See all" as a
    // quiet washi link in a 48 dp target. No coral and no arrow: in Hanko
    // coral is your seal, and nothing in this row is yours. The data, the
    // static cache and where each tap goes are as they were.
    final scaler = MediaQuery.textScalerOf(context);
    // The columns widen as the titles' text grows, so a long word still fits
    // one line: at 1.3x a 72 px column broke "Apothecary" mid-word. Tied to
    // the 12 px title's own growth (Android's large sizes scale non-linearly),
    // and never narrower than the frame's 72 px. The cover keeps 72 x 102.
    final grow = scaler.scale(12) / 12;
    final itemWidth = grow > 1 ? 72 * grow : 72.0;
    final coverHeight = itemWidth * 102 / 72;
    // Two lines of title at the reader's text size, so the strip grows with
    // large text instead of cutting the titles' second line.
    final stripHeight = coverHeight + 6 + scaler.scale(12) * 1.25 * 2 + 4;

    if (_isLoading && _anime.isEmpty) {
      // The size the loaded block takes, so nothing below jumps when it
      // arrives.
      return SizedBox(
        height: AppTheme.hankoTouch + stripHeight,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
                color: AppTheme.hankoWashi, strokeWidth: 1.5),
          ),
        ),
      );
    }

    // The season after the chart's shows (widget.skip), ten at most. A short
    // season that the chart already shows in full leaves nothing, and the
    // block is left out, as when the request failed with nothing saved.
    final shown =
        _anime.where((a) => !widget.skip.contains(a.id)).take(10).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          // The link's 8 px of padding sits in the gutter, so its word
          // lines up with the gutter edge.
          padding: const EdgeInsets.fromLTRB(
              AppTheme.hankoGutter, 0, AppTheme.hankoGutter - 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('This season',
                      style: AppTheme.hankoSerif(height: 1.3)),
                ),
              ),
              const SizedBox(width: 12),
              _SeeAllLink(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const UpcomingAnimeScreen())),
              ),
            ],
          ),
        ),

        // Horizontal scroll
        SizedBox(
          height: stripHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
            itemCount: shown.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final anime = shown[i];
              final title = anime.titleEnglish ?? anime.title;
              void open() => Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => AnimeDetailScreen(anime: anime)));
              // excludeSemantics drops the InkWell's own tap action with the
              // rest of the subtree, so the node carries onTap itself.
              return Semantics(
                button: true,
                label: title,
                onTap: open,
                excludeSemantics: true,
                child: InkWell(
                  onTap: open,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: AppTheme.hankoPressWash,
                  hoverColor: AppTheme.hankoPressWash,
                  child: SizedBox(
                    width: itemWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Poster
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTheme.hankoRadius),
                          child: SizedBox(
                            width: itemWidth,
                            height: coverHeight,
                            child: ColoredBox(
                              color: AppTheme.hankoSumi3,
                              child: anime.imageUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: anime.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, _, _) =>
                                          const SizedBox.expand(),
                                    )
                                  : const SizedBox.expand(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Title
                        Text(
                          title,
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoLabelSize,
                              weight: FontWeight.w500,
                              height: 1.25),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Hanko's quiet link, as Home's "See all": Jost 500 13 in washi, underlined
/// in edge, in a 48 dp target. A secondary way on, never shaped as a button.
class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              minHeight: AppTheme.hankoTouch, minWidth: AppTheme.hankoTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Align(
              widthFactor: 1,
              child: Text(
                'See all',
                style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  weight: FontWeight.w500,
                ).copyWith(
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.hankoEdge,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
