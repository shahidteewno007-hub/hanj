import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/theme/app_theme.dart';
import '../../models/anime_model.dart';
import '../../services/anilist_service.dart';
import '../anime_detail/anime_detail_screen.dart';

// ─────────────────────────────────────────────────────────────
// Category data model — icon-based, no emojis
// ─────────────────────────────────────────────────────────────

class _Category {
  final IconData icon;
  final String name;
  final String tagline;
  final String genre;
  final String sort;
  final Color color;
  final Color bgColor;
  final bool isHiddenGems;

  const _Category({
    required this.icon,
    required this.name,
    required this.tagline,
    required this.genre,
    required this.sort,
    required this.color,
    required this.bgColor,
    this.isHiddenGems = false,
  });
}

const _categories = [
  // ── Hidden Gems — featured at top ──────────────────────────
  _Category(
    icon: Icons.diamond_outlined,
    name: 'Hidden Gems',
    tagline: 'Highly rated, rarely discussed',
    genre: 'Psychological',
    sort: 'SCORE_DESC',
    color: Color(0xFF818CF8),
    bgColor: Color(0xFF0C0A1E),
    isHiddenGems: true,
  ),
  // ── Core vibes ─────────────────────────────────────────────
  _Category(
    icon: Icons.bolt_rounded,
    name: 'Hype Machine',
    tagline: 'Gets the blood pumping',
    genre: 'Action',
    sort: 'TRENDING_DESC',
    color: Color(0xFFF97316),
    bgColor: Color(0xFF1E0A03),
  ),
  _Category(
    icon: Icons.water_drop_outlined,
    name: 'Emotional Journey',
    tagline: 'Feels that stay with you',
    genre: 'Drama',
    sort: 'SCORE_DESC',
    color: Color(0xFF60A5FA),
    bgColor: Color(0xFF060E1A),
  ),
  _Category(
    icon: Icons.hub_outlined,
    name: 'Mind-Bending',
    tagline: 'You won\'t see it coming',
    genre: 'Mystery',
    sort: 'SCORE_DESC',
    color: Color(0xFF818CF8),
    bgColor: Color(0xFF0C0A1E),
  ),
  _Category(
    icon: Icons.nightlight_round,
    name: 'Cozy Night',
    tagline: 'Slow down and stay awhile',
    genre: 'Slice of Life',
    sort: 'POPULARITY_DESC',
    color: Color(0xFFD4A96A),
    bgColor: Color(0xFF1A1004),
  ),
  _Category(
    icon: Icons.people_outline_rounded,
    name: 'Found Family',
    tagline: 'They chose each other',
    genre: 'Adventure',
    sort: 'SCORE_DESC',
    color: Color(0xFF34D399),
    bgColor: Color(0xFF041A0E),
  ),
  _Category(
    icon: Icons.bedtime_outlined,
    name: 'Tragic Masterpieces',
    tagline: 'Not every story needs light',
    genre: 'Horror',
    sort: 'SCORE_DESC',
    color: Color(0xFFF87171),
    bgColor: Color(0xFF1A0608),
  ),
  _Category(
    icon: Icons.auto_awesome_outlined,
    name: 'Peak Fiction',
    tagline: 'Certified masterpieces only',
    genre: 'Supernatural',
    sort: 'SCORE_DESC',
    color: Color(0xFFF97316),
    bgColor: Color(0xFF1A0A03),
  ),
  _Category(
    icon: Icons.explore_outlined,
    name: 'Deep Lore',
    tagline: 'Entire wikis exist for these',
    genre: 'Sci-Fi',
    sort: 'SCORE_DESC',
    color: Color(0xFF22D3EE),
    bgColor: Color(0xFF031418),
  ),
];

// ─────────────────────────────────────────────────────────────
// Main Tab Widget
// ─────────────────────────────────────────────────────────────

class EmotionalCategoriesTab extends StatefulWidget {
  const EmotionalCategoriesTab({super.key});

  @override
  State<EmotionalCategoriesTab> createState() => _EmotionalCategoriesTabState();
}

