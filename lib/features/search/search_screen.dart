import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../core/smooth_page_route.dart';
import '../../core/responsive.dart';
import '../../models/anime_model.dart';
import '../../services/anilist_service.dart';
import '../anime_detail/anime_detail_screen.dart';
import '../discovery/hanj_filter_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Search Screen — title, genre, format, year, sort, studio mode
// ─────────────────────────────────────────────────────────────────────────────

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _service    = AnilistService();
  final _textCtrl   = TextEditingController();
  late final _tabCtrl = TabController(length: 2, vsync: this);

  List<Anime> _results  = [];
  bool _loading         = false;
  bool _hasSearched     = false;
  String? _error;

  // ── Filters ───────────────────────────────────────────────
  String  _sort        = 'POPULARITY_DESC';
  String? _genre;
  String? _format;
  int?    _year;

  // Debounce
  int? _lastSearchMs;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Clear results when switching tabs — fires on tap AND swipe.
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) {
        _textCtrl.clear();
        setState(() { _results = []; _hasSearched = false; _error = null; });
      } else {
        // index settled after a swipe — refresh hint/filter visibility
        setState(() {});
      }
    });
    // Open the keyboard only AFTER the push transition finishes, so the
    // keyboard slide-up doesn't fight the page animation (that's the jank).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _focusNode.requestFocus();
      });
    });
  }

  // ── Constants ─────────────────────────────────────────────
  static const _sorts = [
    ('POPULARITY_DESC', 'Popular'),
    ('TRENDING_DESC',   'Trending'),
    ('SCORE_DESC',      'Top Rated'),
    ('START_DATE_DESC', 'Newest'),
  ];

  static const _genres = [
    'Action','Adventure','Comedy','Drama','Fantasy','Horror',
    'Mystery','Romance','Sci-Fi','Slice of Life','Sports',
    'Supernatural','Thriller','Mecha','Music','Psychological',
  ];

  static const _formats = [
    ('TV',    'TV Series'),
    ('MOVIE', 'Movie'),
    ('ONA',   'ONA'),
    ('OVA',   'OVA'),
  ];

  int get _activeFilterCount =>
      (_genre != null ? 1 : 0) +
      (_format != null ? 1 : 0) +
      (_year != null ? 1 : 0) +
      (_sort != 'POPULARITY_DESC' ? 1 : 0);

  @override
  void dispose() {
    _textCtrl.dispose();
    _tabCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────

  /// AniList's exact genre strings (case-sensitive on their API)
  static const _knownGenres = {
    'action': 'Action', 'adventure': 'Adventure', 'comedy': 'Comedy',
    'drama': 'Drama', 'ecchi': 'Ecchi', 'fantasy': 'Fantasy',
    'horror': 'Horror', 'mecha': 'Mecha', 'music': 'Music',
    'mystery': 'Mystery', 'psychological': 'Psychological',
    'romance': 'Romance', 'sci-fi': 'Sci-Fi', 'scifi': 'Sci-Fi',
    'slice of life': 'Slice of Life', 'sports': 'Sports',
    'supernatural': 'Supernatural', 'thriller': 'Thriller',
  };

  Future<void> _search(String query, {bool isStudio = false}) async {
    final q = query.trim();
    if (q.isEmpty && _genre == null && _format == null && _year == null) {
      setState(() { _results = []; _hasSearched = false; _error = null; });
      return;
    }

    setState(() { _loading = true; _hasSearched = true; _error = null; });

    try {
      List<Anime> results;
      if (isStudio) {
        results = await _service.searchByStudio(q);
      } else {
        // If the typed text exactly matches a known genre, treat it as a
        // genre filter instead of a title search (better intent matching).
        final matchedGenre = _knownGenres[q.toLowerCase()];
        final useAsGenre = matchedGenre != null && _genre == null;

        results = await _service.searchAnime(
          useAsGenre ? '' : q,
          genre:  useAsGenre ? matchedGenre : _genre,
          format: _format,
          year:   _year,
          sort:   _sort,
        );
      }
      if (mounted) setState(() { _results = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onTextChanged(String value) {
    if (value.isEmpty) {
      setState(() { _results = []; _hasSearched = false; });
      return;
    }
    if (value.length < 2) return;
    final t = DateTime.now().millisecondsSinceEpoch;
    _lastSearchMs = t;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && _lastSearchMs == t) {
        _search(value, isStudio: _tabCtrl.index == 1);
      }
    });
  }

  void _clearFilters() {
    setState(() { _genre = null; _format = null; _year = null; _sort = 'POPULARITY_DESC'; });
    if (_hasSearched) _search(_textCtrl.text, isStudio: _tabCtrl.index == 1);
  }

  // ── Filter Sheet ──────────────────────────────────────────

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HanjFilterSheet(
        genre:  _genre,
        format: _format,
        year:   _year,
        onApply: (genre, format, year) {
          setState(() {
            _genre  = genre;
            _format = format;
            _year   = year;
          });
          if (_textCtrl.text.isNotEmpty || genre != null) {
            _search(_textCtrl.text, isStudio: _tabCtrl.index == 1);
          }
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  // ── ANIME tab (with filter row) ──
                  Column(
                    children: [
                      if (_activeFilterCount > 0) _buildActiveFilters(),
                      Expanded(child: _buildBody()),
                    ],
                  ),
                  // ── STUDIO tab ──
                  _buildBody(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: TextField(
              controller: _textCtrl,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onChanged: _onTextChanged,
              onSubmitted: (v) => _search(v, isStudio: _tabCtrl.index == 1),
              style: AppTheme.sans(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: _tabCtrl.index == 0
                    ? 'Search anime title...'
                    : 'Search by studio name...',
                hintStyle: AppTheme.sans(fontSize: 14, color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.textMuted, size: 18),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textCtrl,
                  builder: (_, value, __) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded,
                              color: AppTheme.textMuted, size: 18),
                          onPressed: () {
                            _textCtrl.clear();
                            setState(() { _results = []; _hasSearched = false; });
                          },
                        ),
                ),
                filled: true,
                fillColor: AppTheme.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Filter button — only show on anime tab
          if (_tabCtrl.index == 0)
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.tune_rounded,
                      color: AppTheme.textSecondary, size: 20),
                  onPressed: _showFilters,
                ),
                if (_activeFilterCount > 0)
                  Positioned(
                    top: 6, right: 6,
                    child: Container(
                      width: 16, height: 16,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$_activeFilterCount',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return TabBar(
      controller: _tabCtrl,
      indicatorColor: AppTheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      labelColor: AppTheme.primary,
      unselectedLabelColor: AppTheme.textMuted,
      labelStyle: AppTheme.mono(fontSize: 11, letterSpacing: 1),
      tabs: const [
        Tab(text: 'ANIME'),
        Tab(text: 'STUDIO'),
      ],
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (_sort != 'POPULARITY_DESC')
                  _FilterPill(
                    label: _sorts.firstWhere((s) => s.$1 == _sort).$2,
                    onRemove: () { setState(() => _sort = 'POPULARITY_DESC'); if (_hasSearched) _search(_textCtrl.text); },
                  ),
                if (_genre != null)
                  _FilterPill(
                    label: _genre!,
                    onRemove: () { setState(() => _genre = null); if (_hasSearched) _search(_textCtrl.text); },
                  ),
                if (_format != null)
                  _FilterPill(
                    label: _formats.firstWhere((f) => f.$1 == _format).$2,
                    onRemove: () { setState(() => _format = null); if (_hasSearched) _search(_textCtrl.text); },
                  ),
                if (_year != null)
                  _FilterPill(
                    label: '$_year',
                    onRemove: () { setState(() => _year = null); if (_hasSearched) _search(_textCtrl.text); },
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: _clearFilters,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
            ),
            child: Text('Clear all',
                style: AppTheme.sans(fontSize: 11, color: AppTheme.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return _buildShimmer();
    if (_error != null) return _buildError();
    if (!_hasSearched) return _buildEmptyState();
    if (_results.isEmpty) return _buildNoResults();
    return _buildGrid();
  }

  Widget _buildGrid() {
    return GridView.builder(
      padding: EdgeInsets.all(Responsive.getHorizontalPadding(context)),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: Responsive.getGridColumns(context),
        childAspectRatio: 0.58,
        crossAxisSpacing: Responsive.isMobile(context) ? 10 : 12,
        mainAxisSpacing: Responsive.isMobile(context) ? 10 : 12,
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) =>
          // Keyed by media id: _results is replaced wholesale on every query,
          // so index matching would leave a card's state on a different anime.
          _AnimeCard(key: ValueKey(_results[i].id), anime: _results[i]),
    );
  }

  Widget _buildEmptyState() {
    final isAnime = _tabCtrl.index == 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Glowing icon
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.08),
                border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.25), width: 1),
              ),
              child: Icon(
                isAnime ? Icons.manage_search_rounded : Icons.business_rounded,
                color: AppTheme.primary,
                size: 42,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isAnime ? 'Search for anime' : 'Search by studio',
              style: AppTheme.serif(
                  fontSize: 22, color: AppTheme.textPrimary, weight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              isAnime
                  ? 'Find by title, filter by genre,\nformat, year and more'
                  : 'Discover everything a studio\nhas ever animated',
              textAlign: TextAlign.center,
              style: AppTheme.sans(fontSize: 13.5, color: AppTheme.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded,
              color: AppTheme.textMuted, size: 64),
          const SizedBox(height: 16),
          Text('No results found',
              style: AppTheme.sans(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                  weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            _activeFilterCount > 0
                ? 'Try removing some filters'
                : 'Try different keywords',
            style: AppTheme.sans(fontSize: 13, color: AppTheme.textMuted),
          ),
          if (_activeFilterCount > 0) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: _clearFilters,
              child: Text('Clear filters',
                  style: AppTheme.sans(color: AppTheme.primary, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.error, size: 64),
          const SizedBox(height: 16),
          Text('Something went wrong',
              style: AppTheme.sans(
                  fontSize: 16,
                  color: AppTheme.textSecondary,
                  weight: FontWeight.w600)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _search(_textCtrl.text, isStudio: _tabCtrl.index == 1),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return GridView.builder(
      padding: EdgeInsets.all(Responsive.getHorizontalPadding(context)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: Responsive.getGridColumns(context),
        childAspectRatio: 0.58,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: 12,
      itemBuilder: (_, _) => _ShimmerCard(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final String sort;
  final String? genre;
  final String? format;
  final int? year;
  final void Function(String sort, String? genre, String? format, int? year) onApply;

  const _FilterSheet({
    required this.sort, required this.genre,
    required this.format, required this.year,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String  _sort;
  late String? _genre;
  late String? _format;
  late int?    _year;

  static const _sorts = [
    ('POPULARITY_DESC', 'Popular'),
    ('TRENDING_DESC',   'Trending'),
    ('SCORE_DESC',      'Top Rated'),
    ('START_DATE_DESC', 'Newest'),
  ];

  static const _genres = [
    'Action','Adventure','Comedy','Drama','Fantasy','Horror',
    'Mystery','Romance','Sci-Fi','Slice of Life','Sports',
    'Supernatural','Thriller','Mecha','Music','Psychological',
  ];

  static const _formats = [
    ('TV',    'TV'),
    ('MOVIE', 'Movie'),
    ('ONA',   'ONA'),
    ('OVA',   'OVA'),
  ];

  final _currentYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _sort   = widget.sort;
    _genre  = widget.genre;
    _format = widget.format;
    _year   = widget.year;
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
                      style: AppTheme.serif(
                          fontSize: 18, weight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _sort = 'POPULARITY_DESC';
                      _genre = null; _format = null; _year = null;
                    }),
                    child: Text('Reset',
                        style: AppTheme.sans(
                            color: AppTheme.textMuted, fontSize: 13)),
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.border, height: 1),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  _sectionLabel('Sort By'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _sorts.map((s) => _SelectChip(
                      label: s.$2,
                      selected: _sort == s.$1,
                      onTap: () => setState(() => _sort = s.$1),
                    )).toList(),
                  ),

                  const SizedBox(height: 20),
                  _sectionLabel('Genre'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _genres.map((g) => _SelectChip(
                      label: g,
                      selected: _genre == g,
                      onTap: () => setState(
                          () => _genre = _genre == g ? null : g),
                    )).toList(),
                  ),

                  const SizedBox(height: 20),
                  _sectionLabel('Format'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _formats.map((f) => _SelectChip(
                      label: f.$2,
                      selected: _format == f.$1,
                      onTap: () => setState(
                          () => _format = _format == f.$1 ? null : f.$1),
                    )).toList(),
                  ),

                  const SizedBox(height: 20),
                  _sectionLabel('Year'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: List.generate(8, (i) {
                      final y = _currentYear - i;
                      return _SelectChip(
                        label: '$y',
                        selected: _year == y,
                        onTap: () => setState(
                            () => _year = _year == y ? null : y),
                      );
                    }),
                  ),
                ],
              ),
            ),
            // Apply button
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => widget.onApply(_sort, _genre, _format, _year),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Apply Filters',
                        style: AppTheme.sans(
                            fontSize: 14,
                            color: Colors.white,
                            weight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: AppTheme.mono(
        fontSize: 10,
        color: AppTheme.textMuted,
        letterSpacing: 1.5),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectChip({
    required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.15)
              : AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.sans(
            fontSize: 12,
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            weight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _FilterPill({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: AppTheme.sans(
                  fontSize: 11,
                  color: AppTheme.primary,
                  weight: FontWeight.w500)),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                color: AppTheme.primary, size: 14),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Anime Card
// ─────────────────────────────────────────────────────────────────────────────

class _AnimeCard extends StatelessWidget {
  final Anime anime;
  const _AnimeCard({super.key, required this.anime});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        SmoothPageRoute(page: AnimeDetailScreen(anime: anime)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Hero(
                tag: 'anime_${anime.id}',
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                  child: CachedNetworkImage(
                    imageUrl: anime.imageUrl ?? '',
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(
                      color: AppTheme.surfaceLight,
                      child: const Center(
                        child: Icon(Icons.image_outlined,
                            color: AppTheme.textMuted, size: 40),
                      ),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: AppTheme.surfaceLight,
                      child: const Center(
                        child: Icon(Icons.broken_image_outlined,
                            color: AppTheme.textMuted, size: 40),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anime.titleEnglish ?? anime.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.sans(
                      fontSize: 11,
                      color: AppTheme.textPrimary,
                      weight: FontWeight.w600,
                    ),
                  ),
                  if (anime.averageScore != null) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFFD166), size: 12),
                        const SizedBox(width: 3),
                        Text(
                          (anime.averageScore! / 10).toStringAsFixed(1),
                          style: AppTheme.mono(
                              fontSize: 10,
                              color: AppTheme.textSecondary),
                        ),
                        if (anime.format != null) ...[
                          Text('  ·  ',
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 10)),
                          Text(
                            anime.format!,
                            style: AppTheme.mono(
                                fontSize: 9,
                                color: AppTheme.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ],
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
// Shimmer Card
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Expanded(
            child: Shimmer.fromColors(
              baseColor: AppTheme.surfaceLight,
              highlightColor: AppTheme.surface,
              child: Container(
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(16)),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Shimmer.fromColors(
                  baseColor: AppTheme.surfaceLight,
                  highlightColor: AppTheme.surface,
                  child: Container(
                    height: 12, width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Shimmer.fromColors(
                  baseColor: AppTheme.surfaceLight,
                  highlightColor: AppTheme.surface,
                  child: Container(
                    height: 10, width: 50,
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
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
