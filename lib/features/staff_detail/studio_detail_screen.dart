import 'package:flutter/material.dart';

import 'dart:math' as math;

import '../../core/theme/app_theme.dart';
import '../../services/anilist_service.dart';
import '../../widgets/hanko_board.dart';
import '../../widgets/hover_anime_card.dart';
import '../../models/anime_model.dart';
import '../anime_detail/anime_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class StudioDetailScreen extends StatefulWidget {
  final String studioName;

  const StudioDetailScreen({
    super.key,
    required this.studioName,
  });

  @override
  State<StudioDetailScreen> createState() => _StudioDetailScreenState();
}

class _StudioDetailScreenState extends State<StudioDetailScreen> {
  /// Vibes for the Studio page (Print Room, r9; Shahid, 2026-11-10: "I loved
  /// new vibes change, if we can bring that change to other tabs/features
  /// wherever needed"): the studio's work opens on its own board, three of
  /// its covers standing shoulder to shoulder on a tint taken from them, then
  /// printed posters (no stars, no coral glow, no coral count). False gives
  /// back 07faabe's page as it was.
  static const bool _printRoom = true;
  // The first time a studio's board shows in a session, its hand deals in.
  static final Set<String> _dealt = {};
  late final bool _dealIn = _dealt.add(widget.studioName);

  final _aniListService = AnilistService();
  List<Anime> _animeList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStudioAnime();
  }

  Future<void> _loadStudioAnime() async {
    setState(() => _isLoading = true);
    try {
      // Try exact match first, then partial
      var results = await _aniListService.searchByStudio(widget.studioName);
      // If no results, try with just the first word (e.g. "WIT STUDIO" → "WIT")
      if (results.isEmpty && widget.studioName.contains(' ')) {
        results = await _aniListService.searchByStudio(
            widget.studioName.split(' ').first);
      }
      if (!mounted) return;
      setState(() {
        _animeList = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // How many posters fit across, and how wide each is: three at least.
  static (int, double) _columnsFor(double width) {
    const gutter = 20.0, gap = 12.0;
    final inner = width - 2 * gutter;
    final columns = math.max(3, ((inner + gap) / (132 + gap)).floor());
    return (columns, (inner - gap * (columns - 1)) / columns);
  }

  // ── Print Room (r9) ───────────────────────────────────────
  Widget _printed(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    const corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));
    final n = _animeList.length;
    final Widget body;
    if (_isLoading) {
      // The board and two rows of posters as blank paper while they load.
      body = LayoutBuilder(builder: (context, constraints) {
        final (columns, width) = _columnsFor(constraints.maxWidth);
        return ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          children: [
            const SizedBox(
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: AppTheme.hankoSumi2, borderRadius: corners),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
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
    } else if (n == 0) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const HankoEmptyHand(),
              const SizedBox(height: 20),
              Text(
                'No anime found from ${widget.studioName}',
                textAlign: TextAlign.center,
                style: AppTheme.hankoSerif(
                    fontSize: AppTheme.hankoFeaturedSize, height: 1.25),
              ),
            ],
          ),
        ),
      );
    } else {
      final covers = [for (final a in _animeList.take(3)) a.imageUrl ?? ''];
      final poses = [
        for (final p in HankoPose.level)
          if (p.cover < covers.length) p,
      ];
      body = LayoutBuilder(builder: (context, constraints) {
        final (columns, width) = _columnsFor(constraints.maxWidth);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Semantics(
                  container: true,
                  label: '${widget.studioName}. Their work, highest rated '
                      'first. $n ${n == 1 ? 'title' : 'titles'}',
                  child: ExcludeSemantics(
                    child: HankoCoverTint(
                      urls: covers,
                      builder: (context, tint) => HankoBoard(
                        tint: tint,
                        face: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.studioName,
                                      style: AppTheme.hankoSerif(
                                          fontSize: AppTheme.hankoFeaturedSize,
                                          height: 1.2),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Their work, highest rated first',
                                      style: AppTheme.hankoSans(
                                        fontSize: AppTheme.hankoMetaSize,
                                        color: AppTheme.hankoStoneHi,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '$n ${n == 1 ? 'TITLE' : 'TITLES'} · BY\u00A0SCORE',
                                      style: HankoBoard.labelStyle(),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              HankoHand(
                                poses: poses,
                                urls: covers,
                                coverWidth: 44,
                                lifted: false,
                                dealIn: _dealIn && !still,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  mainAxisExtent: HankoPoster.heightFor(width, scaler),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final anime = _animeList[i];
                    return HankoPoster(
                      key: ValueKey(anime.id),
                      url: anime.imageUrl,
                      title: anime.titleEnglish ?? anime.title,
                      score: anime.averageScore,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnimeDetailScreen(anime: anime),
                        ),
                      ),
                    );
                  },
                  childCount: n,
                ),
              ),
            ),
          ],
        );
      });
    }
    return Scaffold(
      backgroundColor: AppTheme.hankoSumi,
      appBar: AppBar(
        backgroundColor: AppTheme.hankoSumi,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Studio',
          style: HankoBoard.labelStyle(color: AppTheme.hankoStone),
        ),
      ),
      body: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_printRoom) return _printed(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.studioName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Studio',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _animeList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.search_off_rounded,
                          size: 64, color: AppTheme.textMuted),
                      const SizedBox(height: 16),
                      Text('No anime found from ${widget.studioName}',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Anime by ${widget.studioName}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              // 12% coral, so the coral count reads at 4.93:1
                              // on sumi (AA). A 20% fill measured 4.38:1.
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_animeList.length} titles',
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.6,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _animeList.length,
                          itemBuilder: (context, index) {
                            final anime = _animeList[index];
                            return HoverAnimeCard(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AnimeDetailScreen(anime: anime),
                                  ),
                                );
                              },
                              glowColor: AppTheme.primary,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.cardBorder),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CachedNetworkImage(
                                        imageUrl: anime.imageUrl ?? '',
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) =>
                                            Container(
                                          color: AppTheme.surfaceLight,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                                Colors.transparent,
                                                Colors.black
                                                    .withValues(alpha: 0.9),
                                              ],
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                anime.title,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (anime.averageScore != null) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(Icons.star_rounded,
                                                        color: Colors.amber,
                                                        size: 12),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      (anime.averageScore! / 10)
                                                          .toStringAsFixed(1),
                                                      style: const TextStyle(
                                                        color: Colors.amber,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
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
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
