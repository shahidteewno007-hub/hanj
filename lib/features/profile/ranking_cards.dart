import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../widgets/gal_mobile.dart' if (dart.library.html) '../../widgets/gal_stub.dart' as galSaver;

import '../../core/theme/app_theme.dart';
import '../../widgets/hanko_seal.dart';
import 'taste_profile.dart';

// ─────────────────────────────────────────────────────────────
// Ranking Cards Screen
// ─────────────────────────────────────────────────────────────

class RankingCardsScreen extends StatefulWidget {
  const RankingCardsScreen({super.key});

  @override
  State<RankingCardsScreen> createState() => _RankingCardsScreenState();
}

class _RankingCardsScreenState extends State<RankingCardsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<_AnimeEntry> _allAnime = [];
  bool _isLoading = true;
  String _username = '';

  /// The list couldn't be read (question 97).
  bool _failed = false;

  /// Your list as the Taste page reads it (TasteAnalyzer), for the Taste
  /// Card's archetype; null until the list is read, and for an empty one.
  TasteProfile? _taste;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _isLoading = false); return; }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      _username = userDoc.data()?['displayName'] as String? ?? 'Anime Fan';

      final snap = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('animeList').get();

      _allAnime = snap.docs.map((d) {
        final data = d.data();
        return _AnimeEntry(
          title:      data['title'] as String? ?? '',
          imageUrl:   data['imageUrl'] as String?,
          rating:     (data['userRating'] as num?)?.toDouble(),
          status:     data['status'] as String? ?? '',
          genres:     (data['genres'] as List<dynamic>?)?.cast<String>() ?? [],
          addedAt:    (data['addedAt'] as Timestamp?)?.toDate(),
        );
      }).toList();
      _taste = snap.docs.isEmpty ? null : TasteAnalyzer.analyze(snap.docs);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _failed = false;
        });
      }
    } catch (_) {
      // Said as a failure (question 97). It showed each card's empty state,
      // as if the list were empty.
      if (mounted) {
        setState(() {
          _isLoading = false;
          _failed = true;
        });
      }
    }
  }

  /// Reads the list again, from the spinner.
  void _retry() {
    setState(() {
      _isLoading = true;
      _failed = false;
    });
    _load();
  }

  /// Your nine highest ratings on Hanj's 1–10 scale (question 96), as
  /// Profile's favourites and Advanced Stats count them. An imported rating
  /// on another scale (D20: a 70 from a 100-point list) ranked first here,
  /// above every 10; it's left out, and [_offScale] says how many were.
  List<_AnimeEntry> get _top9 {
    final rated = _allAnime
        .where((a) =>
            a.rating != null &&
            _Top9Place._onScale(a.rating!) &&
            a.imageUrl != null)
        .toList()
      ..sort((a, b) => b.rating!.compareTo(a.rating!));
    return rated.take(9).toList();
  }

  /// How many of your ratings are on another scale (imported).
  int get _offScale => _allAnime
      .where((a) => a.rating != null && !_Top9Place._onScale(a.rating!))
      .length;

  List<_AnimeEntry> get _monthlyAnime {
    final now = DateTime.now();
    return _allAnime
        .where((a) =>
            a.addedAt != null &&
            a.addedAt!.month == now.month &&
            a.addedAt!.year == now.year &&
            a.imageUrl != null)
        .toList();
  }

  Map<String, int> get _genreMap {
    final map = <String, int>{};
    for (final a in _allAnime) {
      for (final g in a.genres) {
        map[g] = (map[g] ?? 0) + 1;
      }
    }
    return map;
  }

  /// The three cards as they were before Hanko (coral, gold, silver and
  /// bronze, gradients, a glow and rounded corners), kept switched off as
  /// design history. Each tab's old body is its _buildPreHanko().
  static const bool _preHanko = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_sharp),
          color: AppTheme.hankoWashi,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Ranking Cards', style: AppTheme.hankoSerif(fontSize: 20)),
        // Detail's tabs in Hanko: Jost 13, washi and w600 for the card you're
        // on, stone for the others, a washi rule under it and the screen's
        // one hairline below. Coral is only your seal now, so it marks no
        // tab. Each label stays on one line and shrinks to its tab when large
        // text would cut it ("Monthly Aura" at 1.3x), as Detail's do.
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.hankoWashi,
          unselectedLabelColor: AppTheme.hankoStone,
          labelStyle: AppTheme.hankoSans(
              fontSize: 13, weight: FontWeight.w600),
          unselectedLabelStyle: AppTheme.hankoSans(fontSize: 13),
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: AppTheme.hankoWashi, width: 2),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: AppTheme.hankoHairline,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(AppTheme.hankoPressWash),
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          tabs: [
            for (final label in const ['Top 9', 'Taste Card', 'Monthly Aura'])
              Tab(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label, maxLines: 1, softWrap: false),
                ),
              ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(
              color: AppTheme.hankoWashi, strokeWidth: 2))
          : _failed
              // One read fills all three cards, so each card's page says it
              // failed, with Retry, and the tabs still swipe.
              ? TabBarView(
                  controller: _tabController,
                  children: List.generate(
                      3, (_) => _HankoListFailed(onRetry: _retry)),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _Top9Tab(
                        anime: _top9,
                        username: _username,
                        offScale: _offScale),
                    _TasteCardTab(
                        allAnime: _allAnime,
                        genreMap: _genreMap,
                        username: _username,
                        taste: _taste),
                    _MonthlyAuraTab(
                        anime: _monthlyAnime, username: _username),
                  ],
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Top 9 Tab
// ─────────────────────────────────────────────────────────────