class _EmotionalCategoriesTabState extends State<EmotionalCategoriesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: _categories.length,
      itemBuilder: (_, i) => _CategoryRow(category: _categories[i]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Category Row
// ─────────────────────────────────────────────────────────────

class _CategoryRow extends StatefulWidget {
  final _Category category;
  const _CategoryRow({required this.category});

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  final _anilist = AnilistService();
  List<Anime> _anime = [];
  bool _loading = false;
  bool _expanded = false;
  bool _hasFetched = false;

  // ── Static cache keyed by category name — survives widget rebuilds ──
  static final Map<String, List<Anime>> _globalCache = {};

  @override
  void initState() {
    super.initState();
    // Seed from cache immediately — no re-fetch needed on rebuild
    final cached = _globalCache[widget.category.name];
    if (cached != null) {
      _anime     = cached;
      _hasFetched = true;
    }
  }

  Future<void> _load() async {
    if (_hasFetched) return; // already loaded, don't re-fetch
    setState(() => _loading = true);
    try {
      final results = await _anilist.searchAnime(
        '',
        genre: widget.category.genre,
        sort: widget.category.sort,
      );
      if (mounted) {
        setState(() {
          _anime = widget.category.isHiddenGems
              ? results.where((a) =>
                  a.averageScore != null && a.averageScore! >= 80).toList()
              : results;
          _loading = false;
          _hasFetched = true;
        });
        // Save to static cache so rebuild doesn't re-fetch
        if (_anime.isNotEmpty) {
          _globalCache[widget.category.name] = _anime;
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Category header ────────────────────────────────
          GestureDetector(
            onTap: () {
              setState(() => _expanded = !_expanded);
              if (!_hasFetched) _load();
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cat.bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: cat.color.withValues(alpha: 0.25)),
                // Hidden Gems gets a subtle glow to feel featured
                boxShadow: cat.isHiddenGems
                    ? [BoxShadow(
                        color: cat.color.withValues(alpha: 0.1),
                        blurRadius: 16,
                        spreadRadius: 0,
                      )]
                    : null,
              ),
              child: Row(
                children: [
                  // Icon in circle — no emojis
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cat.color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: cat.color.withValues(alpha: 0.2)),
                    ),
                    child: Icon(cat.icon, color: cat.color, size: 20),
                  ),
                  const SizedBox(width: 14),

                  // Name + tagline
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cat.name,
                          style: AppTheme.serif(
                              fontSize: 17,
                              weight: FontWeight.w600,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cat.tagline,
                          style: AppTheme.sans(
                              fontSize: 12,
                              color: cat.color.withValues(alpha: 0.75)),
                        ),
                      ],
                    ),
                  ),

                  // Count badge
                  if (_hasFetched && !_loading)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: cat.color.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        '${_anime.length}',
                        style: AppTheme.mono(
                            fontSize: 11,
                            color: cat.color,
                            letterSpacing: 0),
                      ),
                    ),
                  const SizedBox(width: 8),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: cat.color.withValues(alpha: 0.7), size: 20),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded anime list ────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: _loading
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Center(
                      child: CircularProgressIndicator(
                          color: cat.color, strokeWidth: 2),
                    ),
                  )
                : _anime.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text('No titles found',
                            style: AppTheme.sans(
                                color: AppTheme.textMuted)),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _anime.length,
                            itemBuilder: (_, i) => _AnimeCard(
                              anime: _anime[i],
                              accentColor: cat.color,
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Anime Card
// ─────────────────────────────────────────────────────────────

class _AnimeCard extends StatelessWidget {
  final Anime anime;
  final Color accentColor;

  const _AnimeCard({required this.anime, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => AnimeDetailScreen(anime: anime)),
      ),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    anime.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: anime.imageUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                Container(color: AppTheme.surfaceLight),
                          )
                        : Container(color: AppTheme.surfaceLight),

                    // Score badge
                    if (anime.averageScore != null)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded,
                                  color: accentColor, size: 10),
                              const SizedBox(width: 2),
                              Text(
                                (anime.averageScore! / 10)
                                    .toStringAsFixed(1),
                                style: TextStyle(
                                  color: accentColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              anime.titleEnglish ?? anime.title,
              style: AppTheme.sans(fontSize: 11, weight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
