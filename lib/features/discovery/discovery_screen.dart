import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/anilist_service.dart';
import '../../widgets/anilist_saved_note.dart';
import '../../widgets/hanko_board.dart';
import '../../services/offline_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hanj_filter_sheet.dart';
import '../../models/anime_model.dart';
import '../anime_detail/anime_detail_screen.dart';
import 'emotional_categories.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Discovery Screen
// ─────────────────────────────────────────────────────────────────────────────

class DiscoveryScreen extends StatefulWidget {
  final String? initialTab;
  /// True when pushed as a route (Home's "MORE →") rather than shown as the
  /// Discover tab. A pushed copy covers the nav bar and, on web, has no
  /// system back gesture, so it draws its own way back.
  final bool showBackButton;
  const DiscoveryScreen({
    super.key,
    this.initialTab,
    this.showBackButton = false,
  });

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = ['VIBES', 'TOP RATED', 'POPULAR', 'TRENDING', 'SEASONAL'];

  /// Vibes for the rest of Discover (Print Room, r9; Shahid, 2026-11-10: "I
  /// loved new vibes change, if we can bring that change to other
  /// tabs/features wherever needed"): printed tabs, the washi one selected;
  /// Top rated, Popular and Trending open on a board holding their first
  /// three, then printed posters; the filter as printed chips; Seasonal as a
  /// board of the season's covers over printed rows, its countdown ticking in
  /// its own leaf. False gives back 07faabe's tabs, grids, filter and hub as
  /// they were (VIBES is unchanged either way).
  static const bool _printRoom = true;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.initialTab != null
        ? _tabs.indexOf(widget.initialTab!)
        : 0;
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex.clamp(0, _tabs.length - 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.showBackButton)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppTheme.textPrimary, size: 20),
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                    ),
                  Text(
                    'Discover',
                    style: AppTheme.serif(
                        fontSize: 28, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Find your next obsession',
                    style: AppTheme.mono(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        letterSpacing: 1.2),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Tab Bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ArukuTabBar(
                controller: _tabController,
                tabs: _tabs,
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab Views ───────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [
                  EmotionalCategoriesTab(),
                  _FilteredAnimeTab(sort: 'SCORE_DESC', enableFilters: true),
                  _FilteredAnimeTab(sort: 'POPULARITY_DESC'),
                  _FilteredAnimeTab(sort: 'TRENDING_DESC'),
                  _SeasonalTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Pill Tab Bar
// ─────────────────────────────────────────────────────────────────────────────

class _ArukuTabBar extends StatefulWidget {
  final TabController controller;
  final List<String> tabs;

  const _ArukuTabBar({required this.controller, required this.tabs});

  @override
  State<_ArukuTabBar> createState() => _ArukuTabBarState();
}

class _ArukuTabBarState extends State<_ArukuTabBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(() => setState(() {}));
  }

  // Print Room (r9): printed tabs, the selected one washi (CLAUDE.md: never
  // coral, which is only ever your verdicts), each a button a screen reader
  // and the keyboard land on.
  Widget _printed(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < widget.tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            HankoTab(
              label: widget.tabs[i],
              selected: widget.controller.index == i,
              onTap: () => widget.controller
                  .animateTo(i, duration: still ? Duration.zero : null),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_DiscoveryScreenState._printRoom) return _printed(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(widget.tabs.length, (i) {
          final selected = widget.controller.index == i;
          return GestureDetector(
            onTap: () => widget.controller.animateTo(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              margin: const EdgeInsets.only(right: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? AppTheme.primary
                      : AppTheme.border,
                  width: 1,
                ),
              ),
              child: Text(
                widget.tabs[i],
                style: AppTheme.mono(
                  fontSize: 10,
                  color: selected
                      ? AppTheme.textPrimary
                      : AppTheme.textMuted,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filtered Anime Tab (Top Rated / Popular / Trending)
// ─────────────────────────────────────────────────────────────────────────────

class _FilteredAnimeTab extends StatefulWidget {
  final String sort;
  final bool enableFilters;

  const _FilteredAnimeTab({required this.sort, this.enableFilters = false});

  @override
  State<_FilteredAnimeTab> createState() => _FilteredAnimeTabState();
}

class _FilteredAnimeTabState extends State<_FilteredAnimeTab>
    with AutomaticKeepAliveClientMixin {
  final _service = AnilistService();

  // Static cache keyed by sort — survives screen rebuilds
  static final Map<String, List<Anime>> _staticCache = {};

  List<Anime> _animeList = [];
  bool _isLoading = true;

  String? _selectedGenre;
  String? _selectedFormat;
  int? _selectedYear;

  // Whether _animeList came from a filtered query. The grid only keeps a
  // list on screen while it matches the filter chips above it.
  bool _showingFiltered = false;
  // Bumped by each _load, so an answer that lands after a newer request
  // (filters changed again meanwhile) is dropped, not shown.
  int _loadSeq = 0;
  // Outcome of the last filtered fetch (null = AniList answered), so a
  // failed one doesn't read as "No results found".
  int? _failStatus;
  // Set when the last unfiltered load came back empty. A sort over all of
  // AniList always has titles, so that means nothing loaded, not that
  // nothing matched. Which way it failed isn't known here, see _load.
  bool _unfilteredFailed = false;

  static const _genres = [
    'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy',
    'Horror', 'Mystery', 'Romance', 'Sci-Fi', 'Slice of Life',
    'Sports', 'Supernatural', 'Thriller',
  ];

  static const _formats = ['TV', 'MOVIE', 'OVA', 'ONA', 'SPECIAL'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final cached = _staticCache[widget.sort];
    if (cached != null && cached.isNotEmpty) {
      _animeList = cached;
      _isLoading = false;
    }
    _load();
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;

    // When no filters are active, use the offline cache (with stale fallback)
    final hasFilters = _selectedGenre != null || _selectedYear != null || _selectedFormat != null;

    // Full spinner when there's nothing to display yet, or when what's on
    // screen was fetched for other filters than the ones now applied.
    if (_animeList.isEmpty || hasFilters || _showingFiltered) {
      setState(() => _isLoading = true);
    }

    List<Anime> results;
    int? failStatus;
    if (!hasFilters) {
      final cache = OfflineCacheService.instance;
      switch (widget.sort) {
        case 'TRENDING_DESC':
          results = await cache.getTrending();
          break;
        case 'POPULARITY_DESC':
          results = await cache.getPopular();
          break;
        case 'SCORE_DESC':
          results = await cache.getTopRated();
          break;
        default:
          results = await _service.searchAnime('', sort: widget.sort);
      }
    } else {
      // Filtered queries can't be cached (too many combinations) — try network, gracefully fail
      try {
        results = await _service.searchAnime(
          '',
          genre: _selectedGenre,
          year: _selectedYear,
          format: _selectedFormat,
          sort: widget.sort,
        );
        // searchAnime has no await after its request, so the flag still
        // holds this query's own outcome here.
        failStatus = AnilistService.lastFailStatus;
      } catch (_) {
        results = [];
      }
    }

    // A newer _load started while this one waited; its answer wins.
    if (!mounted || seq != _loadSeq) return;
    setState(() {
      if (hasFilters) {
        // A filtered answer always replaces the grid, empty or not. Keeping
        // the previous list here left unfiltered results under the chips.
        _animeList = results;
      } else if (results.isNotEmpty) {
        _animeList = results;
        _staticCache[widget.sort] = results;
      } else if (_showingFiltered) {
        // Filters just cleared and nothing came back: fall back to the last
        // unfiltered list rather than keep the filtered one on screen.
        _animeList = _staticCache[widget.sort] ?? [];
      }
      _showingFiltered = hasFilters;
      _failStatus = failStatus;
      // Not read from AnilistService.lastFailStatus. With OfflineCacheService
      // in between, the flag holds this fetch's outcome only while the cache
      // never awaits between the request and an empty return, and a 200 that
      // yields no titles leaves it null anyway.
      _unfilteredFailed = !hasFilters && results.isEmpty;
      _isLoading = false;
    });
  }

  bool get _hasActiveFilters =>
      _selectedGenre != null || _selectedFormat != null || _selectedYear != null;

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HanjFilterSheet(
        genre: _selectedGenre,
        format: _selectedFormat,
        year: _selectedYear,
        onApply: (genre, format, year) {
          setState(() {
            _selectedGenre = genre;
            _selectedFormat = format;
            _selectedYear = year;
          });
          _load();
        },
      ),
    );
  }

  // The filters now on, each with the step that takes it back off.
  List<(String, VoidCallback)> _onFilters() => [
        if (_selectedGenre != null)
          (_selectedGenre!, () {
            setState(() => _selectedGenre = null);
            _load();
          }),
        if (_selectedFormat != null)
          (HanjFilterSheet.formatLabel(_selectedFormat!), () {
            setState(() => _selectedFormat = null);
            _load();
          }),
        if (_selectedYear != null)
          ('$_selectedYear', () {
            setState(() => _selectedYear = null);
            _load();
          }),
      ];

  // ── Print Room (r9): the ranking as a Vibes board, then printed posters ──
  Widget _printed(BuildContext context) {
    final on = _onFilters();
    return Column(
      children: [
        if (widget.enableFilters) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (label, clear) in on) ...[
                          HankoChip(
                            label: label,
                            semanticLabel: 'Remove $label',
                            trailing: Icons.close_rounded,
                            onTap: clear,
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                HankoChip(
                  label: 'Filter',
                  semanticLabel:
                      on.isEmpty ? 'Filter' : 'Filter, ${on.length} on',
                  icon: Icons.tune_rounded,
                  on: on.isNotEmpty,
                  onTap: _showFilterSheet,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        Expanded(
          child: _isLoading
              ? const _RankLoading()
              : _animeList.isEmpty
                  ? _EmptyState(
                      failMessage: _unfilteredFailed
                          ? 'Fresh data can\'t load right now. Try again shortly.'
                          : AnilistService.messageFor(_failStatus))
                  : _RankBoardList(
                      sort: widget.sort,
                      anime: _animeList,
                      filters: [for (final (label, _) in on) label],
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_DiscoveryScreenState._printRoom) return _printed(context);

    return Column(
      children: [
        // ── Filter bar ────────────────────────────────────────
        if (widget.enableFilters) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                // Active filter chips
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (_selectedGenre != null)
                          _ActiveFilterChip(
                            label: _selectedGenre!,
                            onRemove: () {
                              setState(() => _selectedGenre = null);
                              _load();
                            },
                          ),
                        if (_selectedFormat != null)
                          _ActiveFilterChip(
                            label: HanjFilterSheet.formatLabel(_selectedFormat!),
                            onRemove: () {
                              setState(() => _selectedFormat = null);
                              _load();
                            },
                          ),
                        if (_selectedYear != null)
                          _ActiveFilterChip(
                            label: '$_selectedYear',
                            onRemove: () {
                              setState(() => _selectedYear = null);
                              _load();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _showFilterSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _hasActiveFilters
                          ? AppTheme.primary.withValues(alpha: 0.15)
                          : AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _hasActiveFilters
                            ? AppTheme.primary.withValues(alpha: 0.5)
                            : AppTheme.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune_rounded,
                            size: 14,
                            color: _hasActiveFilters
                                ? AppTheme.primary
                                : AppTheme.textMuted),
                        const SizedBox(width: 6),
                        Text(
                          'Filter',
                          style: AppTheme.mono(
                            fontSize: 10,
                            color: _hasActiveFilters
                                ? AppTheme.primary
                                : AppTheme.textMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Grid ──────────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.primary, strokeWidth: 2))
              : _animeList.isEmpty
                  ? _EmptyState(
                      // Unfiltered there is nothing to adjust, yet this read
                      // "No results found / Try adjusting your filters".
                      failMessage: _unfilteredFailed
                          ? 'Fresh data can\'t load right now. Try again shortly.'
                          : AnilistService.messageFor(_failStatus))
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.58,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _animeList.length,
                      itemBuilder: (context, index) {
                        // Featured first item spans 2 columns if top rated
                        return _AnimeCard(
                            key: ValueKey(_animeList[index].id),
                            anime: _animeList[index]);
                      },
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Print Room (r9): a ranking on a board
// ─────────────────────────────────────────────────────────────────────────────

/// A ranking (Top rated, Popular, Trending) drawn the way Vibes draws a mood:
/// a board holding its first three, posed for what the ranking is, then the
/// rest as printed posters, numbered on from four. The first time a ranking
/// shows in a session, the board and the first row deal in.
class _RankBoardList extends StatefulWidget {
  final String sort;
  final List<Anime> anime;
  // The filters now on, in words, for the board's label.
  final List<String> filters;

  const _RankBoardList({
    required this.sort,
    required this.anime,
    required this.filters,
  });

  static const double gutter = 20;
  static const double gap = 12;

  /// How many posters fit across [width] (three at least, and about 132 dp
  /// each on wide windows), and how wide each is.
  static (int, double) columnsFor(double width) {
    final inner = width - 2 * gutter;
    final columns = math.max(3, ((inner + gap) / (132 + gap)).floor());
    return (columns, (inner - gap * (columns - 1)) / columns);
  }

  @override
  State<_RankBoardList> createState() => _RankBoardListState();
}

class _RankBoardListState extends State<_RankBoardList> {
  static final Set<String> _dealt = {};
  late final bool _dealIn = _dealt.add(widget.sort);

  void _open(Anime anime) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)),
      );

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final anime = widget.anime;
    final rest = anime.length > 3 ? anime.sublist(3) : const <Anime>[];
    return LayoutBuilder(builder: (context, constraints) {
      final (columns, width) = _RankBoardList.columnsFor(constraints.maxWidth);
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                _RankBoardList.gutter, 4, _RankBoardList.gutter, 0),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: _RankBoard(
                    sort: widget.sort,
                    top: anime.take(3).toList(),
                    filters: widget.filters,
                    dealIn: _dealIn,
                    onOpen: _open,
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                _RankBoardList.gutter, 20, _RankBoardList.gutter, 40),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: _RankBoardList.gap,
                mainAxisSpacing: 16,
                mainAxisExtent: HankoPoster.heightFor(width, scaler),
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final a = rest[i];
                  return HankoDeal(
                    key: ValueKey(a.id),
                    // After the board's three.
                    index: i + 3,
                    play: _dealIn,
                    from: const Offset(16, 0),
                    child: HankoPoster(
                      url: a.imageUrl,
                      title: a.titleEnglish ?? a.title,
                      score: a.averageScore,
                      rank: i + 4,
                      onTap: () => _open(a),
                    ),
                  );
                },
                childCount: rest.length,
              ),
            ),
          ),
        ],
      );
    });
  }
}

/// The board a ranking opens on: its first three standing in a pose that
/// says what the ranking is, as Vibes poses its moods, on a tint taken from
/// their covers:
///  - Top rated: a podium, number one raised in the middle, and larger;
///  - Popular: shoulder to shoulder, all three level;
///  - Trending: a rising stair, three low on the left, one high on the right.
/// Unlike a Vibes hand they stand upright and apart, so each can be read and
/// tapped: each print is one button, and its title on the strip below opens
/// the same show without a second stop for a screen reader or the keyboard.
/// Titles and the crowd's scores sit on the strip's flat 5%, where ai keeps
/// 5.4:1; the name, tagline and label sit on the pool in washi and stone hi.
class _RankBoard extends StatelessWidget {
  final String sort;
  final List<Anime> top;
  final List<String> filters;
  final bool dealIn;
  final ValueChanged<Anime> onOpen;

  const _RankBoard({
    required this.sort,
    required this.top,
    required this.filters,
    required this.dealIn,
    required this.onOpen,
  });

  static const double _gap = 10;

  // The board's name, its tagline, and the order, for its label. The label's
  // spaces don't break, so it wraps only after a dot.
  static (String, String, String) _words(String sort) => switch (sort) {
        'SCORE_DESC' =>
          ('Top rated', 'The crowd’s highest scores', 'by\u00A0score'),
        'POPULARITY_DESC' =>
          ('Popular', 'On the most lists', 'by\u00A0members'),
        _ => ('Trending', 'Climbing right now', 'trending\u00A0now'),
      };

  // The pose: which of the three stands in each slot, left to right (0 is
  // number one), each slot's width as a share, and how high each stands (dp).
  static (List<int>, List<double>, List<double>) _pose(String sort) =>
      switch (sort) {
        'SCORE_DESC' => (const [1, 0, 2], const [0.92, 1.16, 0.92], const [0.0, 14.0, 0.0]),
        'TRENDING_DESC' => (const [2, 1, 0], const [1.0, 1.0, 1.0], const [0.0, 12.0, 24.0]),
        _ => (const [0, 1, 2], const [1.0, 1.0, 1.0], const [0.0, 0.0, 0.0]),
      };

  @override
  Widget build(BuildContext context) {
    final (name, tagline, order) = _words(sort);
    final label = [
      if (filters.isEmpty) 'all\u00A0anime',
      for (final f in filters) f.replaceAll(' ', '\u00A0'),
      order,
    ].join(' · ').toUpperCase();
    final (slots, shares, raised) = _pose(sort);
    final present = [
      for (var s = 0; s < 3; s++)
        if (slots[s] < top.length) s,
    ];
    return HankoCoverTint(
      urls: [for (final a in top) a.imageUrl ?? ''],
      builder: (context, tint) => LayoutBuilder(
        builder: (context, constraints) {
          final unit = math.min(
              124.0,
              (constraints.maxWidth - 32 - 2 * _gap) /
                  shares.fold(0.0, (a, b) => a + b));
          // One row of the three slots, each cell as wide as its print.
          Widget row(CrossAxisAlignment align,
                  Widget Function(Anime anime, int s, double width) cell) =>
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: align,
                children: [
                  for (final s in present) ...[
                    if (s != present.first) const SizedBox(width: _gap),
                    SizedBox(
                      width: shares[s] * unit,
                      child: cell(top[slots[s]], s, shares[s] * unit),
                    ),
                  ],
                ],
              );
          return HankoBoard(
            tint: tint,
            centre: const Alignment(0, 0.25),
            radius: 0.9,
            face: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoLedeSize, height: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tagline,
                    style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      color: AppTheme.hankoStoneHi,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(label, style: HankoBoard.labelStyle()),
                  const SizedBox(height: 16),
                  row(
                    CrossAxisAlignment.end,
                    (anime, s, width) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HankoDeal(
                          // Number three steps up first, number one last.
                          index: 2 - slots[s],
                          play: dealIn,
                          from: const Offset(0, 12),
                          child: _Standing(
                            anime: anime,
                            rank: slots[s] + 1,
                            width: width,
                            onTap: () => onOpen(anime),
                          ),
                        ),
                        SizedBox(height: raised[s]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            strip: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: row(
                CrossAxisAlignment.start,
                (anime, s, width) =>
                    _StripTitle(anime: anime, onTap: () => onOpen(anime)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One of a ranking's first three, standing on its board: the cover as a
/// printed card with its plate number, one button ("1, Frieren, AniList
/// 9.1"). A press presses it in; a pointer or keyboard focus drops its shadow.
class _Standing extends StatefulWidget {
  final Anime anime;
  final int rank;
  final double width;
  final VoidCallback onTap;

  const _Standing({
    required this.anime,
    required this.rank,
    required this.width,
    required this.onTap,
  });

  @override
  State<_Standing> createState() => _StandingState();
}

class _StandingState extends State<_Standing> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.anime;
    final score = a.averageScore;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      button: true,
      label: [
        '${widget.rank}',
        a.titleEnglish ?? a.title,
        if (score != null) 'AniList ${(score / 10).toStringAsFixed(1)}',
      ].join(', '),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) => setState(() => _focused = v),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ExcludeSemantics(
            child: AnimatedScale(
              scale: _pressed && !still ? 0.97 : 1,
              duration: const Duration(milliseconds: 120),
              child: SizedBox(
                width: widget.width,
                height: widget.width * hankoCoverRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    HankoCard(url: a.imageUrl, lifted: _hovered || _focused),
                    Positioned(
                      left: 0,
                      top: 0,
                      child: HankoPlateNumber(rank: widget.rank),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A standing print's title and the crowd's score, on the board's strip. It
/// opens the same show as the print above it, which is the button, so it's
/// no second stop for a screen reader or the keyboard.
class _StripTitle extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;

  const _StripTitle({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final score = anime.averageScore;
    return ExcludeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          canRequestFocus: false,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                anime.titleEnglish ?? anime.title,
                style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  weight: FontWeight.w500,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (score != null) ...[
                const SizedBox(height: 4),
                Text(
                  (score / 10).toStringAsFixed(1),
                  style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoLabelSize,
                    weight: FontWeight.w500,
                    color: AppTheme.hankoAi,
                    height: 1.25,
                    tabular: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// While a ranking loads: its board and two rows of posters as blank paper,
/// sumi 2 and sumi 3, as everywhere in Hanko. No spinner, nothing moving.
class _RankLoading extends StatelessWidget {
  const _RankLoading();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final (columns, width) = _RankBoardList.columnsFor(constraints.maxWidth);
      const corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            _RankBoardList.gutter, 4, _RankBoardList.gutter, 0),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: const SizedBox(
                width: double.infinity,
                height: 340,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: AppTheme.hankoSumi2, borderRadius: corners),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: _RankBoardList.gap,
            runSpacing: 16,
            children: [
              for (var i = 0; i < columns * 2; i++)
                SizedBox(
                  width: width,
                  height: width * hankoCoverRatio,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                        color: AppTheme.hankoSumi3, borderRadius: corners),
                  ),
                ),
            ],
          ),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seasonal Tab — wraps the full SeasonalHub in a scrollable tab
// ─────────────────────────────────────────────────────────────────────────────

class _SeasonalTab extends StatefulWidget {
  const _SeasonalTab();

  @override
  State<_SeasonalTab> createState() => _SeasonalTabState();
}

class _SeasonalTabState extends State<_SeasonalTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const SingleChildScrollView(
      child: _SeasonalHub(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEASONAL HUB
// ─────────────────────────────────────────────────────────────────────────────

class _SeasonalHub extends StatefulWidget {
  const _SeasonalHub();

  @override
  State<_SeasonalHub> createState() => _SeasonalHubState();
}

class _SeasonalHubState extends State<_SeasonalHub>
    with TickerProviderStateMixin {
  List<_SeasonalAnime> _currentSeason = [];
  List<_SeasonalAnime> _nextSeason = [];
  bool _loading = true;
  bool _showNext = false;

  // ── Static cache — survives tab switches and screen rebuilds ──
  static List<_SeasonalAnime>? _cachedCurrent;
  static List<_SeasonalAnime>? _cachedNext;
  static String? _cachedForSeason;
  static int?    _cachedForYear;

  late AnimationController _countdownPulse;
  late Timer _countdownTimer;
  Duration _timeToNextSeason = Duration.zero;

  @override
  void initState() {
    super.initState();
    _countdownPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    // The printed board has no pulsing border, so its ticker never starts.
    if (!_DiscoveryScreenState._printRoom) {
      _countdownPulse.repeat(reverse: true);
    }
    _computeCountdown();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _computeCountdown(),
    );

    // Seed from static cache so there's no blank flash on rebuild
    final thisSeason = _currentSeasonStr();
    final thisYear   = DateTime.now().year;
    if (_cachedCurrent != null &&
        _cachedForSeason == thisSeason &&
        _cachedForYear   == thisYear) {
      _currentSeason = _cachedCurrent!;
      _nextSeason    = _cachedNext ?? [];
      _loading       = false;
    }

    _fetchSeasons();
  }

  @override
  void dispose() {
    _countdownPulse.dispose();
    _countdownTimer.cancel();
    super.dispose();
  }

  static String _currentSeasonStr() {
    final m = DateTime.now().month;
    if (m >= 1 && m <= 3) return 'WINTER';
    if (m >= 4 && m <= 6) return 'SPRING';
    if (m >= 7 && m <= 9) return 'SUMMER';
    return 'FALL';
  }

  static String _nextSeasonStr() {
    const order = ['WINTER', 'SPRING', 'SUMMER', 'FALL'];
    final idx = order.indexOf(_currentSeasonStr());
    return order[(idx + 1) % 4];
  }

  static int _nextSeasonYear() {
    final now = DateTime.now();
    return _currentSeasonStr() == 'FALL' ? now.year + 1 : now.year;
  }

  static DateTime _nextSeasonStart() {
    final y = _nextSeasonYear();
    switch (_nextSeasonStr()) {
      case 'WINTER': return DateTime(y, 1, 1);
      case 'SPRING': return DateTime(y, 4, 1);
      case 'SUMMER': return DateTime(y, 7, 1);
      default:       return DateTime(y, 10, 1);
    }
  }

  void _computeCountdown() {
    // The printed board's countdown ticks in its own leaf (_SeasonCountdown),
    // so the hub no longer rebuilds every second (PERF.md's idle-jank lesson).
    if (_DiscoveryScreenState._printRoom) return;
    final diff = _nextSeasonStart().difference(DateTime.now());
    if (mounted) setState(() => _timeToNextSeason = diff);
  }

  Color _seasonColor(String season) {
    switch (season) {
      case 'SPRING': return const Color(0xFFD4A5C9);
      case 'SUMMER': return const Color(0xFFE8B86D);
      case 'FALL':   return AppTheme.primary;
      default:       return const Color(0xFF7ABDE8);
    }
  }

  Future<void> _fetchSeasons() async {
    final thisSeason = _currentSeasonStr();
    final thisYear   = DateTime.now().year;

    final current = await _fetchSeasonAnime(thisSeason, thisYear);
    final next    = await _fetchSeasonAnime(_nextSeasonStr(), _nextSeasonYear());

    if (current.isNotEmpty) {
      _cachedCurrent = current;
      _cachedForSeason = thisSeason;
      _cachedForYear = thisYear;
    }
    if (next.isNotEmpty) _cachedNext = next;

    if (mounted) {
      setState(() {
        if (current.isNotEmpty) _currentSeason = current;
        if (next.isNotEmpty)    _nextSeason     = next;
        _loading = false;
      });
    }
  }

  Future<List<_SeasonalAnime>> _fetchSeasonAnime(String season, int year) async {
    final cacheKey = 'cache_seasonal_hub_${season}_$year';
    final prefs    = await SharedPreferences.getInstance();
    const ttlMs    = 60 * 60 * 1000; // 1 hour

    // Try fresh cache first
    final tsKey  = '${cacheKey}_ts';
    final cachedAt = prefs.getInt(tsKey);
    final cached   = prefs.getString(cacheKey);
    if (cached != null && cachedAt != null &&
        DateTime.now().millisecondsSinceEpoch - cachedAt < ttlMs) {
      try {
        return (jsonDecode(cached) as List)
            .cast<Map<String, dynamic>>()
            .map(_SeasonalAnime.fromJson)
            .toList();
      } catch (_) {}
    }

    const url = 'https://graphql.anilist.co';
    final query = '''
    query {
      Page(page: 1, perPage: 12) {
        media(
          season: $season
          seasonYear: $year
          type: ANIME
          sort: POPULARITY_DESC
          format_in: [TV, TV_SHORT, MOVIE, ONA]
        ) {
          id
          title { romaji english }
          coverImage { large extraLarge }
          bannerImage
          popularity
          averageScore
          episodes
          nextAiringEpisode { airingAt episode }
          genres
          description(asHtml: false)
          status
        }
      }
    }
    ''';
    try {
      // Shared throttle + 429 retry, then cache the successful result.
      http.Response? res;
      for (var attempt = 0; attempt < 3; attempt++) {
        await AnilistService.throttle();
        try {
          res = await http.post(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'query': query}),
          );
        } catch (_) {
          // No response at all — record it, then let the network-exception
          // stale fallback at the bottom of this method run as before.
          AnilistService.noteStatus(0, 'discovery seasonal');
          rethrow;
        }
        AnilistService.noteStatus(res.statusCode, 'discovery seasonal');
        AnilistService.noteLimits(res.headers);
        if (res.statusCode != 429) break;
        // Rate limited — honor Retry-After, push the shared slot out
        final retryAfter =
            int.tryParse(res.headers['retry-after'] ?? '') ?? (3 * (attempt + 1));
        AnilistService.backoff(retryAfter);
      }

      if (res == null || res.statusCode != 200) {
        // Stale fallback
        if (cached != null) {
          try {
            return (jsonDecode(cached) as List)
                .cast<Map<String, dynamic>>()
                .map(_SeasonalAnime.fromJson)
                .toList();
          } catch (_) {}
        }
        return [];
      }

      final data = jsonDecode(res.body);
      if (data['data'] == null || data['data']['Page'] == null) {
        if (cached != null) {
          try {
            return (jsonDecode(cached) as List)
                .cast<Map<String, dynamic>>()
                .map(_SeasonalAnime.fromJson)
                .toList();
          } catch (_) {}
        }
        return [];
      }

      final List mediaList = data['data']['Page']['media'] ?? [];
      final maxPop = mediaList.isEmpty
          ? 1
          : mediaList.map((x) => (x['popularity'] ?? 0) as int).reduce(math.max);
      final result = mediaList.map((m) {
        final pop = (m['popularity'] ?? 0) as int;
        final hype = maxPop > 0 ? (pop / maxPop * 100).round() : 0;
        return _SeasonalAnime(
          id: m['id'] as int,
          title: (m['title']['english'] ?? m['title']['romaji'] ?? 'Unknown') as String,
          cover: m['coverImage']['extraLarge'] ?? m['coverImage']['large'] ?? '',
          banner: m['bannerImage'] ?? '',
          popularity: pop,
          hype: hype,
          score: m['averageScore'] ?? 0,
          episodes: m['episodes'] ?? 0,
          genres: (m['genres'] as List?)?.cast<String>() ?? [],
          description: _stripHtml(m['description'] ?? ''),
          status: m['status'] ?? '',
          nextAiringAt: m['nextAiringEpisode']?['airingAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  (m['nextAiringEpisode']['airingAt'] as int) * 1000)
              : null,
          nextEpisode: m['nextAiringEpisode']?['episode'],
        );
      }).toList();

      // ── Cache successful result to SharedPreferences (was missing!) ──
      if (result.isNotEmpty) {
        try {
          await prefs.setString(
              cacheKey, jsonEncode(result.map((a) => a.toJson()).toList()));
          await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
        } catch (_) {}
      }

      return result;
    } catch (_) {
      // Network exception — return stale if available
      if (cached != null) {
        try {
          return (jsonDecode(cached) as List)
              .cast<Map<String, dynamic>>()
              .map(_SeasonalAnime.fromJson)
              .toList();
        } catch (_) {}
      }
      return [];
    }
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#039;', "'")
        .replaceAll('&quot;', '"')
        .trim();
  }

  // ── Print Room (r9): the season as a Vibes board, then printed rows ──
  // The season's colour comes from its own covers, not from a hue per season
  // (FALL was coral, which is only ever yours).
  Widget _printed(BuildContext context) {
    final next = _showNext;
    final season = next ? _nextSeasonStr() : _currentSeasonStr();
    final year = next ? _nextSeasonYear() : DateTime.now().year;
    final activeList = next ? _nextSeason : _currentSeason;
    const corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AnilistSavedNote(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              HankoTab(
                label: 'Now airing',
                selected: !next,
                onTap: () => setState(() => _showNext = false),
              ),
              const SizedBox(width: 8),
              HankoTab(
                label: 'Coming soon',
                selected: next,
                onTap: () => setState(() => _showNext = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _loading
              ? const SizedBox(
                  height: 250,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: AppTheme.hankoSumi2, borderRadius: corners),
                  ),
                )
              : _SeasonBoard(
                  key: ValueKey('$season $year'),
                  season: season,
                  year: year,
                  covers: [for (final a in activeList.take(5)) a.cover],
                  startsAt: next ? _nextSeasonStart() : null,
                ),
        ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              children: [
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        const SizedBox(width: 26),
                        const SizedBox(
                          width: 40,
                          height: 40 * hankoCoverRatio,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: AppTheme.hankoSumi3,
                                borderRadius: corners),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 14,
                            margin: const EdgeInsets.only(right: 60),
                            color: AppTheme.hankoSumi3,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          )
        else if (activeList.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Text(
              'No seasonal data available',
              textAlign: TextAlign.center,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize, color: AppTheme.hankoStone),
            ),
          )
        else ...[
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'COMMUNITY HYPE',
              style: HankoBoard.labelStyle(color: AppTheme.hankoStone),
            ),
          ),
          const SizedBox(height: 4),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: math.min(activeList.length, 10),
            // Keyed by media id, as before: the list swaps wholesale between
            // this season and next.
            itemBuilder: (ctx, i) => _HypeMeterRow(
              key: ValueKey(activeList[i].id),
              anime: activeList[i],
              rank: i + 1,
              accentColor: _seasonColor(season),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_DiscoveryScreenState._printRoom) return _printed(context);
    final curSeason = _currentSeasonStr();
    final nxtSeason = _nextSeasonStr();
    final accentCur = _seasonColor(curSeason);
    final accentNxt = _seasonColor(nxtSeason);
    final activeList = _showNext ? _nextSeason : _currentSeason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AnilistSavedNote(),
        // ── Season toggle ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _SeasonToggle(
            currentSeason: curSeason,
            nextSeason: nxtSeason,
            showNext: _showNext,
            currentColor: accentCur,
            nextColor: accentNxt,
            onToggle: (val) => setState(() => _showNext = val),
          ),
        ),

        // ── Countdown banner ─────────────────────────────────────────────
        if (_showNext) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _CountdownBanner(
              timeLeft: _timeToNextSeason,
              nextSeason: nxtSeason,
              accentColor: accentNxt,
              pulseController: _countdownPulse,
            ),
          ),
        ],

        const SizedBox(height: 16),

        if (_loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: List.generate(5, (i) => Container(
                height: 56,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                ),
              )),
            ),
          )
        else if (activeList.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                'No seasonal data available',
                style: AppTheme.sans(fontSize: 13, color: AppTheme.textMuted),
              ),
            ),
          )
        else ...[
          // Hero card — #1 most hyped
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _HeroCard(
              anime: activeList.first,
              accentColor: _showNext ? accentNxt : accentCur,
            ),
          ),

          const SizedBox(height: 16),

          // Section label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'COMMUNITY HYPE',
              style: AppTheme.mono(
                fontSize: 10,
                color: AppTheme.textMuted,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Hype meter rows
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: math.min(activeList.length, 10),
            // Keyed by media id: activeList swaps wholesale when _showNext
            // toggles between this season and next. _HypeMeterRowState owns an
            // AnimationController and an _expanded flag, so index matching
            // leaves a row expanded (and mid-animation) over a different anime.
            itemBuilder: (ctx, i) => _HypeMeterRow(
              key: ValueKey(activeList[i].id),
              anime: activeList[i],
              rank: i + 1,
              accentColor: _showNext ? accentNxt : accentCur,
            ),
          ),

          const SizedBox(height: 28),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Print Room (r9): the season on a board
// ─────────────────────────────────────────────────────────────────────────────

/// The season as Vibes draws its featured board: its name, what feeds it, and
/// its five most-watched covers in the featured spread, on a tint taken from
/// them. Coming soon adds the countdown. The board deals its hand in the
/// first time a season shows in a session. One node for a screen reader,
/// which names the season (the rows below name the shows).
class _SeasonBoard extends StatefulWidget {
  final String season;
  final int year;
  final List<String> covers;
  // When the season starts, for one that hasn't yet.
  final DateTime? startsAt;

  const _SeasonBoard({
    super.key,
    required this.season,
    required this.year,
    required this.covers,
    required this.startsAt,
  });

  @override
  State<_SeasonBoard> createState() => _SeasonBoardState();
}

class _SeasonBoardState extends State<_SeasonBoard> {
  static final Set<String> _dealt = {};
  late final bool _dealIn = _dealt.add('${widget.season} ${widget.year}');

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final s = widget.season;
    final name = '${s[0]}${s.substring(1).toLowerCase()} ${widget.year}';
    final startsAt = widget.startsAt;
    final tagline = startsAt == null
        ? 'Airing now, the most watched first'
        : 'On the way, the most awaited first';
    final days = startsAt?.difference(DateTime.now()).inDays;
    return Semantics(
      container: true,
      label: [
        name,
        tagline,
        if (days != null) 'Starts in ${days < 1 ? 'under a day' : '$days days'}',
      ].join('. '),
      child: ExcludeSemantics(
        child: HankoCoverTint(
          urls: widget.covers,
          builder: (context, tint) => HankoBoard(
            tint: tint,
            centre: const Alignment(0, 0.45),
            radius: 1.1,
            face: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    name,
                    style: AppTheme.hankoSerif(
                        fontSize: AppTheme.hankoLedeSize, height: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tagline,
                    style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoMetaSize,
                      color: AppTheme.hankoStoneHi,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$s\u00A0${widget.year} · POPULAR',
                    style: HankoBoard.labelStyle(),
                  ),
                  if (startsAt != null) ...[
                    const SizedBox(height: 10),
                    _SeasonCountdown(startsAt: startsAt),
                  ],
                  const SizedBox(height: 14),
                  Center(
                    child: HankoHand(
                      poses: HankoPose.featured,
                      urls: widget.covers,
                      coverWidth: 58,
                      lifted: false,
                      dealIn: _dealIn && !still,
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
}

/// The countdown to the next season, in Jost's tabular figures so the
/// seconds don't shift. It ticks in this leaf alone (PERF.md: a per-second
/// setState on a large screen caused idle jank).
class _SeasonCountdown extends StatefulWidget {
  final DateTime startsAt;

  const _SeasonCountdown({required this.startsAt});

  @override
  State<_SeasonCountdown> createState() => _SeasonCountdownState();
}

class _SeasonCountdownState extends State<_SeasonCountdown> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var left = widget.startsAt.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('STARTS IN', style: HankoBoard.labelStyle()),
        Text(
          '${left.inDays}D ${two(left.inHours % 24)}H '
          '${two(left.inMinutes % 60)}M ${two(left.inSeconds % 60)}S',
          style: AppTheme.hankoSans(
            fontSize: 15,
            weight: FontWeight.w600,
            height: 1.3,
            tabular: true,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Season Toggle
// ─────────────────────────────────────────────────────────────────────────────

class _SeasonToggle extends StatelessWidget {
  final String currentSeason, nextSeason;
  final bool showNext;
  final Color currentColor, nextColor;
  final ValueChanged<bool> onToggle;

  const _SeasonToggle({
    required this.currentSeason, required this.nextSeason,
    required this.showNext, required this.currentColor,
    required this.nextColor, required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _tab('NOW AIRING', currentSeason, !showNext, currentColor, () => onToggle(false)),
          _tab('COMING SOON', nextSeason, showNext, nextColor, () => onToggle(true)),
        ],
      ),
    );
  }

  Widget _tab(String sub, String label, bool active, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: color.withValues(alpha: 0.4)) : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: AppTheme.mono(
                  fontSize: 11,
                  color: active ? color : AppTheme.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
              Text(
                sub,
                style: AppTheme.mono(
                  fontSize: 8,
                  color: active ? color.withValues(alpha: 0.6) : AppTheme.textMuted.withValues(alpha: 0.5),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Countdown Banner
// ─────────────────────────────────────────────────────────────────────────────

class _CountdownBanner extends StatelessWidget {
  final Duration timeLeft;
  final String nextSeason;
  final Color accentColor;
  final AnimationController pulseController;

  const _CountdownBanner({
    required this.timeLeft, required this.nextSeason,
    required this.accentColor, required this.pulseController,
  });

  String _pad(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final d = timeLeft.inDays;
    final h = timeLeft.inHours % 24;
    final m = timeLeft.inMinutes % 60;
    final s = timeLeft.inSeconds % 60;

    return AnimatedBuilder(
      animation: pulseController,
      builder: (ctx, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surfaceMid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.15 + pulseController.value * 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: accentColor, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$nextSeason SEASON STARTS IN',
                style: AppTheme.mono(
                  fontSize: 9,
                  color: AppTheme.textMuted,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            _timeUnit(_pad(d), 'D', accentColor),
            const SizedBox(width: 8),
            _timeUnit(_pad(h), 'H', accentColor),
            const SizedBox(width: 8),
            _timeUnit(_pad(m), 'M', accentColor),
            const SizedBox(width: 8),
            _timeUnit(_pad(s), 'S', accentColor),
          ],
        ),
      ),
    );
  }

  Widget _timeUnit(String val, String label, Color color) {
    return Column(
      children: [
        // Jost with tabular figures (Hanko's numerals; question 136). The
        // old 'SpaceGrotesk' literal named no registered family, so the
        // digits fell back to the platform font. Tabular figures keep the
        // ticking seconds from shifting width. 600 is Jost's heaviest.
        Text(val, style: AppTheme.mono(
          fontSize: 15, weight: FontWeight.w600, color: color,
          letterSpacing: 0,
        )),
        Text(label, style: TextStyle(
          color: AppTheme.textMuted, fontSize: 8, letterSpacing: 1,
        )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Card — #1 Most Hyped
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatefulWidget {
  final _SeasonalAnime anime;
  final Color accentColor;

  const _HeroCard({required this.anime, required this.accentColor});

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.anime;
    final nextEpText = a.nextAiringAt != null
        ? 'EP ${a.nextEpisode} · ${_fmtRelative(a.nextAiringAt!)}'
        : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => AnimeDetailScreen(anime: widget.anime.toAnime()),
        )),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 180,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? widget.accentColor.withValues(alpha: 0.5)
                  : widget.accentColor.withValues(alpha: 0.2),
            ),
            boxShadow: _hovered
                ? [BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.15),
                    blurRadius: 16,
                  )]
              : [],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Banner or cover image. An image that can't load (offline and
            // never cached) stays blank; with no errorWidget the failure
            // went to Crashlytics as fatal.
            a.banner.isNotEmpty
                ? CachedNetworkImage(imageUrl: a.banner, fit: BoxFit.cover,
                    errorWidget: (_, _, _) => CachedNetworkImage(
                      imageUrl: a.cover, fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const SizedBox.shrink()))
                : CachedNetworkImage(imageUrl: a.cover, fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink()),

            // Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.88),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),

            // Bottom content
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: CachedNetworkImage(
                        imageUrl: a.cover, width: 50, height: 70, fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink()),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: widget.accentColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '#1 MOST HYPED',
                              style: AppTheme.mono(
                                fontSize: 8,
                                color: Colors.white,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            a.title,
                            style: AppTheme.serif(fontSize: 16, weight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              if (a.genres.isNotEmpty)
                                _SmallChip(a.genres.first, AppTheme.textPrimary.withValues(alpha: 0.15)),
                              if (nextEpText != null) ...[
                                const SizedBox(width: 5),
                                _SmallChip(
                                  nextEpText,
                                  widget.accentColor.withValues(alpha: 0.2),
                                  textColor: widget.accentColor,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Hype bubble
                    Container(
                      width: 46,
                      height: 46,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.accentColor.withValues(alpha: 0.15),
                        border: Border.all(color: widget.accentColor.withValues(alpha: 0.4), width: 1.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${a.hype}',
                            style: TextStyle(
                              color: widget.accentColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text('HYPE', style: AppTheme.mono(fontSize: 7, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Score pill top-right
            if (a.score > 0)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFFD166), size: 10),
                      const SizedBox(width: 3),
                      Text(
                        (a.score / 10).toStringAsFixed(1),
                        style: AppTheme.mono(fontSize: 10, color: AppTheme.textPrimary),
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

  String _fmtRelative(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'aired';
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'soon';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hype Meter Row
// ─────────────────────────────────────────────────────────────────────────────

class _HypeMeterRow extends StatefulWidget {
  final _SeasonalAnime anime;
  final int rank;
  final Color accentColor;

  const _HypeMeterRow({super.key, required this.anime, required this.rank, required this.accentColor});

  @override
  State<_HypeMeterRow> createState() => _HypeMeterRowState();
}

class _HypeMeterRowState extends State<_HypeMeterRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _barCtrl;
  late Animation<double> _barAnim;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _barCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _barAnim = CurvedAnimation(parent: _barCtrl, curve: Curves.easeOutCubic);
    Future.delayed(Duration(milliseconds: 80 + widget.rank * 60), () {
      if (mounted) _barCtrl.forward();
    });
  }

  @override
  void dispose() { _barCtrl.dispose(); super.dispose(); }

  // Print Room (r9): a printed row: the rank, the cover as a printed card,
  // the title, a thin hype rule in ai deep (no glow), the crowd's numbers in
  // ai and no star. Long-press still opens the synopsis.
  Widget _printed(BuildContext context) {
    final a = widget.anime;
    final still = MediaQuery.disableAnimationsOf(context);
    final top3 = widget.rank <= 3;
    final score = a.score > 0 ? (a.score / 10).toStringAsFixed(1) : null;
    // The rank, the cover and the gap: where the synopsis lines up.
    const inset = 26.0 + 40 + 12;
    return Semantics(
      container: true,
      button: true,
      label: [
        '${widget.rank}',
        a.title,
        '${a.hype}% hype',
        if (score != null) 'AniList $score',
      ].join(', '),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => AnimeDetailScreen(anime: widget.anime.toAnime()),
          )),
          onLongPress: () => setState(() => _expanded = !_expanded),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${widget.rank}',
                          style: AppTheme.hankoSans(
                            fontSize: top3 ? 15 : 13,
                            weight: FontWeight.w600,
                            color: top3
                                ? AppTheme.hankoWashi
                                : AppTheme.hankoStone,
                            height: 1.3,
                            tabular: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        height: 40 * hankoCoverRatio,
                        child: HankoCard(url: a.cover),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: AppTheme.hankoSans(
                                weight: FontWeight.w500,
                                height: 1.3,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            AnimatedBuilder(
                              animation: _barAnim,
                              builder: (ctx, _) => _HypeRule(
                                value: a.hype / 100 * (still ? 1 : _barAnim.value),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${a.hype}% hype',
                                    style: AppTheme.hankoSans(
                                      fontSize: AppTheme.hankoDataSmallSize,
                                      weight: FontWeight.w500,
                                      color: AppTheme.hankoAi,
                                      tabular: true,
                                    ),
                                  ),
                                  if (a.genres.isNotEmpty)
                                    TextSpan(
                                      text: '  ·  ${a.genres.take(2).join(', ')}',
                                      style: AppTheme.hankoSans(
                                        fontSize: AppTheme.hankoDataSmallSize,
                                        color: AppTheme.hankoStone,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (score != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            score,
                            style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              weight: FontWeight.w500,
                              color: AppTheme.hankoAi,
                              height: 1.3,
                              tabular: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_expanded && a.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.only(left: inset),
                      child: Text(
                        a.description,
                        style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          color: AppTheme.hankoStone,
                          height: 1.45,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (a.nextAiringAt != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: inset),
                        child: Text(
                          'Episode ${a.nextEpisode} ${_fmtRelative(a.nextAiringAt!)}'
                              .toUpperCase(),
                          style:
                              HankoBoard.labelStyle(color: AppTheme.hankoStoneHi),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_DiscoveryScreenState._printRoom) return _printed(context);
    final a = widget.anime;
    final isTop3 = widget.rank <= 3;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => AnimeDetailScreen(anime: widget.anime.toAnime()),
      )),
      onLongPress: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _expanded
              ? widget.accentColor.withValues(alpha: 0.07)
              : AppTheme.surfaceLight.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _expanded
                ? widget.accentColor.withValues(alpha: 0.2)
                : AppTheme.border.withValues(alpha: 0.6),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                // Rank
                SizedBox(
                  width: 26,
                  child: Text(
                    '#${widget.rank}',
                    style: AppTheme.mono(
                      fontSize: isTop3 ? 13 : 11,
                      color: isTop3 ? widget.accentColor : AppTheme.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Cover
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CachedNetworkImage(
                    imageUrl: a.cover, width: 34, height: 48, fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.title,
                        style: AppTheme.sans(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                          weight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      // Animated hype bar
                      AnimatedBuilder(
                        animation: _barAnim,
                        builder: (ctx, _) => _HypeBar(
                          value: (a.hype / 100) * _barAnim.value,
                          color: widget.accentColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '${a.hype}% hype',
                            style: AppTheme.mono(
                              fontSize: 9,
                              color: widget.accentColor.withValues(alpha: 0.8),
                            ),
                          ),
                          if (a.genres.isNotEmpty) ...[
                            Text('  ·  ', style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 9)),
                            Text(
                              a.genres.take(2).join(', '),
                              style: AppTheme.mono(fontSize: 9, color: AppTheme.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (a.score > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Column(
                      children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFFFD166), size: 12),
                        Text(
                          (a.score / 10).toStringAsFixed(1),
                          style: AppTheme.mono(fontSize: 10, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Expanded description
            if (_expanded && a.description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(color: widget.accentColor.withValues(alpha: 0.15), height: 1),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(width: 34),
                  Expanded(
                    child: Text(
                      a.description,
                      style: AppTheme.sans(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (a.nextAiringAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 34),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: widget.accentColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_rounded, color: widget.accentColor, size: 10),
                          const SizedBox(width: 4),
                          Text(
                            'Episode ${a.nextEpisode} ${_fmtRelative(a.nextAiringAt!)}',
                            style: AppTheme.mono(
                              fontSize: 10,
                              color: widget.accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _fmtRelative(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'aired';
    if (diff.inDays > 0) return 'in ${diff.inDays}d';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'soon';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hype Rule — Print Room (r9): a 2 dp rule in ai deep on the hairline, the
// crowd's measure (3.7:1 on sumi as a mark), with no gradient and no glow.
// ─────────────────────────────────────────────────────────────────────────────

class _HypeRule extends StatelessWidget {
  final double value;

  const _HypeRule({required this.value});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppTheme.hankoHairline),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0),
              child: const ColoredBox(color: AppTheme.hankoAiDeep),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hype Bar
// ─────────────────────────────────────────────────────────────────────────────

class _HypeBar extends StatelessWidget {
  final double value;
  final Color color;

  const _HypeBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      return Container(
        height: 3,
        width: c.maxWidth,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.6), color]),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 4,
              )],
            ),
          ),
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small chip helper
// ─────────────────────────────────────────────────────────────────────────────

class _SmallChip extends StatelessWidget {
  final String label;
  final Color bgColor;
  final Color? textColor;

  const _SmallChip(this.label, this.bgColor, {this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppTheme.mono(
          fontSize: 9,
          color: textColor ?? AppTheme.textSecondary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Seasonal Anime Data Model
// ─────────────────────────────────────────────────────────────────────────────

class _SeasonalAnime {
  final int id;
  final String title, cover, banner, description, status;
  final int popularity, hype, score, episodes;
  final List<String> genres;
  final DateTime? nextAiringAt;
  final int? nextEpisode;

  const _SeasonalAnime({
    required this.id, required this.title, required this.cover,
    required this.banner, required this.popularity, required this.hype,
    required this.score, required this.episodes, required this.genres,
    required this.description, required this.status,
    this.nextAiringAt, this.nextEpisode,
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'cover': cover, 'banner': banner,
    'popularity': popularity, 'hype': hype, 'score': score, 'episodes': episodes,
    'genres': genres, 'description': description, 'status': status,
    'nextAiringAt': nextAiringAt?.millisecondsSinceEpoch,
    'nextEpisode': nextEpisode,
  };

  factory _SeasonalAnime.fromJson(Map<String, dynamic> j) => _SeasonalAnime(
    id: j['id'] as int,
    title: j['title'] as String,
    cover: j['cover'] as String,
    banner: j['banner'] as String,
    popularity: j['popularity'] as int,
    hype: j['hype'] as int,
    score: j['score'] as int,
    episodes: j['episodes'] as int,
    genres: (j['genres'] as List).cast<String>(),
    description: j['description'] as String,
    status: j['status'] as String,
    nextAiringAt: j['nextAiringAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(j['nextAiringAt'] as int)
        : null,
    nextEpisode: j['nextEpisode'] as int?,
  );

  Anime toAnime() => Anime(
    id: id.toString(),
    title: title,
    imageUrl: cover,
    averageScore: score > 0 ? score.toDouble() : null,
    episodes: episodes > 0 ? episodes : null,
    status: status,
    genres: genres,
    description: description.isNotEmpty ? description : null,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Anime Card
// ─────────────────────────────────────────────────────────────────────────────

class _AnimeCard extends StatefulWidget {
  final Anime anime;

  const _AnimeCard({super.key, required this.anime});

  @override
  State<_AnimeCard> createState() => _AnimeCardState();
}

class _AnimeCardState extends State<_AnimeCard> {
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
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? AppTheme.primary.withValues(alpha: 0.6)
                  : AppTheme.cardBorder,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Cover image
                CachedNetworkImage(
                  imageUrl: widget.anime.imageUrl ?? '',
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: AppTheme.surfaceLight,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppTheme.primary),
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: AppTheme.surfaceLight,
                    child: const Icon(Icons.broken_image_outlined,
                        color: AppTheme.textMuted, size: 28),
                  ),
                ),

                // Gradient + info
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.anime.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.anime.averageScore != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Color(0xFFFFCC48), size: 11),
                              const SizedBox(width: 3),
                              Text(
                                (widget.anime.averageScore! / 10)
                                    .toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Color(0xFFFFCC48),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (widget.anime.format != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  widget.anime.format!,
                                  style: TextStyle(
                                    color: Colors.white
                                        .withValues(alpha: 0.5),
                                    fontSize: 9,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Format badge top-right
                if (widget.anime.seasonYear != null)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${widget.anime.seasonYear}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  // Set when the fetch behind the empty grid failed (AnilistService
  // .messageFor), so the grid doesn't claim the query had no matches.
  final String? failMessage;
  const _EmptyState({this.failMessage});

  // Print Room (r9): an empty hand where the shows would be, and the same
  // words.
  Widget _printed() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HankoEmptyHand(),
              const SizedBox(height: 20),
              Text(
                failMessage == null ? 'No results found' : 'Something went wrong',
                textAlign: TextAlign.center,
                style: AppTheme.hankoSerif(
                    fontSize: AppTheme.hankoFeaturedSize, height: 1.25),
              ),
              const SizedBox(height: 6),
              Text(
                failMessage ?? 'Try adjusting your filters',
                textAlign: TextAlign.center,
                style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  color: AppTheme.hankoStone,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => _DiscoveryScreenState._printRoom
      ? _printed()
      : Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 56, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text(failMessage == null ? 'No results found' : 'Something went wrong',
                style: AppTheme.sans(
                    fontSize: 15,
                    color: AppTheme.textSecondary,
                    weight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(failMessage ?? 'Try adjusting your filters',
                textAlign: TextAlign.center,
                style:
                    AppTheme.mono(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      );
}

class _FilterLabel extends StatelessWidget {
  final String text;
  const _FilterLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTheme.mono(
            fontSize: 10,
            color: AppTheme.textMuted,
            letterSpacing: 1.5),
      );
}

class _PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.18)
              : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.mono(
            fontSize: 10,
            color: selected ? color : AppTheme.textSecondary,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: AppTheme.mono(
                  fontSize: 10,
                  color: AppTheme.primary,
                  letterSpacing: 0.6)),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 12, color: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Unified Hanj Filter Sheet — used by both Discovery and Search
// ─────────────────────────────────────────────────────────────────────────────

class _HanjFilterSheet extends StatefulWidget {
  final String? genre;
  final String? format;
  final int? year;
  final void Function(String? genre, String? format, int? year) onApply;

  const _HanjFilterSheet({
    required this.onApply,
    this.genre,
    this.format,
    this.year,
  });

  @override
  State<_HanjFilterSheet> createState() => _HanjFilterSheetState();
}

class _HanjFilterSheetState extends State<_HanjFilterSheet> {
  late String? _genre;
  late String? _format;
  late int? _year;

  static const _genres = [
    'Action','Adventure','Comedy','Drama','Fantasy','Horror',
    'Mystery','Romance','Sci-Fi','Slice of Life','Sports',
    'Supernatural','Thriller','Mecha','Music','Psychological',
  ];
  static const _formats = ['TV', 'Movie', 'ONA', 'OVA', 'Special'];
  final _currentYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _genre = widget.genre;
    _format = widget.format;
    _year = widget.year;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.5,
      expand: false,
      builder: (ctx, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text('Filter & Sort',
                      style: AppTheme.serif(fontSize: 18, weight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _genre = null; _format = null; _year = null;
                    }),
                    child: Text('Reset',
                        style: AppTheme.sans(color: AppTheme.textMuted, fontSize: 13)),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            // Content
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _label('Genre'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _genres.map((g) => _Chip(
                      label: g,
                      selected: _genre == g,
                      onTap: () => setState(() => _genre = _genre == g ? null : g),
                    )).toList(),
                  ),
                  const SizedBox(height: 20),
                  _label('Format'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _formats.map((f) => _Chip(
                      label: f,
                      selected: _format == f,
                      onTap: () => setState(() => _format = _format == f ? null : f),
                    )).toList(),
                  ),
                  const SizedBox(height: 20),
                  _label('Year'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: List.generate(8, (i) {
                      final y = _currentYear - i;
                      return _Chip(
                        label: '$y',
                        selected: _year == y,
                        onTap: () => setState(() => _year = _year == y ? null : y),
                      );
                    }),
                  ),
                ],
              ),
            ),
            // Apply
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onApply(_genre, _format, _year);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Apply Filters',
                        // Sumi on coral, 5.64:1 (Hanko's rule; white was 3.35:1).
                        style: AppTheme.sans(fontSize: 14, color: AppTheme.textInverse, weight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: AppTheme.mono(fontSize: 11, color: AppTheme.textMuted, letterSpacing: 1),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            fontSize: 13,
            color: selected ? Colors.white : AppTheme.textSecondary,
            weight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