class _Top9Tab extends StatelessWidget {
  final List<_AnimeEntry> anime;
  final String username;

  /// Imported ratings on another scale, which the Top 9 leaves out.
  final int offScale;
  final _repaintKey = GlobalKey();

  _Top9Tab({
    required this.anime,
    required this.username,
    required this.offScale,
  });

  /// What the Top 9 leaves out, said under it (question 96) in Profile's
  /// words for its seal register. Shown on the page, never in the image.
  String? get _note => offScale == 0
      ? null
      : offScale == 1
          ? '1 imported rating is on another scale, so it isn\'t ranked\u00A0here.'
          : '$offScale imported ratings are on another scale, so they '
              'aren\'t ranked\u00A0here.';

  @override
  Widget build(BuildContext context) {
    if (_RankingCardsScreenState._preHanko) return _buildPreHanko();
    if (anime.isEmpty) {
      // What the card is for. With only imported ratings, the note says why
      // none of them is here.
      return _HankoEmpty(
        title: 'Your Top 9',
        line: 'Your nine highest-rated shows, as one image to save and '
            'share. It\'s made from the ratings on your list.',
        note: _note,
      );
    }
    return _PrintPage(
      repaintKey: _repaintKey,
      filename: 'hanj_top9',
      card: _Top9Print(anime: anime, username: username),
      note: _note,
    );
  }

  /// The tab before Hanko (_RankingCardsScreenState._preHanko).
  Widget _buildPreHanko() {
    if (anime.isEmpty) {
      return _EmptyState(
        message: 'Rate at least 9 anime to generate your Top 9 grid',
        emoji: '🏆',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Preview
          RepaintBoundary(
            key: _repaintKey,
            child: _Top9Card(anime: anime, username: username),
          ),
          const SizedBox(height: 24),
          _SaveButton(repaintKey: _repaintKey, filename: 'hanj_top9'),
        ],
      ),
    );
  }
}

class _Top9Card extends StatelessWidget {
  final List<_AnimeEntry> anime;
  final String username;

  const _Top9Card({required this.anime, required this.username});

