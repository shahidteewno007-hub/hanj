import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';
import '../../core/trailer_launcher.dart';
import '../../models/anime_model.dart';
import '../../models/pulse_card.dart';
import '../../services/pulse_service.dart';
import '../../services/anilist_service.dart';
import '../../widgets/hanko_board.dart';
import '../../widgets/hanko_print.dart';
import '../anime_detail/anime_detail_screen.dart';

class PulseScreen extends StatefulWidget {
  const PulseScreen({super.key});

  @override
  State<PulseScreen> createState() => _PulseScreenState();
}

class _PulseScreenState extends State<PulseScreen>
    with SingleTickerProviderStateMixin {
  /// Vibes and Print Room for Pulse (r9; Shahid, 2026-11-10: "I loved new
  /// vibes change, if we can bring that change to other tabs/features
  /// wherever needed"): Hanko's washi and Shippori in place of the orange and
  /// the old ivory; printed tabs; a trailer on a field of its cover's own
  /// colour, the cover as a sharp print; the other cards as printed rows with
  /// their type as a printed label (no neon type colours); still placeholders
  /// in place of Shimmer, which moves even with Remove animations on. False
  /// gives back 07faabe's Pulse as it was.
  static const bool _printRoom = true;
  static const _printedTabs = ['For you', 'Trailers', 'Airing', 'Upcoming'];

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
    if (_printRoom) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text('Pulse', style: AppTheme.hankoSerif(fontSize: 28)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Text(
        'Pulse',
        style: AppTheme.shipporiMincho(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFF3EEE7),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    if (_printRoom) {
      // Printed tabs, the selected one washi, as Discover's.
      final still = MediaQuery.disableAnimationsOf(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
        child: AnimatedBuilder(
          animation: _tabController,
          builder: (context, _) => HankoTabStrip(
            labels: _printedTabs,
            selected: _tabController.index,
            onSelect: (i) => _tabController.animateTo(i,
                duration: still ? Duration.zero : null),
          ),
        ),
      );
    }
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
        labelStyle: AppTheme.jost(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
        unselectedLabelStyle: AppTheme.jost(
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
        if (cards.isEmpty) return _buildEmpty(cards);
        const printRoom = _PulseScreenState._printRoom;
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          color: printRoom ? AppTheme.hankoWashi : const Color(0xFFF97316),
          backgroundColor: printRoom ? AppTheme.hankoSumi2 : AppTheme.surface,
          child: ListView.builder(
            padding: printRoom
                ? const EdgeInsets.fromLTRB(20, 4, 20, 32)
                : const EdgeInsets.fromLTRB(16, 4, 16, 32),
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

  // Print Room (r9): rows as blank paper while the feed loads, and still
  // (Shimmer moves even with Remove animations on).
  Widget _printedLoading() {
    const corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 60,
                  height: 60 * hankoCoverRatio,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: AppTheme.hankoSumi3, borderRadius: corners),
                  ),
                ),
                const SizedBox(width: 14),
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
    );
  }

  Widget _buildShimmer() {
    if (_PulseScreenState._printRoom) return _printedLoading();
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

  // [cards] is this feed's own last result, so the message follows the
  // outcome of this feed's own fetch — not AnilistService's app-wide flag,
  // which a 200 anywhere else clears while this feed still holds a failure.
  Widget _buildEmpty(List<PulseCard> cards) {
    final failStatus = PulseService.instance.failStatusOf(cards);
    if (_PulseScreenState._printRoom) {
      // Print Room (r9): the same words and shape in Hanko's colours. The
      // shape stays, so landscape still overflows as before (WEB.md §10;
      // page_width_layout_test holds it).
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.emptyIcon, size: 44, color: AppTheme.hankoAsh),
              const SizedBox(height: 16),
              Text(
                AnilistService.messageFor(failStatus) ?? widget.emptyMessage,
                textAlign: TextAlign.center,
                style: AppTheme.hankoSans(
                    color: AppTheme.hankoStone, height: 1.6),
              ),
              if (widget.emptyAction) ...[
                const SizedBox(height: 24),
                TextButton(
                  onPressed: _refresh,
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.hankoWashi),
                  child: Text('Refresh',
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          weight: FontWeight.w600,
                          letterSpacing: 0.8)),
                ),
              ],
            ],
          ),
        ),
      );
    }
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
              AnilistService.messageFor(failStatus) ?? widget.emptyMessage,
              textAlign: TextAlign.center,
              style: AppTheme.jost(
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
                    style: AppTheme.jost(
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
                  style: AppTheme.shipporiMincho(
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

  // Print Room (r9): the trailer on a field of its cover's own colour
  // (AppTheme.hankoField, so washi on it keeps 5.69:1 or better), the cover
  // as a print with Vibes' keyline and hard shadow, sharp (its 460 px
  // version, as Home's heroes; the 230 px cover stretched across the card
  // was about 3× soft), the title in Shippori and a washi play mark, the
  // card's one action. On the field all text is washi.
  Widget _printed(BuildContext context) {
    final url = card.imageUrl;
    final reason = card.reason;
    const corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        container: true,
        button: true,
        label: ['Trailer', card.title, ?reason].join(', '),
        child: HankoCoverTint(
          urls: [url ?? ''],
          guard: false,
          builder: (context, colour) => Material(
            color: AppTheme.hankoField(colour) ?? AppTheme.hankoSumi2,
            borderRadius: corners,
            child: InkWell(
              onTap: () => _openTrailer(context),
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              borderRadius: corners,
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          color: AppTheme.hankoSumi,
                          borderRadius: corners,
                          boxShadow: [
                            BoxShadow(
                                color: Color(0x8C000000), offset: Offset(0, 3)),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.hankoKeyline),
                          child: HankoPrint(
                            url: url,
                            width: 84,
                            height: 84 * hankoCoverRatio,
                            lift: HankoPrintLift.none,
                            sharp: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('TRAILER',
                                style: HankoBoard.labelStyle(
                                    color: AppTheme.hankoWashi)),
                            const SizedBox(height: 6),
                            Text(
                              card.title,
                              maxLines: 3,
                              overflow: TextOverflow.fade,
                              style: AppTheme.hankoSerif(
                                  fontSize: 17, height: 1.25),
                            ),
                            if (reason != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                reason,
                                style: AppTheme.hankoSans(
                                    fontSize: AppTheme.hankoLabelSize,
                                    height: 1.35),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.hankoWashi,
                                    borderRadius: corners,
                                  ),
                                  child: const Icon(Icons.play_arrow_rounded,
                                      color: AppTheme.hankoSumi, size: 20),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Watch the trailer',
                                  style: AppTheme.hankoSans(
                                      fontSize: AppTheme.hankoMetaSize,
                                      weight: FontWeight.w500),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_PulseScreenState._printRoom) return _printed(context);
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
                    style: AppTheme.shipporiMincho(
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
                      style: AppTheme.jost(
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

  // Print Room (r9): a printed row: the cover as a printed card, the type as
  // a printed label in stone (the word says it; the neon colours only
  // repeated it, and NEW SEASON was coral), the title, what's new and why
  // it's here. One button for a screen reader.
  Widget _printed(BuildContext context) {
    final reason = card.reason;
    final type = _TypeBadge._labels[card.type] ?? '';
    return Semantics(
      container: true,
      button: true,
      label: [
        if (type.isNotEmpty) '${type[0]}${type.substring(1).toLowerCase()}',
        card.title,
        card.headline,
        ?reason,
      ].join(', '),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
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
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    height: 60 * hankoCoverRatio,
                    child: HankoCard(url: card.imageUrl),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (type.isNotEmpty) ...[
                          Text(type,
                              style: HankoBoard.labelStyle(
                                  color: AppTheme.hankoStone)),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          card.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoListTitleSize,
                            weight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          card.headline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: AppTheme.hankoStone,
                            height: 1.35,
                          ),
                        ),
                        if (reason != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoLabelSize,
                              color: AppTheme.hankoStoneHi,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
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

  @override
  Widget build(BuildContext context) {
    if (_PulseScreenState._printRoom) return _printed(context);
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
                      style: AppTheme.jost(
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
                      style: AppTheme.jost(
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
                          style: AppTheme.jost(
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
      style: AppTheme.jostTabular(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 1.1,
      ),
    );
  }
}
