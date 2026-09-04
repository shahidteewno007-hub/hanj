import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/trailer_launcher.dart';
import '../../models/anime_model.dart';
import '../../models/pulse_card.dart';
import '../../services/pulse_service.dart';
import '../anime_detail/anime_detail_screen.dart';

class PulseScreen extends StatefulWidget {
  const PulseScreen({super.key});

  @override
  State<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends State<PulseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PulseTabView(
                  loader: (r) => PulseService.instance.getForYou(forceRefresh: r),
                  emptyIcon: Icons.person_search_outlined,
                  emptyMessage:
                      'Add anime to your list and Pulse will personalise\nthis feed just for you.',
                  emptyAction: true,
                ),
                _PulseTabView(
                  loader: (r) => PulseService.instance.getTrailers(forceRefresh: r),
                  emptyIcon: Icons.play_circle_outline_rounded,
                  emptyMessage: 'No trailers available right now.\nCheck back soon.',
                ),
                _PulseTabView(
                  loader: (r) => PulseService.instance.getAiring(forceRefresh: r),
                  emptyIcon: Icons.tv_outlined,
                  emptyMessage: 'Nothing seems to be airing right now.',
                ),
                _PulseTabView(
                  loader: (r) => PulseService.instance.getUpcoming(forceRefresh: r),
                  emptyIcon: Icons.calendar_today_outlined,
                  emptyMessage: 'No upcoming titles found.',
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        'Pulse',
        style: GoogleFonts.playfairDisplay(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFF3EEE7),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: const Color(0xFFF97316),
        indicatorWeight: 2,
        indicatorSize: TabBarIndicatorSize.label,
        labelColor: const Color(0xFFF97316),
        unselectedLabelColor: const Color(0xFFF3EEE7).withOpacity(0.45),
        labelStyle: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
        unselectedLabelStyle: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
        dividerColor: Colors.transparent,
        tabs: const [
          Tab(text: 'FOR YOU'),
          Tab(text: 'TRAILERS'),
          Tab(text: 'AIRING'),
          Tab(text: 'UPCOMING'),
        ],
      ),
    );
  }
}

// ── Tab view ──────────────────────────────────────────────────

class _PulseTabView extends StatefulWidget {
  final Future<List<PulseCard>> Function(bool forceRefresh) loader;
  final IconData emptyIcon;
  final String emptyMessage;
  final bool emptyAction;

  const _PulseTabView({
    required this.loader,
    required this.emptyIcon,
    required this.emptyMessage,
    this.emptyAction = false,
  });

  @override
  State<_PulseTabView> createState() => _PulseTabViewState();
}

class _PulseTabViewState extends State<_PulseTabView>
    with AutomaticKeepAliveClientMixin {
  late Future<List<PulseCard>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = widget.loader(false);
  }

  void _refresh() => setState(() => _future = widget.loader(true));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<PulseCard>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _buildShimmer();
        }
        final cards = snap.data ?? [];
        if (cards.isEmpty) return _buildEmpty();
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          color: const Color(0xFFF97316),
          backgroundColor: AppTheme.surface,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            itemCount: cards.length,
            itemBuilder: (context, i) {
              final card = cards[i];
              return card.type == PulseCardType.trailer
                  ? _TrailerCard(card: card)
                  : _StandardCard(card: card);
            },
          ),
        );
      },
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: 6,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: const Color(0xFF1A1A1A),
          highlightColor: const Color(0xFF252525),
          child: Container(
            height: 96,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.emptyIcon,
                size: 44,
                color: const Color(0xFFF3EEE7).withOpacity(0.18)),
            const SizedBox(height: 16),
            Text(
              widget.emptyMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: const Color(0xFFF3EEE7).withOpacity(0.40),
                height: 1.6,
              ),
            ),
            if (widget.emptyAction) ...[
              const SizedBox(height: 24),
              TextButton(
                onPressed: _refresh,
                style:
                    TextButton.styleFrom(foregroundColor: const Color(0xFFF97316)),
                child: Text('Refresh',
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Trailer card ──────────────────────────────────────────────
// On mobile: tap → TrailerPlayerScreen (full-screen dedicated route).
// On web:    tap → bottom sheet with inline TrailerButton iframe.

class _TrailerCard extends StatelessWidget {
  final PulseCard card;
  const _TrailerCard({required this.card});

  void _openTrailer(BuildContext context) {
    final trailerUrl = card.payload['trailerUrl'] as String?;
    if (trailerUrl == null) return;

    if (kIsWeb) {
      showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF111111),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(card.title,
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF3EEE7))),
              const SizedBox(height: 12),
              TrailerButton(trailerUrl: trailerUrl),
            ],
          ),
        ),
      );
    } else {
      final videoId = extractYouTubeId(trailerUrl);
      if (videoId == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TrailerPlayerScreen(videoId: videoId),
          fullscreenDialog: true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openTrailer(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF141414),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (card.imageUrl != null)
              CachedNetworkImage(
                imageUrl: card.imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    Colors.black.withOpacity(0.15),
                    Colors.black.withOpacity(0.82),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _TypeBadge(type: card.type),
                  const SizedBox(height: 8),
                  Text(
                    card.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF3EEE7),
                      height: 1.2,
                    ),
                  ),
                  if (card.reason != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      card.reason!,
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: const Color(0xFFF3EEE7).withOpacity(0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFF3EEE7).withOpacity(0.6),
                    width: 1.5,
                  ),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Color(0xFFF3EEE7), size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Standard card ─────────────────────────────────────────────

class _StandardCard extends StatelessWidget {
  final PulseCard card;
  const _StandardCard({required this.card});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnimeDetailScreen(
            anime: Anime(
              id: card.animeId,
              title: card.title,
              imageUrl: card.imageUrl,
              genres: const [],
            ),
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E1E1E), width: 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              child: SizedBox(
                width: 68,
                height: 96,
                child: card.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: card.imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholder(),
                      )
                    : _placeholder(),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TypeBadge(type: card.type),
                    const SizedBox(height: 6),
                    Text(
                      card.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF3EEE7),
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      card.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: const Color(0xFFF3EEE7).withOpacity(0.55),
                      ),
                    ),
                    if (card.reason != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFF97316).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          card.reason!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color:
                                const Color(0xFFF97316).withOpacity(0.9),
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right_rounded,
                  color: Color(0xFF3A3A3A), size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF1A1A1A),
        child: const Icon(Icons.image_outlined,
            color: Color(0xFF2E2E2E), size: 24),
      );
}

// ── Type badge ─────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final PulseCardType type;
  const _TypeBadge({required this.type});

  static const _labels = {
    PulseCardType.trailer: 'TRAILER',
    PulseCardType.airingSoon: 'AIRING SOON',
    PulseCardType.nowAiring: 'AIRING',
    PulseCardType.newSeason: 'NEW SEASON',
    PulseCardType.upcoming: 'UPCOMING',
  };

  static const _colors = {
    PulseCardType.trailer: Color(0xFF4A90E2),
    PulseCardType.airingSoon: Color(0xFFF97316),
    PulseCardType.nowAiring: Color(0xFF34C759),
    PulseCardType.newSeason: Color(0xFFE8624A),
    PulseCardType.upcoming: Color(0xFF8A8A8A),
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[type] ?? '';
    final color = _colors[type] ?? const Color(0xFF8A8A8A);
    return Text(
      label,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 1.1,
      ),
    );
  }
}
