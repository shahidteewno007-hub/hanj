import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../services/anilist_service.dart';
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
  const DiscoveryScreen({super.key, this.initialTab});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = ['VIBES', 'TOP RATED', 'POPULAR', 'TRENDING', 'SEASONAL'];

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

  @override
  Widget build(BuildContext context) {
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
    // Only show full spinner if we have nothing to display yet
    if (_animeList.isEmpty) setState(() => _isLoading = true);

    // When no filters are active, use the offline cache (with stale fallback)
    final hasFilters = _selectedGenre != null || _selectedYear != null || _selectedFormat != null;

    List<Anime> results;
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
      } catch (_) {
        results = [];
      }
    }

    if (mounted) setState(() {
      if (results.isNotEmpty) {
        _animeList = results;
        if (!hasFilters) _staticCache[widget.sort] = results;
      }
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

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
                            label: _selectedFormat!,
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
                  ? _EmptyState()
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
                        return _AnimeCard(anime: _animeList[index]);
                      },
                    ),
        ),
      ],
    );
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
    )..repeat(reverse: true);
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
        res = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'query': query}),
        );
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

  @override
  Widget build(BuildContext context) {
    final curSeason = _currentSeasonStr();
    final nxtSeason = _nextSeasonStr();
    final accentCur = _seasonColor(curSeason);
    final accentNxt = _seasonColor(nxtSeason);
    final activeList = _showNext ? _nextSeason : _currentSeason;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            itemBuilder: (ctx, i) => _HypeMeterRow(
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
        Text(val, style: TextStyle(
          color: color, fontSize: 15, fontWeight: FontWeight.w800,
          fontFamily: 'SpaceGrotesk',
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
            // Banner or cover image
            a.banner.isNotEmpty
                ? CachedNetworkImage(imageUrl: a.banner, fit: BoxFit.cover,
                    errorWidget: (_, _, _) => CachedNetworkImage(
                      imageUrl: a.cover, fit: BoxFit.cover))
                : CachedNetworkImage(imageUrl: a.cover, fit: BoxFit.cover),

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
                        imageUrl: a.cover, width: 50, height: 70, fit: BoxFit.cover),
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

  const _HypeMeterRow({required this.anime, required this.rank, required this.accentColor});

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

  @override
  Widget build(BuildContext context) {
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
                    imageUrl: a.cover, width: 34, height: 48, fit: BoxFit.cover),
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

  const _AnimeCard({required this.anime});

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
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 56, color: AppTheme.textMuted),
            const SizedBox(height: 12),
            Text('No results found',
                style: AppTheme.sans(
                    fontSize: 15,
                    color: AppTheme.textSecondary,
                    weight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('Try adjusting your filters',
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
                        style: AppTheme.sans(fontSize: 14, color: Colors.white, weight: FontWeight.w600)),
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
