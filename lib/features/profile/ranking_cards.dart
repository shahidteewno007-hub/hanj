import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../widgets/gal_mobile.dart' if (dart.library.html) '../../widgets/gal_stub.dart' as galSaver;

import '../../core/theme/app_theme.dart';

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

      if (mounted) setState(() => _isLoading = false);
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<_AnimeEntry> get _top9 {
    final rated = _allAnime
        .where((a) => a.rating != null && a.imageUrl != null)
        .toList()
      ..sort((a, b) => b.rating!.compareTo(a.rating!));
    return rated.take(9).toList();
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Ranking Cards',
            style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primary,
          labelStyle: AppTheme.mono(
              fontSize: 10, color: AppTheme.primary, letterSpacing: 1),
          unselectedLabelStyle: AppTheme.mono(
              fontSize: 10, color: AppTheme.textMuted, letterSpacing: 1),
          tabs: const [
            Tab(text: 'TOP 9'),
            Tab(text: 'TASTE CARD'),
            Tab(text: 'MONTHLY AURA'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(
              color: AppTheme.primary, strokeWidth: 2))
          : TabBarView(
              controller: _tabController,
              children: [
                _Top9Tab(anime: _top9, username: _username),
                _TasteCardTab(
                    allAnime: _allAnime,
                    genreMap: _genreMap,
                    username: _username),
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
  final _repaintKey = GlobalKey();

  _Top9Tab({required this.anime, required this.username});

  @override
  Widget build(BuildContext context) {
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
        color: const Color(0xFF0D0B09),
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
                    const Color(0xFF0D0B09),
                  ],
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18, height: 18,
                    child: Image.asset('assets/images/hanj_wing_transparent.png'),
                  ),
                  const SizedBox(width: 8),
                  Text('Hanj',
                      style: GoogleFonts.playfairDisplay(
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
  final _repaintKey = GlobalKey();

  _TasteCardTab({
    required this.allAnime,
    required this.genreMap,
    required this.username,
  });

  List<String> get _topGenres {
    final sorted = genreMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }

  double get _avgRating {
    final rated =
        allAnime.where((a) => a.rating != null).map((a) => a.rating!).toList();
    if (rated.isEmpty) return 0;
    return rated.reduce((a, b) => a + b) / rated.length;
  }

  int get _completed =>
      allAnime.where((a) => a.status == 'COMPLETED').length;

  String get _archetype {
    final g = _topGenres.join(' ');
    if (g.contains('Action') && g.contains('Thriller')) return 'Thrill Seeker';
    if (g.contains('Drama') || g.contains('Romance')) return 'Emotional Soul';
    if (g.contains('Mystery') || g.contains('Psychological')) return 'Deep Thinker';
    if (g.contains('Slice of Life') || g.contains('Comedy')) return 'Comfort Watcher';
    if (g.contains('Fantasy') || g.contains('Adventure')) return 'World Builder';
    return 'All-Rounder';
  }

  @override
  Widget build(BuildContext context) {
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
            Color(0xFF0D0B09),
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
                        child: Image.asset('assets/images/hanj_wing_transparent.png'),
                      ),
                      const SizedBox(width: 8),
                      Text('Hanj',
                          style: GoogleFonts.playfairDisplay(
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
                    style: GoogleFonts.playfairDisplay(
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
        color: const Color(0xFF0D0B09),
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
                        child: Image.asset('assets/images/hanj_wing_transparent.png'),
                      ),
                      const SizedBox(width: 8),
                      Text('Hanj',
                          style: GoogleFonts.playfairDisplay(
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
                      style: GoogleFonts.playfairDisplay(
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Right-click the card to save on web'),
              backgroundColor: Color(0xFF4CAF50),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        await galSaver.saveImageToGallery(bytes, 'hanj_card_${DateTime.now().millisecondsSinceEpoch}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Card saved to gallery!'),
              backgroundColor: Color(0xFF4CAF50),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Failed to save card'),
            backgroundColor: Color(0xFFE8624A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
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