  @override
  Widget build(BuildContext context) {
    final items = anime.take(9).toList();
    while (items.length < 9) {
      items.add(_AnimeEntry(title: '', imageUrl: null, status: ''));
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121110),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.3),
                    const Color(0xFF121110),
                  ],
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18, height: 18,
                    child: Image.asset('assets/images/hanj_cut_small.png'),
                  ),
                  const SizedBox(width: 8),
                  Text('Hanj',
                      style: AppTheme.shipporiMincho(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(
                    '$username\'s Top 9',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // 3x3 grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.7,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: 9,
              itemBuilder: (_, i) {
                final entry = items[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    entry.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: entry.imageUrl!,
                            fit: BoxFit.cover,
                            // Can't load (offline, never cached): stays blank.
                            // Unhandled, the failure went to Crashlytics as fatal.
                            errorWidget: (_, _, _) => const SizedBox.shrink(),
                          )
                        : Container(color: AppTheme.surfaceLight),

                    // Rank badge
                    Positioned(
                      top: 6, left: 6,
                      child: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: i == 0
                              ? const Color(0xFFFFD700)
                              : i == 1
                                  ? const Color(0xFFC0C0C0)
                                  : i == 2
                                      ? const Color(0xFFCD7F32)
                                      : Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              color: i < 3 ? Colors.black : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Title overlay
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
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
                        child: Text(
                          entry.title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                'hanj.app',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Taste Card Tab
// ─────────────────────────────────────────────────────────────

class _TasteCardTab extends StatelessWidget {
  final List<_AnimeEntry> allAnime;
  final Map<String, int> genreMap;
  final String username;

  /// The same list read by the Taste page's rules (TasteAnalyzer).
  final TasteProfile? taste;
  final _repaintKey = GlobalKey();

  _TasteCardTab({
    required this.allAnime,
    required this.genreMap,
    required this.username,
    required this.taste,
  });

  List<String> get _topGenres {
    final sorted = genreMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }

  /// Your average rating as the Taste page gives it (question 96): only
  /// ratings on Hanj's 1–10 scale, so an imported 70 no longer makes it
  /// 28.2. 0 with none, which the card prints as a dash.
  double get _avgRating => taste?.avgRating ?? 0;

  /// What the average leaves out, said under the card, never in its image.
  String? get _note {
    final n = taste?.offScaleRatings ?? 0;
    return n == 0
        ? null
        : n == 1
            ? '1 imported rating is on another scale, so it isn\'t in the\u00A0average.'
            : '$n imported ratings are on another scale, so they aren\'t in '
                'the\u00A0average.';
  }

  int get _completed =>
      allAnime.where((a) => a.status == 'COMPLETED').length;

  /// Your archetype by the Taste page's rules (question 95), so this card,
  /// Profile's Taste row and the Taste page name the same one for the same
  /// list. One reading of your list, one place it's worked out.
  ///
  /// The card had rules of its own: it read your top five genres where the
  /// Taste page reads three, Drama or Romance alone made you an "Emotional
  /// Soul" where the Taste page asks for both, and it never looked at your
  /// ratings or drops. So one list was "Emotional Soul" here and "The
  /// All-Rounder" on the Taste page.
  String get _archetype => taste?.archetype ?? '';

  @override
  Widget build(BuildContext context) {
    if (_RankingCardsScreenState._preHanko) return _buildPreHanko();
    if (allAnime.isEmpty) {
      return const _HankoEmpty(
        title: 'Your taste card',
        line: 'Your archetype, your numbers and your top genres, as one '
            'image to save and share. It\'s made from the shows on your list.',
      );
    }
    return _PrintPage(
      repaintKey: _repaintKey,
      filename: 'hanj_taste_card',
      card: _TastePrint(
        username: username,
        archetype: _archetype,
        topGenres: _topGenres,
        avgRating: _avgRating,
        completed: _completed,
        total: allAnime.length,
      ),
      note: _note,
    );
  }

  /// The tab before Hanko (_RankingCardsScreenState._preHanko).
  Widget _buildPreHanko() {
    if (allAnime.isEmpty) {
      return _EmptyState(
        message: 'Add anime to your list to generate your taste card',
        emoji: '✨',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          RepaintBoundary(
            key: _repaintKey,
            child: _TasteCard(
              username: username,
              archetype: _archetype,
              topGenres: _topGenres,
              avgRating: _avgRating,
              completed: _completed,
              total: allAnime.length,
            ),
          ),
          const SizedBox(height: 24),
          _SaveButton(repaintKey: _repaintKey, filename: 'hanj_taste_card'),
        ],
      ),
    );
  }
}

class _TasteCard extends StatelessWidget {
  final String username;
  final String archetype;
  final List<String> topGenres;
  final double avgRating;
  final int completed;
  final int total;

  const _TasteCard({
    required this.username,
    required this.archetype,
    required this.topGenres,
    required this.avgRating,
    required this.completed,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A0A06),
            Color(0xFF121110),
            Color(0xFF0A0614),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Background decoration
            Positioned(
              right: -30, top: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primary.withValues(alpha: 0.08),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: Image.asset('assets/images/hanj_cut_small.png'),
                      ),
                      const SizedBox(width: 8),
                      Text('Hanj',
                          style: AppTheme.shipporiMincho(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('TASTE CARD',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 9,
                              letterSpacing: 1.5)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Username + archetype
                  Text(
                    username,
                    style: AppTheme.shipporiMincho(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          archetype,
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Stats row
                  Row(
                    children: [
                      _CardStat('$total', 'ANIME'),
                      const SizedBox(width: 24),
                      _CardStat('$completed', 'COMPLETED'),
                      const SizedBox(width: 24),
                      _CardStat(
                          avgRating > 0
                              ? avgRating.toStringAsFixed(1)
                              : '—',
                          'AVG RATING'),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Genre DNA
                  Text(
                    'GENRE DNA',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 9,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: topGenres.map((g) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Text(
                        g,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11),
                      ),
                    )).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Footer
                  Text(
                    'hanj.app',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  final String value;
  final String label;
  const _CardStat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 9,
                letterSpacing: 1)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Monthly Aura Tab
// ─────────────────────────────────────────────────────────────

class _MonthlyAuraTab extends StatelessWidget {
  final List<_AnimeEntry> anime;
  final String username;
  final _repaintKey = GlobalKey();

  _MonthlyAuraTab({required this.anime, required this.username});

  Color get _auraColor {
    if (anime.isEmpty) return AppTheme.primary;
    final genres = anime.expand((a) => a.genres).toList();
    final genreCount = <String, int>{};
    for (final g in genres) genreCount[g] = (genreCount[g] ?? 0) + 1;
    final top = (genreCount.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .firstOrNull?.key ?? '';

    if (top == 'Action' || top == 'Sports') return const Color(0xFFFF6B35);
    if (top == 'Drama' || top == 'Romance') return const Color(0xFF4A7FB5);
    if (top == 'Comedy' || top == 'Slice of Life') return const Color(0xFFD4A96A);
    if (top == 'Mystery' || top == 'Psychological') return const Color(0xFF9B59B6);
    if (top == 'Fantasy' || top == 'Adventure') return const Color(0xFF4A9B6F);
    if (top == 'Horror' || top == 'Thriller') return const Color(0xFFCF6679);
    return AppTheme.primary;
  }

  String get _auraName {
    final color = _auraColor;
    if (color == const Color(0xFFFF6B35)) return 'Blazing Orange';
    if (color == const Color(0xFF4A7FB5)) return 'Ocean Blue';
    if (color == const Color(0xFFD4A96A)) return 'Golden Warmth';
    if (color == const Color(0xFF9B59B6)) return 'Mystic Purple';
    if (color == const Color(0xFF4A9B6F)) return 'Forest Green';
    if (color == const Color(0xFFCF6679)) return 'Crimson Edge';
    return 'Coral Fire';
  }

  @override
  Widget build(BuildContext context) {
    final month = DateFormat('MMMM yyyy').format(DateTime.now());
    if (_RankingCardsScreenState._preHanko) return _buildPreHanko(month);
    return _PrintPage(
      repaintKey: _repaintKey,
      filename: 'hanj_monthly_aura',
      card: _AuraPrint(
        username: username,
        month: month,
        anime: anime,
        auraColor: _auraColor,
        auraName: _auraName,
      ),
    );
  }

  /// The tab before Hanko (_RankingCardsScreenState._preHanko).
  Widget _buildPreHanko(String month) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          RepaintBoundary(
            key: _repaintKey,
            child: _MonthlyAuraCard(
              username: username,
              month: month,
              anime: anime,
              auraColor: _auraColor,
              auraName: _auraName,
            ),
          ),
          const SizedBox(height: 24),
          _SaveButton(
              repaintKey: _repaintKey,
              filename: 'hanj_monthly_aura'),
        ],
      ),
    );
  }
}

class _MonthlyAuraCard extends StatelessWidget {
  final String username;
  final String month;
  final List<_AnimeEntry> anime;
  final Color auraColor;
  final String auraName;

  const _MonthlyAuraCard({
    required this.username,
    required this.month,
    required this.anime,
    required this.auraColor,
    required this.auraName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF121110),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: auraColor.withValues(alpha: 0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Aura glow background
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.2,
                    colors: [
                      auraColor.withValues(alpha: 0.2),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      SizedBox(
                        width: 18, height: 18,
                        child: Image.asset('assets/images/hanj_cut_small.png'),
                      ),
                      const SizedBox(width: 8),
                      Text('Hanj',
                          style: AppTheme.shipporiMincho(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('MONTHLY AURA',
                          style: TextStyle(
                              color: auraColor,
                              fontSize: 9,
                              letterSpacing: 1.5)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Text(month.toUpperCase(),
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 10,
                          letterSpacing: 2)),
                  const SizedBox(height: 4),
                  Text(username,
                      style: AppTheme.shipporiMincho(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w700)),

                  const SizedBox(height: 16),

                  // Aura badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: auraColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: auraColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: auraColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: auraColor.withValues(alpha: 0.6),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          auraName,
                          style: TextStyle(
                            color: auraColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Anime count
                  Text(
                    anime.isEmpty
                        ? 'No anime added this month'
                        : '${anime.length} anime this month',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13),
                  ),

                  if (anime.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    // Mini poster row
                    SizedBox(
                      height: 60,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: anime.take(8).length,
                        itemBuilder: (_, i) {
                          final a = anime[i];
                          return Container(
                            width: 42,
                            margin: const EdgeInsets.only(right: 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: a.imageUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: a.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, _, _) =>
                                          const SizedBox.shrink(),
                                    )
                                  : Container(
                                      color: AppTheme.surfaceLight),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  Text(
                    'hanj.app',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Save Button
// ─────────────────────────────────────────────────────────────

class _SaveButton extends StatefulWidget {
  final GlobalKey repaintKey;
  final String filename;
  const _SaveButton({required this.repaintKey, required this.filename});

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final boundary = widget.repaintKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();

      if (kIsWeb) {
        if (mounted) _say('On the web, right-click the card to save it.');
      } else {
        await galSaver.saveImageToGallery(bytes, 'hanj_card_${DateTime.now().millisecondsSinceEpoch}');
        if (mounted) _say('Saved to your gallery.');
      }
    } catch (e) {
      if (mounted) _say('Couldn\'t save the card.');
    }
    if (mounted) setState(() => _saving = false);
  }

  /// A note in the theme's own snack bar, washi words on a sumi step. The
  /// notes were green for done and coral for failed, with ✅ and ❌: in
  /// Hanko coral means only your seal, and the words already say which.
  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  /// The screen's one main action, as Hanko draws it (Detail's
  /// _HankoMainAction): a washi tile with sumi words, 15.34:1, 2 px corners,
  /// pressed with a sumi wash and no ripple. While the card is saved, a sumi
  /// spinner takes the icon's place and taps are ignored.
  ///
  /// Its own semantics node (container), named by its word, with the
  /// InkWell's tap and focus inside it, as Soulmatch's Match since 2d721db
  /// (question 104). A label over excluded semantics gave a node with no tap
  /// and no focus, so a screen reader found Save card but couldn't press it.
  @override
  Widget build(BuildContext context) {
    if (_RankingCardsScreenState._preHanko) return _buildPreHanko();
    final label = _saving ? 'Saving…' : 'Save card';
    return Semantics(
      container: true,
      button: true,
      enabled: !_saving,
      child: Material(
        color: AppTheme.hankoWashi,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: InkWell(
          onTap: _saving ? null : _save,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
          hoverColor: AppTheme.hankoSumi.withValues(alpha: 0.05),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: _saving
                        ? const Padding(
                            padding: EdgeInsets.all(2),
                            child: CircularProgressIndicator(
                                color: AppTheme.hankoSumi, strokeWidth: 2),
                          )
                        : const Icon(Icons.download_sharp,
                            size: 20, color: AppTheme.hankoSumi),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: AppTheme.hankoSans(
                        fontSize: 15,
                        weight: FontWeight.w600,
                        color: AppTheme.hankoSumi,
                        height: 1.2,
                      ),
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

  /// The button before Hanko (_RankingCardsScreenState._preHanko).
  Widget _buildPreHanko() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.download_rounded),
        label: Text(_saving ? 'Saving...' : 'Save Card'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String message;
  final String emoji;
  const _EmptyState({required this.message, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(message,
                style: AppTheme.sans(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    height: 1.6),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Hanko (question 73): the cards as prints
// ─────────────────────────────────────────────────────────────

/// The list couldn't be read (question 97): Profile's line and its Retry, at
/// the top of the column where the card would stand. Before, a failed read
/// showed the cards' empty states, as if your list were empty. The line names
/// no cause the app can't verify (ANILIST-OFFLINE-0908-REPORT.md's rule).
/// Retry reads the list again.
class _HankoListFailed extends StatelessWidget {
  const _HankoListFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 28, AppTheme.hankoGutter, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _Print.width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shippori draws the typewriter apostrophe as a straight
              // tick, so the line is set with the typographic one.
              Text('Couldn’t load your list just now.',
                  style: AppTheme.hankoSerif(fontSize: 17, height: 1.5)),
              const SizedBox(height: 12),
              _TextTile(label: 'Retry', onTap: onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Hanko secondary tile with a word on it ("Retry"), as Profile's and the
/// Calendar's: sumi 3 with a 1 px edge outline, Jost 600 15 washi, 48 dp
/// tall, pressed with the 8% wash. Its own semantics node (container), as
/// the Calendar's since dd45bd1, so a screen reader finds one button named
/// "Retry" with its own tap, apart from the line above it.
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

/// A tab with nothing to print yet: what its card is for, in a few words,
/// at the top of the column where the card would stand. A failed read has
/// its own state now (_HankoListFailed), so this means an empty list.
/// [note], if given, says what the card leaves out (question 96).
class _HankoEmpty extends StatelessWidget {
  const _HankoEmpty({required this.title, required this.line, this.note});

  final String title;
  final String line;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 28, AppTheme.hankoGutter, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _Print.width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppTheme.hankoSerif(
                      fontSize: AppTheme.hankoFeaturedSize, height: 1.25)),
              const SizedBox(height: 8),
              Text(line,
                  style: AppTheme.hankoSans(
                      color: AppTheme.hankoStone, height: 1.5)),
              if (note != null) ...[
                const SizedBox(height: 12),
                _PrintNote(note),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A line under a print, in Jost 13 stone, as Profile writes the line under
/// its seal register. It's part of the page, not the print, so it answers
/// the reader's text size and never reaches the saved image.
class _PrintNote extends StatelessWidget {
  const _PrintNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppTheme.hankoSans(
          fontSize: AppTheme.hankoMetaSize,
          color: AppTheme.hankoStone,
          height: 1.4));
}

/// A tab's page: the card as a print, then Save card under it, in a column
/// the print's width. On a 360 px phone that is the screen less its gutters;
/// on a wide window the column keeps that width and hangs on the left, as
/// Profile's does; on a phone narrower than 360 the print is scaled down
/// whole, never reflowed, so the saved image is the same on every phone.
///
/// A hairline trims the print on screen, so you can see where the image
/// ends. It sits outside the RepaintBoundary that Save card renders, so the
/// saved image has none. [note], if given, sits under the print, outside it
/// too (question 96).
class _PrintPage extends StatelessWidget {
  const _PrintPage({
    required this.repaintKey,
    required this.filename,
    required this.card,
    this.note,
  });

  final GlobalKey repaintKey;
  final String filename;
  final Widget card;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 24, AppTheme.hankoGutter, 32),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _Print.width),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.hankoHairline)),
                  child: RepaintBoundary(key: repaintKey, child: card),
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 12),
                _PrintNote(note),
              ],
              const SizedBox(height: 20),
              _SaveButton(repaintKey: repaintKey, filename: filename),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Ranking Card as Hanko prints it (question 73): a printed object with
/// one size, 320 px wide and as tall as its content, whatever the reader's
/// text size or window, as question 52 made the Hanj Card's share image.
/// The text-size setting doesn't reach inside (MediaQuery.withNoTextScaling):
/// the old cards grew with it, so one card saved differently on different
/// phones. At Save card's pixel ratio of 3 the image is 960 px wide.
///
/// Its parts: the masthead (the coral mark and "Hanj" in Shippori, the
/// card's name at the right in Jost), the print's one rule, the card's own
/// content, and "hanj.app" at the foot. Sumi ground, washi and stone words,
/// square corners like the Hanj Card's; no gradient, glow or pill. [tint]
/// lays a colour over the sumi at Hanko's cover-tint strength (Monthly
/// Aura); secondary words on it are stone hi, as on Detail's tinted field.
class _Print extends StatelessWidget {
  const _Print({required this.kind, required this.children, this.tint});

  /// The card's name, at the masthead's right.
  final String kind;
  final List<Widget> children;
  final Color? tint;

  static const double width = 320;
  static const double pad = 16;
  static const double inner = width - 2 * pad;

  /// Secondary words: stone on sumi (6.93:1), stone hi on a tint.
  static Color secondaryOn(Color? tint) =>
      tint == null ? AppTheme.hankoStone : AppTheme.hankoStoneHi;

  @override
  Widget build(BuildContext context) {
    final tint = this.tint;
    final ground = tint == null
        ? AppTheme.hankoSumi
        : Color.alphaBlend(
            tint.withValues(alpha: AppTheme.hankoTintOpacity),
            AppTheme.hankoSumi);
    final secondary = secondaryOn(tint);
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: width,
        child: ColoredBox(
          color: ground,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(pad, 14, pad, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/images/hanj_cut_small.png',
                      width: 18,
                      height: 18,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 7),
                    Text('Hanj',
                        style: AppTheme.hankoSerif(
                            fontSize: 16, height: 1, letterSpacing: 0.2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        kind,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoLabelSize,
                            color: secondary,
                            height: 1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // The print's one rule: the hairline on sumi; on a tint, washi
                // at 12%, which is the hairline's own step over sumi.
                ColoredBox(
                  color: tint == null
                      ? AppTheme.hankoHairline
                      : AppTheme.hankoWashi.withValues(alpha: 0.12),
                  child: const SizedBox(height: 1, width: double.infinity),
                ),
                const SizedBox(height: 14),
                ...children,
                const SizedBox(height: 18),
                Text('hanj.app',
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoDataSmallSize,
                        color: secondary,
                        height: 1.2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whose card it is: the name in Shippori 19, washi, as Profile heads with
/// it. A long name wraps rather than being cut.
class _PrintByline extends StatelessWidget {
  const _PrintByline(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(name,
      style: AppTheme.hankoSerif(
          fontSize: AppTheme.hankoFeaturedSize, height: 1.25));
}

/// A cover in a print: the list entry's stored URL with Hanko's 2 px corners
/// on sumi 3, which also shows while it loads. When it can't load (offline
/// and never cached), [title], if given, stands in at its foot, so a saved
/// card still says what was there. Never a thrown image error: unhandled,
/// those reached Crashlytics as fatal (this screen's Top 9 gave 8 fatal
/// records offline before its errorWidget).
class _PrintCover extends StatelessWidget {
  const _PrintCover({required this.url, this.title});

  final String? url;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final title = this.title;
    final Widget standIn = title == null
        ? const SizedBox.expand()
        : Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                title,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoDataSmallSize,
                    weight: FontWeight.w500,
                    color: AppTheme.hankoStone,
                    height: 1.25),
              ),
            ),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      child: ColoredBox(
        color: AppTheme.hankoSumi3,
        child: u == null || u.isEmpty
            ? standIn
            : CachedNetworkImage(
                imageUrl: u,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorWidget: (_, _, _) => standIn,
              ),
      ),
    );
  }
}

/// Top 9 as a print: your nine highest-rated shows, three by three in
/// rating order, each cover with your seal pressed over its corner (the
/// mockup's "press", a wariin: half on the art, half on the page). The
/// covers carry no words, like Profile's favourites, and the seals carry the
/// order; each cover gives its place, title and rating to a screen reader.
/// The old card's gold, silver and bronze badges and its titles on a black
/// gradient over the art are gone: Hanko sets no words on art, and your
/// verdict is the seal.
///
/// A rating imported on another scale (D20, such as a 70 from a 100-point
/// list) isn't ranked at all (question 96; the screen's _top9): it took
/// first place above every 10, without a seal, since "70.0" in a seal would
/// say what Hanj's 1-10 scale can't. With fewer than nine, the rest are
/// Hanko's dashed "not yet" places.
class _Top9Print extends StatelessWidget {
  const _Top9Print({required this.anime, required this.username});

  final List<_AnimeEntry> anime;
  final String username;

  /// Room for a seal's 6 px overhang and its 2 px keyline, 2 px clear of
  /// the next cover.
  static const double gap = 10;
  static const double coverWidth = (_Print.inner - 2 * gap) / 3;

  /// AniList covers' own 230 : 325, so nothing is cropped.
  static const double coverHeight = coverWidth * 325 / 230;

  @override
  Widget build(BuildContext context) {
    final items = anime.take(9).toList();
    return _Print(
      kind: 'Top 9',
      children: [
        _PrintByline(username),
        const SizedBox(height: 14),
        for (var row = 0; row < 3; row++) ...[
          if (row > 0) const SizedBox(height: gap + 2),
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                if (col > 0) const SizedBox(width: gap),
                _Top9Place(
                  rank: row * 3 + col + 1,
                  entry: row * 3 + col < items.length
                      ? items[row * 3 + col]
                      : null,
                ),
              ],
            ],
          ),
        ],
        // The last row's seals hang below it.
        const SizedBox(
            height: _Top9Place.overhang + AppTheme.hankoKeyline),
      ],
    );
  }
}

/// One place in the Top 9: the cover, and your seal over its bottom-right
/// corner; or a dashed empty place.
class _Top9Place extends StatelessWidget {
  const _Top9Place({required this.rank, required this.entry});

  final int rank;
  final _AnimeEntry? entry;

  /// The spec's 24 px list seal, its numerals at 11.5.
  static const double sealSize = 24;

  /// How far the seal hangs past the cover's edges, as the mockup presses it.
  static const double overhang = 6;

  /// Hanj's scale, 1 to 10 in half steps (Profile's rule for favourites).
  static bool _onScale(double rating) {
    final step = (rating * 2).round() / 2;
    return step >= 1 && step <= 10;
  }

  @override
  Widget build(BuildContext context) {
    const w = _Top9Print.coverWidth, h = _Top9Print.coverHeight;
    final entry = this.entry;
    if (entry == null) {
      return HankoSeal.unrated(
        size: h,
        width: w,
        showAdd: false,
        semanticLabel: 'Place $rank, empty',
      );
    }
    final rating = entry.rating;
    final double? seal = rating != null && _onScale(rating) ? rating : null;
    return Semantics(
      image: true,
      label: '$rank. ${entry.title}'
          '${seal == null ? '' : ', your rating ${HankoSeal.formatScore(seal)}'}',
      excludeSemantics: true,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
                child: _PrintCover(url: entry.imageUrl, title: entry.title)),
            if (seal != null)
              Positioned(
                right: -overhang,
                bottom: -overhang,
                child: HankoSeal.score(seal, size: sealSize),
              ),
          ],
        ),
      ),
    );
  }
}

/// Your taste as a print: your name; your archetype as its headline, in
/// Shippori 28 and washi, where the old card set it in a coral pill (an
/// archetype is a reading of your list, not a verdict, so it is never
/// coral); three figures; and your top genres as one line.
class _TastePrint extends StatelessWidget {
  const _TastePrint({
    required this.username,
    required this.archetype,
    required this.topGenres,
    required this.avgRating,
    required this.completed,
    required this.total,
  });

  final String username;
  final String archetype;
  final List<String> topGenres;
  final double avgRating;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return _Print(
      kind: 'Taste Card',
      children: [
        _PrintByline(username),
        const SizedBox(height: 10),
        Text(archetype, style: AppTheme.hankoSerif(fontSize: 28, height: 1.2)),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _PrintFigure('$total', 'titles')),
            Expanded(child: _PrintFigure('$completed', 'completed')),
            Expanded(
              child: _PrintFigure(
                  avgRating > 0 ? avgRating.toStringAsFixed(1) : '—',
                  'average rating'),
            ),
          ],
        ),
        if (topGenres.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Genre DNA',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoDataSmallSize,
                  color: AppTheme.hankoStone,
                  height: 1.2)),
          const SizedBox(height: 6),
          // A genre's own words never part ("Slice of Life" broke after
          // "of"), and each dot stays with the genre before it, so a line
          // breaks only after a dot.
          Text(
              topGenres
                  .map((g) => g.replaceAll(' ', '\u00A0'))
                  .join('\u00A0· '),
              style: AppTheme.hankoSans(height: 1.5)),
        ],
      ],
    );
  }
}

/// A figure on a print: the number in Shippori 22, washi, over its word in
/// Jost 11, stone.
class _PrintFigure extends StatelessWidget {
  const _PrintFigure(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTheme.hankoSerif(fontSize: 22, height: 1.1)),
        const SizedBox(height: 4),
        Text(label,
            style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoDataSmallSize,
                color: AppTheme.hankoStone,
                height: 1.2)),
      ],
    );
  }
}

/// Monthly Aura as a print: the month's colour laid over the whole card at
/// Hanko's cover-tint strength (20%, flat), where the old card had a radial
/// glow, a glowing dot and a coloured border. Here the colour is the card's
/// content, as a cover's colour is on Detail: it is named in words and shown
/// once at full strength, as a flat dot beside its name. Up to six of the
/// month's covers fit the width; the old row scrolled, so the saved image
/// cut off whatever didn't fit.
class _AuraPrint extends StatelessWidget {
  const _AuraPrint({
    required this.username,
    required this.month,
    required this.anime,
    required this.auraColor,
    required this.auraName,
  });

  final String username;
  final String month;
  final List<_AnimeEntry> anime;
  final Color auraColor;
  final String auraName;

  static const int _covers = 6;
  static const double _coverGap = 5;
  static const double _coverWidth =
      (_Print.inner - (_covers - 1) * _coverGap) / _covers;
  static const double _coverHeight = _coverWidth * 325 / 230;

  @override
  Widget build(BuildContext context) {
    final secondary = _Print.secondaryOn(auraColor);
    final n = anime.length;
    final shown = n < _covers ? n : _covers;
    return _Print(
      kind: 'Monthly Aura',
      tint: auraColor,
      children: [
        Text(month,
            style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoLabelSize,
                color: secondary,
                height: 1.2)),
        const SizedBox(height: 4),
        _PrintByline(username),
        const SizedBox(height: 18),
        Row(
          children: [
            DecoratedBox(
              decoration:
                  BoxDecoration(color: auraColor, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 14),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(auraName,
                  style: AppTheme.hankoSerif(fontSize: 24, height: 1.2)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          n == 0
              ? 'No titles added this month'
              : n == 1
                  ? '1 title this month'
                  : '$n titles this month',
          style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoMetaSize, color: secondary, height: 1.3),
        ),
        if (shown > 0) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < shown; i++) ...[
                if (i > 0) const SizedBox(width: _coverGap),
                SizedBox(
                  width: _coverWidth,
                  height: _coverHeight,
                  child: _PrintCover(url: anime[i].imageUrl),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────

class _AnimeEntry {
  final String title;
  final String? imageUrl;
  final double? rating;
  final String status;
  final List<String> genres;
  final DateTime? addedAt;

  const _AnimeEntry({
    required this.title,
    required this.imageUrl,
    required this.status,
    this.rating,
    this.genres = const [],
    this.addedAt,
  });
}


