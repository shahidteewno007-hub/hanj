import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// Your own Top 9 (round seven): up to nine list-entry ids in your order,
  /// as users/{uid}.top9 keeps them. Null until you pick, and then the Top 9
  /// is your nine highest ratings, as it always was.
  List<String>? _picks;

  /// One key per print, held here so a rebuild (your picks changing, a
  /// cover's colour arriving) keeps the RepaintBoundary that Save card
  /// renders. Each tab made its own, anew on every rebuild of the screen.
  final _top9Key = GlobalKey();
  final _tasteKey = GlobalKey();
  final _auraKey = GlobalKey();

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
      final picks = userDoc.data()?['top9'];
      _picks = picks is List ? picks.whereType<String>().take(9).toList() : null;

      final snap = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('animeList').get();

      _allAnime = snap.docs.map((d) {
        final data = d.data();
        return _AnimeEntry(
          id:         d.id,
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

  /// The Top 9 as its card prints it: your picks in your order, leaving out
  /// any you've since taken off your list; or, until you pick, your nine
  /// highest ratings.
  List<_AnimeEntry> get _top9 {
    final picks = _picks;
    if (picks == null) return _highestRated;
    final byId = {for (final a in _allAnime) a.id: a};
    return picks.map((id) => byId[id]).whereType<_AnimeEntry>().toList();
  }

  /// Your nine highest ratings on Hanj's 1–10 scale (question 96), as
  /// Profile's favourites and Advanced Stats count them. An imported rating
  /// on another scale (D20: a 70 from a 100-point list) ranked first here,
  /// above every 10; it's left out, and [_offScale] says how many were.
  List<_AnimeEntry> get _highestRated {
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

  /// Opens the editor on the Top 9 as its card shows it, and keeps what you
  /// leave the editor with, by Done or Back.
  Future<void> _editTop9() async {
    final result = await Navigator.push<_Top9Edit>(
      context,
      MaterialPageRoute(
        builder: (_) => _Top9EditScreen(
          entries: _allAnime,
          picks: [for (final a in _top9) a.id],
          highestRated: [for (final a in _highestRated) a.id],
          pickedByYou: _picks != null,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final picks = result.pickedByYou ? result.ids : null;
    final before = _picks;
    if (listEquals(picks, before)) return;
    setState(() => _picks = picks);
    _storePicks(picks, before);
  }

  /// Keeps your picks on your user document as `top9`, the list-entry ids in
  /// order, or clears it (null) for your highest ratings again. Today's rules
  /// let you write your own user document (only founderNumber is frozen) and
  /// every other writer of it merges, so nothing else there is touched. It
  /// holds ids only, no titles or covers. Awaited and caught, but the screen
  /// never waits on it: offline, Firestore keeps the change and sends it on.
  /// A refused write puts [before] back, unless you've changed them again,
  /// so the card never shows an order that wasn't kept.
  Future<void> _storePicks(List<String>? picks, List<String>? before) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {'top9': picks ?? FieldValue.delete()},
        SetOptions(merge: true),
      );
    } catch (_) {
      if (!mounted) return;
      if (listEquals(_picks, picks)) setState(() => _picks = before);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Couldn’t keep your Top 9 just now.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
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
                        repaintKey: _top9Key,
                        anime: _top9,
                        username: _username,
                        offScale: _offScale,
                        pickedByYou: _picks != null,
                        hasList: _allAnime.isNotEmpty,
                        onEdit: _editTop9),
                    _TasteCardTab(
                        repaintKey: _tasteKey,
                        allAnime: _allAnime,
                        genreMap: _genreMap,
                        username: _username,
                        taste: _taste),
                    _MonthlyAuraTab(
                        repaintKey: _auraKey,
                        anime: _monthlyAnime,
                        username: _username),
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

  /// Whether the nine are your own picks (round seven), not your highest
  /// ratings.
  final bool pickedByYou;

  /// Whether your list has anything on it to pick from.
  final bool hasList;

  /// Opens the Top 9 editor.
  final VoidCallback onEdit;

  /// The print's boundary, which Save card renders (the screen holds it).
  final GlobalKey repaintKey;

  const _Top9Tab({
    required this.repaintKey,
    required this.anime,
    required this.username,
    required this.offScale,
    required this.pickedByYou,
    required this.hasList,
    required this.onEdit,
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
      // What the card is for. With a list, you can pick your nine from it
      // here, rated or not (round seven); with only imported ratings, the
      // note says why none of them was ranked.
      return _HankoEmpty(
        title: 'Your Top 9',
        line: hasList
            ? 'Your nine favourites in your own order, as one image to save '
                'and share. Pick them from your list, rated or not.'
            : 'Your nine favourites, as one image to save and share. Add '
                'shows to your list to pick them.',
        note: pickedByYou ? null : _note,
        action: hasList
            ? _TextTile(label: 'Pick your nine', onTap: onEdit)
            : null,
      );
    }
    // The note explains the ranking by ratings, so your own order has none.
    return _PrintPage(
      repaintKey: repaintKey,
      filename: 'hanj_top9',
      header: _Top9Header(pickedByYou: pickedByYou, onEdit: onEdit),
      card: _Top9Print(
          anime: anime, username: username, pickedByYou: pickedByYou),
      note: pickedByYou ? null : _note,
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
            key: repaintKey,
            child: _Top9Card(anime: anime, username: username),
          ),
          const SizedBox(height: 24),
          _SaveButton(repaintKey: repaintKey, filename: 'hanj_top9'),
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
      items.add(_AnimeEntry(id: '', title: '', imageUrl: null, status: ''));
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
                    child: Image.asset('assets/images/hanj_wing_transparent.png'),
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

  /// The print's boundary, which Save card renders (the screen holds it).
  final GlobalKey repaintKey;

  const _TasteCardTab({
    required this.repaintKey,
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
      repaintKey: repaintKey,
      filename: 'hanj_taste_card',
      card: _TastePrint(
        username: username,
        archetype: _archetype,
        description: taste?.archetypeDesc ?? '',
        genres: taste?.topGenres ?? const [],
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
            key: repaintKey,
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
          _SaveButton(repaintKey: repaintKey, filename: 'hanj_taste_card'),
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
                        child: Image.asset('assets/images/hanj_wing_transparent.png'),
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

  /// The print's boundary, which Save card renders (the screen holds it).
  final GlobalKey repaintKey;

  const _MonthlyAuraTab({
    required this.repaintKey,
    required this.anime,
    required this.username,
  });

  /// The genre the month's titles share most, which [_auraColor] reads the
  /// colour from (the same count); null for an empty month.
  String? get _leadGenre {
    final count = <String, int>{};
    for (final g in anime.expand((a) => a.genres)) {
      count[g] = (count[g] ?? 0) + 1;
    }
    return (count.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .firstOrNull
        ?.key;
  }

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
      repaintKey: repaintKey,
      filename: 'hanj_monthly_aura',
      card: _AuraPrint(
        username: username,
        month: month,
        anime: anime,
        auraColor: _auraColor,
        auraName: _auraName,
        leadGenre: _leadGenre,
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
            key: repaintKey,
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
              repaintKey: repaintKey,
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
                        child: Image.asset('assets/images/hanj_wing_transparent.png'),
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
      // A card that isn't there, or that doesn't encode, is a failed save
      // (question 129): each throws into the catch below, which says so,
      // and the button comes back. They used to return from inside the try,
      // past the reset after the catch, so the button stayed at "Saving…"
      // and ignored taps.
      final boundary = widget.repaintKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('No card to render.');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('The card did not encode.');

      final bytes = byteData.buffer.asUint8List();

      if (kIsWeb) {
        if (mounted) _say('On the web, right-click the card to save it.');
      } else {
        await galSaver.saveImageToGallery(bytes, 'hanj_card_${DateTime.now().millisecondsSinceEpoch}');
        if (mounted) _say('Saved to your gallery.');
      }
    } catch (e) {
      // The typographic apostrophe, as the screen's other lines (question
      // 154).
      if (mounted) _say('Couldn’t save the card.');
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
/// [note], if given, says what the card leaves out (question 96); [action],
/// if given, is the way to fill it (the Top 9's "Pick your nine").
class _HankoEmpty extends StatelessWidget {
  const _HankoEmpty({
    required this.title,
    required this.line,
    this.note,
    this.action,
  });

  final String title;
  final String line;
  final String? note;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    final action = this.action;
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
              if (action != null) ...[
                const SizedBox(height: 20),
                action,
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
/// too (question 96); [header], if given, above it (the Top 9's way to edit).
class _PrintPage extends StatelessWidget {
  const _PrintPage({
    required this.repaintKey,
    required this.filename,
    required this.card,
    this.note,
    this.header,
  });

  final GlobalKey repaintKey;
  final String filename;
  final Widget card;
  final String? note;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final note = this.note;
    final header = this.header;
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
              if (header != null) ...[
                header,
                const SizedBox(height: 16),
              ],
              _PrintReveal(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topLeft,
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.hankoHairline)),
                    child: RepaintBoundary(key: repaintKey, child: card),
                  ),
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
/// Its parts: the masthead (the coral wing and "Hanj" in Shippori, the
/// card's name at the right in Jost), the print's one rule, the card's own
/// content, and "hanj.app" at the foot with the month beside it. Square
/// corners like the Hanj Card's.
///
/// Round seven gives the prints back the depth they had before Hanko (a
/// field of colour, a glow, art filling the frame), in Hanko's faces and
/// without coral. [ground] paints under everything: each card's own field of
/// colour (its #1's cover colour, its archetype's colour, its aura's glow).
/// Over it lies a fine paper grain, washi and sumi specks, under the words
/// and the art, so the grain never touches a cover. Words on a field stay
/// washi and stone hi, since every field is kept dark enough for them
/// (_fieldOver).
class _Print extends StatelessWidget {
  const _Print({
    required this.kind,
    required this.children,
    this.ground,
    this.footnote,
  });

  /// The card's name, at the masthead's right.
  final String kind;
  final List<Widget> children;

  /// The card's field of colour, filling the print under the grain. Plain
  /// sumi without one.
  final Widget? ground;

  /// A few words at the foot's right, such as the month.
  final String? footnote;

  static const double width = 320;
  static const double pad = 16;
  static const double inner = width - 2 * pad;

  /// Where the card's own content starts: the top pad, the 18 px masthead,
  /// 12, the rule and 14. Monthly Aura places its glow from it.
  static const double contentTop = 14 + 18 + 12 + 1 + 14;

  /// Secondary words on every print: stone hi, which keeps at least 5:1 on
  /// any field _fieldOver allows (stone, at 3.4:1 there, would not).
  static const Color secondary = AppTheme.hankoStoneHi;

  @override
  Widget build(BuildContext context) {
    final ground = this.ground;
    final footnote = this.footnote;
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: width,
        child: Stack(
          children: [
            const Positioned.fill(
                child: ColoredBox(color: AppTheme.hankoSumi)),
            if (ground != null) Positioned.fill(child: ground),
            const Positioned.fill(
                child: CustomPaint(painter: _GrainPainter())),
            Padding(
              padding: const EdgeInsets.fromLTRB(pad, 14, pad, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 18,
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/hanj_wing_transparent.png',
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
                                weight: FontWeight.w500,
                                color: secondary,
                                height: 1,
                                letterSpacing: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // The print's one rule: washi at 12%, the hairline's own
                  // step over sumi, so it shows on any field.
                  ColoredBox(
                    color: AppTheme.hankoWashi.withValues(alpha: 0.12),
                    child: const SizedBox(height: 1, width: double.infinity),
                  ),
                  const SizedBox(height: 14),
                  ...children,
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text('hanj.app',
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoDataSmallSize,
                              color: secondary,
                              height: 1.2)),
                      if (footnote != null) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(footnote,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style: AppTheme.hankoSans(
                                  fontSize: AppTheme.hankoDataSmallSize,
                                  color: secondary,
                                  height: 1.2)),
                        ),
                      ],
                    ],
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

/// [key] laid over sumi as strongly as [alpha] allows while washi on it
/// keeps at least 7.7:1 and stone hi 5.4:1: the blend's luminance is held at
/// 0.06 or under, easing the colour off for pale covers and auras (a white
/// cover at 45% would leave washi at 4.2:1). Saturated, dark colours keep
/// their full strength.
Color _fieldOver(Color key, double alpha) {
  var a = alpha;
  var c = Color.alphaBlend(key.withValues(alpha: a), AppTheme.hankoSumi);
  while (a > 0.06 && c.computeLuminance() > 0.06) {
    a -= 0.02;
    c = Color.alphaBlend(key.withValues(alpha: a), AppTheme.hankoSumi);
  }
  return c;
}

/// [key]'s hue as a deep, saturated tone with a luminance of [lum] or less:
/// as much colour as a field can hold while the words on it keep their
/// contrast (at 0.06, washi 7.7:1 and stone hi 5.4:1, as _fieldOver). Laid
/// over sumi, a colour greys out before it gets that dark; this keeps its
/// saturation, so a field with no art on it (the Taste Card, the aura's
/// glow) still reads as colour, not as black.
Color _jewel(Color key, double lum) {
  final hsv = HSVColor.fromColor(key);
  final saturation = math.max(hsv.saturation, 0.6);
  var value = 1.0;
  var c = hsv.withSaturation(saturation).withValue(value).toColor();
  while (value > 0.05 && c.computeLuminance() > lum) {
    value -= 0.01;
    c = hsv.withSaturation(saturation).withValue(value).toColor();
  }
  return c;
}

/// The print's paper: fine washi and sumi specks at random but fixed places
/// (the same seed every time, so a card saves the same on every phone),
/// about one per 70 px², drawn in two calls. Under the words and covers.
class _GrainPainter extends CustomPainter {
  const _GrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    var seed = 20261103;
    double next() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    final n = (size.width * size.height / 70).round();
    final light = <Offset>[], dark = <Offset>[];
    for (var i = 0; i < n; i++) {
      final p = Offset(next() * size.width, next() * size.height);
      (i.isEven ? light : dark).add(p);
    }
    canvas.drawPoints(
        ui.PointMode.points,
        light,
        Paint()
          ..color = AppTheme.hankoWashi.withValues(alpha: 0.045)
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round);
    canvas.drawPoints(
        ui.PointMode.points,
        dark,
        Paint()
          ..color = AppTheme.hankoSumi.withValues(alpha: 0.22)
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_GrainPainter oldDelegate) => false;
}

/// The print rising into place as its tab opens: 260 ms, fading in and up
/// 10 px, slowing as it lands, as Hanko's sheets rise. It moves the print
/// from outside its RepaintBoundary, so Save card never renders it part
/// way. None when the system asks for no animations.
class _PrintReveal extends StatelessWidget {
  const _PrintReveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: AppTheme.hankoSheetCurve,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
            offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: child,
    );
  }
}

/// A cover's colour, read from its own art (round seven): the most vivid
/// hue in a 20 px wide decode of it, or its plain average when it has none
/// (a black-and-white cover gives a neutral grey). No AniList request, so it
/// works offline from the image cache and for covers imported from
/// MyAnimeList. Kept per address for as long as the app runs; a cover that
/// can't load has no colour (null), and its card keeps plain sumi.
///
/// The listener stays on until the image arrives or fails, so a late
/// failure is still handled here: with no listener, it would reach
/// Crashlytics as fatal, as unhandled cover errors did before.
class _CoverTones {
  _CoverTones._();

  static final Map<String, Color?> _known = {};
  static final Map<String, Future<Color?>> _pending = {};

  /// The colour already read for [url], or null.
  static Color? known(String url) => _known[url];

  /// Reads the large file the print shows, then the stored one if that
  /// fails. Never throws.
  static Future<Color?> of(String url) {
    if (_known.containsKey(url)) return Future.value(_known[url]);
    return _pending[url] ??= () async {
      final large = _largeCover(url);
      final c = (large == null ? null : await _read(large)) ?? await _read(url);
      _known[url] = c;
      _pending.remove(url);
      return c;
    }();
  }

  static Future<Color?> _read(String url) async {
    final done = Completer<ui.Image?>();
    final stream = ResizeImage(CachedNetworkImageProvider(url), width: 20)
        .resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    }, onError: (_, _) {
      if (!done.isCompleted) done.complete(null);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    final image = await done.future;
    if (image == null) return null;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      // Twelve hue bins of 30°, each pixel weighed by how vivid it is
      // (saturation times value). On the web the decode isn't resized, so
      // every few pixels stand for the rest.
      final pixels = data.lengthInBytes ~/ 4;
      final step = math.max(1, pixels ~/ 1500);
      final weight = List<double>.filled(12, 0);
      final red = List<double>.filled(12, 0);
      final green = List<double>.filled(12, 0);
      final blue = List<double>.filled(12, 0);
      var count = 0;
      double r0 = 0, g0 = 0, b0 = 0;
      for (var p = 0; p < pixels; p += step) {
        final i = p * 4;
        if (data.getUint8(i + 3) < 128) continue;
        final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
        r0 += r;
        g0 += g;
        b0 += b;
        count++;
        final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
        if (hsv.saturation < 0.2 || hsv.value < 0.2) continue;
        final w = hsv.saturation * hsv.value;
        final bin = (hsv.hue / 30).floor() % 12;
        weight[bin] += w;
        red[bin] += r * w;
        green[bin] += g * w;
        blue[bin] += b * w;
      }
      if (count == 0) return null;
      var best = 0;
      for (var k = 1; k < 12; k++) {
        if (weight[k] > weight[best]) best = k;
      }
      // Less colour than a tenth of its pixels at half strength: a grey
      // cover, which gives its plain average.
      if (weight[best] < count * 0.05) {
        return Color.fromARGB(255, (r0 / count).round(), (g0 / count).round(),
            (b0 / count).round());
      }
      final w = weight[best];
      final hsv = HSVColor.fromColor(Color.fromARGB(255, (red[best] / w).round(),
          (green[best] / w).round(), (blue[best] / w).round()));
      // A field reads its colour best fairly saturated and not too dark.
      return hsv
          .withSaturation(math.max(hsv.saturation, 0.35))
          .withValue(hsv.value.clamp(0.55, 0.92))
          .toColor();
    } catch (_) {
      // Pixels that can't be read (an image the browser won't share) give no
      // colour, and the card keeps plain sumi.
      return null;
    } finally {
      image.dispose();
    }
  }
}

/// AniList's cover at its largest (460 px wide) for a cover stored at its
/// `large` size (230), by the same file's path: a saved print is 960 px
/// wide, so a 230 px cover would print soft. Null for any other address
/// (MyAnimeList's covers, AniList's default image), which prints as stored.
String? _largeCover(String url) {
  const stored = 's4.anilist.co/file/anilistcdn/media/anime/cover/medium/';
  if (!url.startsWith('https://$stored') || url.endsWith('/default.jpg')) {
    return null;
  }
  return url.replaceFirst('/cover/medium/', '/cover/large/');
}

/// Builds with the colours of [urls]' covers ([_CoverTones]), in order, each
/// null until it's read; rebuilds as each arrives.
class _Tones extends StatefulWidget {
  const _Tones({required this.urls, required this.builder});

  final List<String> urls;
  final Widget Function(BuildContext context, List<Color?> tones) builder;

  @override
  State<_Tones> createState() => _TonesState();
}

class _TonesState extends State<_Tones> {
  List<Color?> _tones = const [];

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(_Tones oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.urls, widget.urls)) _read();
  }

  void _read() {
    final urls = widget.urls;
    _tones = [for (final u in urls) _CoverTones.known(u)];
    for (var i = 0; i < urls.length; i++) {
      if (_tones[i] != null) continue;
      _CoverTones.of(urls[i]).then((c) {
        if (!mounted || c == null || !listEquals(urls, widget.urls)) return;
        setState(() => _tones = List.of(_tones)..[i] = c);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tones);
}

/// Whose card it is: the name in Shippori, washi, 19 as Profile heads with
/// it unless [size] says otherwise. A long name wraps rather than being
/// cut, unless [oneLine] (Monthly Aura, whose glow is placed from fixed
/// heights), where it fades out at the edge.
class _PrintByline extends StatelessWidget {
  const _PrintByline(
    this.name, {
    this.size = AppTheme.hankoFeaturedSize,
    this.oneLine = false,
  });

  final String name;
  final double size;
  final bool oneLine;

  @override
  Widget build(BuildContext context) => Text(name,
      maxLines: oneLine ? 1 : null,
      softWrap: !oneLine,
      overflow: oneLine ? TextOverflow.fade : null,
      style: AppTheme.hankoSerif(fontSize: size, height: 1.25));
}

/// A cover in a print: the list entry's cover with Hanko's 2 px corners on
/// sumi 3, which also shows while it loads. AniList's covers come at their
/// largest (_largeCover), so a saved print is sharp; if that file can't
/// load, the stored one takes its place. When neither can (offline and
/// never cached), [title], if given, stands in at its foot, so a saved card
/// still says what was there. Never a thrown image error: unhandled, those
/// reached Crashlytics as fatal (this screen's Top 9 gave 8 fatal records
/// offline before its errorWidget).
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
    Widget cover(String address, Widget orElse) => CachedNetworkImage(
          imageUrl: address,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorWidget: (_, _, _) => orElse,
        );
    final large = u == null ? null : _largeCover(u);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      child: ColoredBox(
        color: AppTheme.hankoSumi3,
        child: u == null || u.isEmpty
            ? standIn
            : large == null
                ? cover(u, standIn)
                : cover(large, cover(u, standIn)),
      ),
    );
  }
}

/// Top 9 as a print (round seven): your nine as three rows of three
/// posters, the "3x3" people post, on a field of your #1's cover colour.
///
/// Shahid's words (2026-11-03): "remove the rating or put it inside the
/// poster". The rating is gone: the order can be yours now, and a rating
/// beside it would argue with it (your #2 may be rated above your #1). Your
/// place for each sits inside its poster instead, in Shippori 26 washi on a
/// sumi scrim at the foot (at least 4.6:1 there over white art; large type
/// needs 3:1). The titles move off the art into a legend under the grid,
/// one per column, so the posters stay clean and a viewer can still tell
/// what #4 is. Round six's seal over each corner, and its covers-only grid,
/// were this card's "letters on black".
///
/// Until you pick your own (the editor), the nine are your highest ratings
/// on the 1-10 scale (question 96). With fewer than nine, the rest are
/// Hanko's dashed "not yet" places.
class _Top9Print extends StatelessWidget {
  const _Top9Print({
    required this.anime,
    required this.username,
    required this.pickedByYou,
  });

  final List<_AnimeEntry> anime;
  final String username;

  /// Your own order, or your highest ratings: the print says which.
  final bool pickedByYou;

  static const double gap = 6;
  static const double coverWidth = (_Print.inner - 2 * gap) / 3;

  /// AniList covers' own 230 : 325, so nothing is cropped.
  static const double coverHeight = coverWidth * 325 / 230;

  @override
  Widget build(BuildContext context) {
    final items = anime.take(9).toList();
    final lead = items.isEmpty ? '' : items.first.imageUrl ?? '';
    return _Tones(
      urls: lead.isEmpty ? const [] : [lead],
      builder: (context, tones) => _Print(
        kind: 'Top 9',
        footnote: DateFormat('MMMM yyyy').format(DateTime.now()),
        ground: _FieldGround(tone: tones.isEmpty ? null : tones.first),
        children: [
          _PrintByline(username, size: 24),
          const SizedBox(height: 2),
          Text(pickedByYou ? 'Ranked by me' : 'Ranked by my ratings',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  color: _Print.secondary,
                  height: 1.3)),
          const SizedBox(height: 14),
          for (var row = 0; row < 3; row++) ...[
            if (row > 0) const SizedBox(height: gap),
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
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Top9Legend(items: items),
          ],
        ],
      ),
    );
  }
}

/// One place in the Top 9: the cover with your place for it inside, at its
/// foot; or a dashed empty place. A cover that can't load leaves sumi 3 and
/// the number, and the legend still names it.
class _Top9Place extends StatelessWidget {
  const _Top9Place({required this.rank, required this.entry});

  final int rank;
  final _AnimeEntry? entry;

  /// Hanj's scale, 1 to 10 in half steps (Profile's rule for favourites).
  static bool _onScale(double rating) {
    final step = (rating * 2).round() / 2;
    return step >= 1 && step <= 10;
  }

  /// Clear over the art's top half, deepening to sumi at 92% at its foot,
  /// under the number.
  static const _scrim = BoxDecoration(
    borderRadius: BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00121110), Color(0x9E121110), Color(0xEB121110)],
      stops: [0.45, 0.72, 1.0],
    ),
  );

  /// A washi keyline at 10% round the poster, so a dark cover's foot, under
  /// its scrim, still ends where the poster does.
  static const _keyline = BoxDecoration(
    borderRadius: BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
    border: Border.fromBorderSide(BorderSide(color: Color(0x1AEEE7DA))),
  );

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
    return Semantics(
      image: true,
      label: '$rank. ${entry.title}',
      excludeSemantics: true,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _PrintCover(url: entry.imageUrl),
            const DecoratedBox(decoration: _scrim),
            const DecoratedBox(decoration: _keyline),
            Positioned(
              left: 7,
              bottom: 5,
              child: Text('$rank',
                  style: AppTheme.hankoSerif(fontSize: 26, height: 1)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Top 9's titles under its grid, one per column as the posters stand:
/// each place's number in stone hi and its title in washi, Jost 11, up to
/// two lines. A screen reader has them from the posters already.
class _Top9Legend extends StatelessWidget {
  const _Top9Legend({required this.items});

  final List<_AnimeEntry> items;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var row = 0; row * 3 < items.length; row++) ...[
            if (row > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < 3; col++) ...[
                  if (col > 0) const SizedBox(width: _Top9Print.gap),
                  SizedBox(
                    width: _Top9Print.coverWidth,
                    // The number hangs in its own column, so a title's
                    // second line starts under its first word.
                    child: row * 3 + col < items.length
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 13,
                                child: Text('${row * 3 + col + 1}',
                                    style: AppTheme.hankoSans(
                                        fontSize: AppTheme.hankoDataSmallSize,
                                        weight: FontWeight.w600,
                                        color: _Print.secondary,
                                        height: 1.3,
                                        tabular: true)),
                              ),
                              Expanded(
                                child: Text(items[row * 3 + col].title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.hankoSans(
                                        fontSize: AppTheme.hankoDataSmallSize,
                                        height: 1.3)),
                              ),
                            ],
                          )
                        : null,
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A print's field of colour: [tone] at up to 45% over sumi from the top,
/// held dark enough for washi (_fieldOver), fading to sumi by 62% of the
/// print's height. It fades in over 400 ms when the tone arrives (at once
/// when the system asks for no animations); plain sumi without one.
class _FieldGround extends StatelessWidget {
  const _FieldGround({required this.tone});

  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final tone = this.tone;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(
          end: tone == null ? AppTheme.hankoSumi : _fieldOver(tone, 0.45)),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 400),
      builder: (context, field, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [field ?? AppTheme.hankoSumi, AppTheme.hankoSumi],
            stops: const [0, 0.62],
          ),
        ),
      ),
    );
  }
}

/// Your taste as a print (round seven). Shahid's words (2026-11-03): "the
/// current design is bad just the letters and numbers on black
/// background". So each archetype has a colour world of its own
/// (_archetypeColour), laid as the card had it before Hanko: a diagonal
/// field from that colour at the top left, through sumi, to a deeper
/// neighbour of it at the foot, with rings in the corner where the old card
/// had its circle. On it: your name; your archetype as the headline, Shippori
/// 34 washi (a reading of your list, not a verdict, so never coral); the
/// Taste page's words for it; your Genre DNA drawn as a double helix
/// (_HelixPainter), your top genre in the archetype's own colour; and three
/// figures, the average on the 1-10 scale only (question 96).
///
/// No covers: question 13 keeps AniList art out of exports that never had
/// it, and this card never had any.
class _TastePrint extends StatelessWidget {
  const _TastePrint({
    required this.username,
    required this.archetype,
    required this.description,
    required this.genres,
    required this.avgRating,
    required this.completed,
    required this.total,
  });

  final String username;
  final String archetype;

  /// The Taste page's sentences about the archetype.
  final String description;

  /// Your genres by how many of your titles have each, as the Taste page
  /// counts them.
  final List<GenreData> genres;
  final double avgRating;
  final int completed;
  final int total;

  /// The DNA's five tones: your top genre in the archetype's colour, lifted
  /// towards washi; the rest in washi, fainter down the list.
  static List<Color> _dnaTones(Color colour) => [
        Color.lerp(colour, AppTheme.hankoWashi, 0.3)!,
        AppTheme.hankoWashi.withValues(alpha: 0.9),
        AppTheme.hankoWashi.withValues(alpha: 0.62),
        AppTheme.hankoWashi.withValues(alpha: 0.42),
        AppTheme.hankoWashi.withValues(alpha: 0.28),
      ];

  @override
  Widget build(BuildContext context) {
    final colour = _archetypeColour(archetype);
    final dna = genres.take(5).toList();
    final tones = _dnaTones(colour);
    final percent = [for (final g in dna) (g.percentage * 100).round()];
    return _Print(
      kind: 'Taste Card',
      footnote: DateFormat('MMMM yyyy').format(DateTime.now()),
      ground: _TasteGround(colour: colour),
      children: [
        _PrintByline(username),
        const SizedBox(height: 12),
        Text(archetype, style: AppTheme.hankoSerif(fontSize: 34, height: 1.12)),
        if (description.isNotEmpty) ...[
          const SizedBox(height: 10),
          // The Taste page's typewriter apostrophes, set typographic here.
          Text(description.replaceAll("'", '’'),
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  color: _Print.secondary,
                  height: 1.45)),
        ],
        if (dna.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Genre DNA',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoDataSmallSize,
                  weight: FontWeight.w500,
                  color: _Print.secondary,
                  height: 1.2,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Semantics(
            image: true,
            label: 'Genre DNA: ${[
              for (var i = 0; i < dna.length; i++)
                '${dna[i].name} ${percent[i]}%'
            ].join(', ')}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: CustomPaint(
                    painter: _HelixPainter(
                      shares: [for (final g in dna) g.count],
                      tones: tones,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < dna.length; i++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: tones[i],
                              borderRadius: BorderRadius.circular(
                                  AppTheme.hankoRadius),
                            ),
                            child: const SizedBox.square(dimension: 8),
                          ),
                          const SizedBox(width: 6),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(text: dna[i].name),
                              TextSpan(
                                text: '  ${percent[i]}%',
                                style: AppTheme.hankoSans(
                                    fontSize: AppTheme.hankoDataSmallSize,
                                    weight: FontWeight.w500,
                                    color: _Print.secondary,
                                    height: 1.3,
                                    tabular: true),
                              ),
                            ]),
                            style:
                                AppTheme.hankoSans(fontSize: 12, height: 1.3),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
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
      ],
    );
  }
}

/// Each archetype's colour on the Taste Card (round seven). Four are the
/// Monthly Aura's own (ocean blue, mystic purple, golden warmth, forest
/// green), for the genres that make those archetypes; the rest are new, one
/// per archetype. Every one is at least 25° of hue from coral's, which
/// means only your own verdicts.
Color _archetypeColour(String archetype) => switch (archetype) {
      'The Thrill Seeker' => const Color(0xFFE6B422), // saffron
      'The Emotional Soul' => const Color(0xFF4A7FB5), // ocean blue
      'The Deep Thinker' => const Color(0xFF9B59B6), // mystic purple
      'The Comfort Watcher' => const Color(0xFFD4A96A), // golden warmth
      'The World Builder' => const Color(0xFF4A9B6F), // forest green
      'The Visionary' => const Color(0xFF3EA3C4), // cyan
      'The Dark Explorer' => const Color(0xFF8E3B5E), // wine
      'The Connoisseur' => const Color(0xFF6F72C9), // indigo
      'The Picky Viewer' => const Color(0xFF4FA39A), // sea glass
      _ => const Color(0xFF9AAE5B), // olive: The All-Rounder
    };

/// The Taste Card's ground: the diagonal field it had before Hanko (a
/// colour at the top left, sumi, a deeper colour at the foot), now from the
/// archetype's colour and its neighbour 30° round the wheel, turning the
/// way that avoids coral; and two thin washi rings in the top right corner,
/// where the old card had its circle.
class _TasteGround extends StatelessWidget {
  const _TasteGround({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(colour);
    var hue = (hsv.hue + 30) % 360;
    // Within 25° of coral's hue (about 9°): turn the other way.
    if (hue > 344 || hue < 34) hue = (hsv.hue - 30) % 360;
    final far = hsv.withHue(hue).toColor();
    return CustomPaint(
      foregroundPainter: const _RingsPainter(
        centre: Offset(_Print.width - 26, 30),
        radii: [86, 128],
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // Jewel tones (_jewel): as deep as the words allow, and still
            // the archetype's colour, where sumi would grey it out.
            colors: [
              _jewel(colour, 0.06),
              AppTheme.hankoSumi,
              _jewel(far, 0.04),
            ],
            stops: const [0, 0.6, 1],
          ),
        ),
      ),
    );
  }
}

/// Thin washi rings (7%, 1 px) round [centre], over a field: the Taste
/// Card's corner and the Monthly Aura's glow. Line only, so the words they
/// pass under keep their contrast.
class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.centre, required this.radii});

  final Offset centre;
  final List<double> radii;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppTheme.hankoWashi.withValues(alpha: 0.07);
    for (final r in radii) {
      canvas.drawCircle(centre, r, ring);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) =>
      oldDelegate.centre != centre || !listEquals(oldDelegate.radii, radii);
}

/// Genre DNA as a double helix: two washi strands crossing four times across
/// the print, and a rung every 6 px between them, shared out among your top
/// genres by how many of your titles have each, from the left. Each genre's
/// rungs are its tone; a rung seen nearly edge-on, where the strands cross,
/// is fainter, which gives the twist its depth.
class _HelixPainter extends CustomPainter {
  const _HelixPainter({required this.shares, required this.tones});

  /// How many titles have each genre, most first.
  final List<int> shares;
  final List<Color> tones;

  @override
  void paint(Canvas canvas, Size size) {
    final total = shares.fold<int>(0, (a, b) => a + b);
    if (total == 0) return;
    final mid = size.height / 2, amp = size.height / 2 - 3;
    double y(double x, double phase) =>
        mid + amp * math.sin(2 * math.pi * 4 * x / size.width + phase);

    const step = 6.0;
    final count = (size.width / step).floor();
    final rung = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    var g = 0;
    var upTo = shares[0] / total;
    for (var k = 0; k < count; k++) {
      final f = (k + 0.5) / count;
      while (f > upTo && g < shares.length - 1) {
        g++;
        upTo += shares[g] / total;
      }
      final x = step / 2 + k * step;
      final y1 = y(x, 0), y2 = y(x, math.pi);
      final open = ((y1 - y2).abs() / (2 * amp)).clamp(0.0, 1.0);
      final tone = tones[g % tones.length];
      rung.color = tone.withValues(alpha: tone.a * (0.4 + 0.6 * open));
      canvas.drawLine(Offset(x, y1), Offset(x, y2), rung);
    }

    final strand = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = AppTheme.hankoWashi.withValues(alpha: 0.55);
    for (final phase in const [0.0, math.pi]) {
      final path = Path()..moveTo(0, y(0, phase));
      for (var x = 2.0; x <= size.width; x += 2) {
        path.lineTo(x, y(x, phase));
      }
      canvas.drawPath(path, strand);
    }
  }

  @override
  bool shouldRepaint(_HelixPainter oldDelegate) =>
      !listEquals(oldDelegate.shares, shares) ||
      !listEquals(oldDelegate.tones, tones);
}

/// A figure on a print: the number in Shippori 26, washi, over its word in
/// Jost 11, stone hi.
class _PrintFigure extends StatelessWidget {
  const _PrintFigure(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: AppTheme.hankoSerif(fontSize: 26, height: 1.1)),
        const SizedBox(height: 4),
        Text(label,
            style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoDataSmallSize,
                color: _Print.secondary,
                height: 1.2)),
      ],
    );
  }
}

/// Monthly Aura as a print (round seven). Shahid's words (2026-11-03):
/// "Montly aura also bad just a colored box with letters". So the aura is a
/// glow again, as it was before Hanko: the month's colour (named from the
/// genre that led it, as before) radiates from behind a fan of the covers
/// you added this month, with faint rings round it, and fades to sumi at
/// the edges (_AuraGlowPainter). Under the fan: the aura's name in Shippori
/// 30 beside a flat dot of its colour, which genre led the month and how
/// many titles you added, and a ribbon of those covers' own colours.
///
/// The fan holds up to seven covers, the newest in front at the middle; the
/// old row of six cut off the rest of a long month too. An empty month
/// keeps its named aura (question 98) and shows the empty place where a
/// cover will go.
class _AuraPrint extends StatelessWidget {
  const _AuraPrint({
    required this.username,
    required this.month,
    required this.anime,
    required this.auraColor,
    required this.auraName,
    required this.leadGenre,
  });

  final String username;
  final String month;
  final List<_AnimeEntry> anime;
  final Color auraColor;
  final String auraName;

  /// The genre the month's titles share most; null for an empty month.
  final String? leadGenre;

  static const int _fanMax = 7;
  static const double _fanHeight = 180;

  /// The fan's middle, from the print's top: where content starts, the
  /// month (16 tall), 4, the byline (26), 14, then half the fan. The month
  /// and byline keep those heights, one line each, so the glow can be placed
  /// before the print is laid out.
  static const double _fanCentre =
      _Print.contentTop + 16 + 4 + 26 + 14 + _fanHeight / 2;

  @override
  Widget build(BuildContext context) {
    final n = anime.length;
    // Newest first, so the newest stands in front.
    final covers = [...anime]..sort((a, b) => (b.addedAt ?? DateTime(0))
        .compareTo(a.addedAt ?? DateTime(0)));
    final shown = covers.take(_fanMax).toList();
    final lead = leadGenre;
    return _Tones(
      urls: [
        for (final a in shown)
          if ((a.imageUrl ?? '').isNotEmpty) a.imageUrl!,
      ],
      builder: (context, tones) {
        final palette = tones.whereType<Color>().toList();
        return _Print(
          kind: 'Monthly Aura',
          ground: CustomPaint(
            painter: _AuraGlowPainter(colour: auraColor, centreY: _fanCentre),
          ),
          children: [
            SizedBox(
              height: 16,
              child: Text(month,
                  maxLines: 1,
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      weight: FontWeight.w500,
                      color: _Print.secondary,
                      height: 1.2,
                      letterSpacing: 0.6)),
            ),
            const SizedBox(height: 4),
            SizedBox(height: 26, child: _PrintByline(username, oneLine: true)),
            const SizedBox(height: 14),
            SizedBox(
              height: _fanHeight,
              width: double.infinity,
              child: shown.isEmpty
                  ? const Center(
                      child: HankoSeal.unrated(
                        size: 132,
                        width: 94,
                        showAdd: false,
                        semanticLabel: 'No covers yet this month',
                      ),
                    )
                  : _CoverFan(covers: shown),
            ),
            const SizedBox(height: 16),
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
                      style: AppTheme.hankoSerif(fontSize: 30, height: 1.15)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              n == 0 || lead == null
                  ? 'Nothing added yet this month.'
                  : '${n == 1 ? '1 title' : '$n titles'} added. '
                      '$lead led the month.',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  color: _Print.secondary,
                  height: 1.4),
            ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('The month’s colours',
                  style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoDataSmallSize,
                      weight: FontWeight.w500,
                      color: _Print.secondary,
                      height: 1.2,
                      letterSpacing: 0.6)),
              const SizedBox(height: 6),
              // The covers' colours (_CoverTones) as one ribbon; the hairline
              // until they're read.
              SizedBox(
                height: 10,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(AppTheme.hankoRadius),
                    color: palette.isEmpty
                        ? AppTheme.hankoHairline
                        : palette.length == 1
                            ? palette.first
                            : null,
                    gradient: palette.length < 2
                        ? null
                        : LinearGradient(colors: palette),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Monthly Aura's ground: the aura colour glowing round the fan's middle.
/// Strongest (70% over sumi) behind the covers, showing between them and
/// round their tops, then a deep tone of the colour (_jewel) held dark
/// enough for washi by the time it reaches any words, fading to sumi at the
/// print's edges; with three faint rings round it.
class _AuraGlowPainter extends CustomPainter {
  const _AuraGlowPainter({required this.colour, required this.centreY});

  final Color colour;

  /// The fan's middle, from the print's top.
  final double centreY;

  /// [c] turned out of coral's hue when it falls within Hanko's 25° guard
  /// (the one Detail's cover tint keeps), to 30° from coral on its own side.
  /// Coral means only your own verdicts, so the glow, which is decoration,
  /// never takes it: Coral Fire (an empty month's aura, question 98) and
  /// Blazing Orange glow amber, Crimson Edge a deep pink. The dot and the
  /// name keep the aura's own colour.
  static Color _awayFromCoral(Color c) {
    final hsv = HSVColor.fromColor(c);
    final coral = HSVColor.fromColor(AppTheme.hankoCoral).hue;
    var d = hsv.hue - coral;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    if (d.abs() > AppTheme.hankoTintHueGuard) return c;
    return hsv.withHue((coral + (d < 0 ? -30 : 30)) % 360).toColor();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, centreY);
    final hue = _awayFromCoral(colour);
    final core =
        Color.alphaBlend(hue.withValues(alpha: 0.7), AppTheme.hankoSumi);
    final glow = Paint()
      ..shader = ui.Gradient.radial(
        centre,
        size.width * 0.95,
        [
          core,
          core,
          _jewel(hue, 0.06),
          _jewel(hue, 0.03),
          AppTheme.hankoSumi,
        ],
        // The core reaches 67 px; by 103 px it is at its held strength,
        // short of the nearest words (the byline and the aura's name,
        // 106 px from the middle).
        const [0, 0.22, 0.34, 0.66, 1],
      );
    canvas.drawRect(Offset.zero & size, glow);
    _RingsPainter(centre: centre, radii: const [118, 152, 190])
        .paint(canvas, size);
  }

  @override
  bool shouldRepaint(_AuraGlowPainter oldDelegate) =>
      oldDelegate.colour != colour || oldDelegate.centreY != centreY;
}

/// The month's covers held as a fan: the newest in front at the middle,
/// the next ones alternating out to each side, each turned a little more and
/// set a little lower, like cards in a hand. Each sits on a 2 px sumi
/// keyline with a hard shadow under it (no blur, so it costs nothing to
/// draw). The covers carry their titles to a screen reader as one image.
class _CoverFan extends StatelessWidget {
  const _CoverFan({required this.covers});

  /// Up to seven, newest first.
  final List<_AnimeEntry> covers;

  @override
  Widget build(BuildContext context) {
    final n = covers.length;
    final w = n == 1 ? 104.0 : (n <= 3 ? 94.0 : 80.0);
    final h = w * 325 / 230;
    final spread =
        n == 1 ? 0.0 : math.min(44.0, (_Print.inner - w - 8) / (n - 1));
    final turn = (n <= 3 ? 7.0 : 5.0) * math.pi / 180;
    final middle = (n - 1) / 2;
    // Places from the middle out, the right side first: the newest cover
    // takes the first.
    final places = List<int>.generate(n, (i) => i)
      ..sort((a, b) {
        final d = (a - middle).abs().compareTo((b - middle).abs());
        return d != 0 ? d : b.compareTo(a);
      });
    // Each place sits lower by 2.4 px times the square of its distance from
    // the middle; the fan is lifted by half the lowest drop, to centre it.
    double drop(int place) => (place - middle) * (place - middle) * 2.4;
    final lift = drop(0) / 2;
    return Semantics(
      image: true,
      label: 'Covers of the titles you added this month: '
          '${covers.map((a) => a.title).join(', ')}',
      excludeSemantics: true,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // The outermost first, so the newest is drawn last, on top.
          for (var i = n - 1; i >= 0; i--)
            Transform.translate(
              offset: Offset((places[i] - middle) * spread,
                  drop(places[i]) - lift),
              child: Transform.rotate(
                angle: (places[i] - middle) * turn,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.hankoSumi,
                    borderRadius:
                        BorderRadius.circular(AppTheme.hankoRadius + 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x8C121110),
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.hankoKeyline),
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: _PrintCover(
                          url: covers[i].imageUrl, title: covers[i].title),
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
// Top 9 editor (round seven)
// ─────────────────────────────────────────────────────────────

/// Above the Top 9 print: how its nine are chosen, in Jost 13 stone, and
/// Edit Top 9 beside it. Under large text the line wraps and the tile keeps
/// its words.
class _Top9Header extends StatelessWidget {
  const _Top9Header({required this.pickedByYou, required this.onEdit});

  final bool pickedByYou;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            pickedByYou
                ? 'Your own nine, in your order.'
                : 'Your nine highest ratings, until you pick your own.',
            style: AppTheme.hankoSans(
                fontSize: AppTheme.hankoMetaSize,
                color: AppTheme.hankoStone,
                height: 1.4),
          ),
        ),
        const SizedBox(width: 12),
        _TextTile(label: 'Edit Top 9', onTap: onEdit),
      ],
    );
  }
}

/// What the editor leaves: the nine in order, and whether they're your own
/// picks; if not, they're your highest ratings, kept as the default.
class _Top9Edit {
  const _Top9Edit({required this.ids, required this.pickedByYou});

  final List<String> ids;
  final bool pickedByYou;
}

/// The Top 9 editor (round seven). Shahid's words (2026-11-03): "make this
/// top 9 editable so I can pick my own first 2nd and until 9". It opens on
/// the nine as the card shows them: your highest ratings until you pick.
/// Each place is a row with its number, the cover, the title and your seal
/// (coral is right here, since it is your verdict).
///  - Drag a row by its handle to move it. On a keyboard, Alt with the up or
///    down arrow moves the row in focus, and focus goes with it. A screen
///    reader has Move up and Move down on each row (and the list's own
///    moves).
///  - Tap a row to choose another title for that place (_Top9PickScreen).
///  - Remove takes a title out; the ones after it move up, and the empty
///    places stay at the end, each with "Add a title".
///  - "Use my highest ratings" puts the default back.
/// Back and Done both keep what you leave; nothing is stored before then.
class _Top9EditScreen extends StatefulWidget {
  const _Top9EditScreen({
    required this.entries,
    required this.picks,
    required this.highestRated,
    required this.pickedByYou,
  });

  /// Your whole list, to pick from.
  final List<_AnimeEntry> entries;

  /// The nine as the card shows them now, in order.
  final List<String> picks;

  /// Your nine highest ratings, the default.
  final List<String> highestRated;

  /// Whether [picks] are your own, not [highestRated].
  final bool pickedByYou;

  @override
  State<_Top9EditScreen> createState() => _Top9EditScreenState();
}

class _Top9EditScreenState extends State<_Top9EditScreen> {
  late List<String> _ids = List.of(widget.picks);
  late bool _pickedByYou = widget.pickedByYou;
  late final Map<String, _AnimeEntry> _byId = {
    for (final a in widget.entries) a.id: a,
  };

  /// One focus node per title, kept here: the list rebuilds a row it moves,
  /// so a node the row made itself would be lost with the move.
  final Map<String, FocusNode> _focus = {};

  FocusNode _focusFor(String id) =>
      _focus.putIfAbsent(id, () => FocusNode(debugLabel: 'Top 9 $id'));

  @override
  void dispose() {
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Any change makes the nine your own.
  void _change(VoidCallback edit) {
    setState(() {
      edit();
      _pickedByYou = true;
    });
  }

  /// Moves the title at [from] to [to], counted after it has left its place
  /// (as ReorderableListView's onReorderItem gives them).
  void _move(int from, int to) {
    if (from == to || to < 0 || to >= _ids.length) return;
    _change(() => _ids.insert(to, _ids.removeAt(from)));
  }

  /// [_move] from the keyboard or a screen reader, with focus kept on the
  /// title as it moves.
  void _moveKeepingFocus(int from, int to) {
    if (from == to || to < 0 || to >= _ids.length) return;
    final id = _ids[from];
    _move(from, to);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusFor(id).requestFocus();
    });
  }

  void _remove(int place) => _change(() => _ids.removeAt(place));

  /// Chooses a title for [place]: one already in your nine swaps with it; an
  /// empty place takes the next free spot at the end.
  Future<void> _choose(int place) async {
    final id = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _Top9PickScreen(
          entries: widget.entries,
          picks: List.of(_ids),
          place: place,
        ),
      ),
    );
    if (id == null || !mounted) return;
    _change(() {
      final there = _ids.indexOf(id);
      if (place < _ids.length) {
        if (there >= 0) _ids[there] = _ids[place];
        _ids[place] = id;
      } else if (there < 0) {
        _ids.add(id);
      }
    });
  }

  void _useHighestRated() => setState(() {
        _ids = List.of(widget.highestRated);
        _pickedByYou = false;
      });

  void _done() => Navigator.pop(
      context, _Top9Edit(ids: List.of(_ids), pickedByYou: _pickedByYou));

  @override
  Widget build(BuildContext context) {
    final meta = AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize,
        color: AppTheme.hankoStone,
        height: 1.45);
    return PopScope<_Top9Edit>(
      canPop: false,
      // A system Back keeps your changes too: it closes the editor the way
      // Done does.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_sharp),
            color: AppTheme.hankoWashi,
            onPressed: _done,
          ),
          title: Text('Your Top 9', style: AppTheme.hankoSerif(fontSize: 20)),
        ),
        body: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          padding: const EdgeInsets.only(bottom: 24),
          header: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.hankoGutter, 16, AppTheme.hankoGutter, 12),
            child: Text(
                'Your first place leads the card. Drag a title by its '
                'handle to move it, or tap it to choose another.',
                style: meta),
          ),
          itemCount: _ids.length,
          onReorderItem: _move,
          proxyDecorator: (child, index, animation) => Material(
            color: AppTheme.hankoSumi3,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.hankoEdge)),
              child: child,
            ),
          ),
          itemBuilder: (context, i) => _Top9EditRow(
            key: ValueKey(_ids[i]),
            index: i,
            count: _ids.length,
            entry: _byId[_ids[i]],
            focusNode: _focusFor(_ids[i]),
            onReplace: () => _choose(i),
            onRemove: () => _remove(i),
            onMove: (to) => _moveKeepingFocus(i, to),
          ),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var p = _ids.length; p < 9; p++)
                _Top9EmptyRow(place: p + 1, onTap: () => _choose(p)),
              if (_pickedByYou && widget.highestRated.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.hankoGutter),
                  child: _TextTile(
                      label: 'Use my highest ratings',
                      onTap: _useHighestRated),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.hankoGutter, 8, AppTheme.hankoGutter, 12),
            child: _DoneTile(onTap: _done),
          ),
        ),
      ),
    );
  }
}

/// One filled place in the editor. The row's tap (choose another) and its
/// keyboard focus live in its own semantics node, named by place, title and
/// your rating, with Move up and Move down; Remove and the drag handle stand
/// beside it.
class _Top9EditRow extends StatelessWidget {
  const _Top9EditRow({
    super.key,
    required this.index,
    required this.count,
    required this.entry,
    required this.focusNode,
    required this.onReplace,
    required this.onRemove,
    required this.onMove,
  });

  final int index;
  final int count;
  final _AnimeEntry? entry;
  final FocusNode focusNode;
  final VoidCallback onReplace;
  final VoidCallback onRemove;
  final void Function(int to) onMove;

  @override
  Widget build(BuildContext context) {
    final place = index + 1;
    final title = entry?.title ?? '';
    final rating = entry?.rating;
    final seal = rating != null && _Top9Place._onScale(rating) ? rating : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTheme.hankoGutter - 8, 2, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                    () => onMove(index - 1),
                const SingleActivator(LogicalKeyboardKey.arrowDown,
                    alt: true): () => onMove(index + 1),
              },
              child: Semantics(
                container: true,
                button: true,
                label: '$place. $title'
                    '${seal == null ? '' : ', your rating ${HankoSeal.formatScore(seal)}'}',
                hint: 'Choose another',
                customSemanticsActions: {
                  if (index > 0)
                    const CustomSemanticsAction(label: 'Move up'): () =>
                        onMove(index - 1),
                  if (index < count - 1)
                    const CustomSemanticsAction(label: 'Move down'): () =>
                        onMove(index + 1),
                },
                child: InkWell(
                  focusNode: focusNode,
                  onTap: onReplace,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: AppTheme.hankoPressWash,
                  hoverColor: AppTheme.hankoPressWash,
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text('$place',
                                style: AppTheme.hankoSerif(
                                    fontSize: 22, height: 1)),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 44,
                            height: 62,
                            child: _PrintCover(url: entry?.imageUrl),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.hankoSans(
                                        fontSize:
                                            AppTheme.hankoListTitleSize,
                                        height: 1.3)),
                                const SizedBox(height: 6),
                                if (seal != null)
                                  HankoSeal.score(seal, size: 24)
                                else
                                  Text('Not rated',
                                      style: AppTheme.hankoSans(
                                          fontSize: AppTheme.hankoMetaSize,
                                          color: AppTheme.hankoStone,
                                          height: 1.3)),
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
          IconButton(
            tooltip: 'Remove',
            onPressed: onRemove,
            icon: const Icon(Icons.close_sharp),
            color: AppTheme.hankoStone,
            style: IconButton.styleFrom(
              minimumSize: const Size.square(AppTheme.hankoTouch),
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                      Radius.circular(AppTheme.hankoRadius))),
            ).copyWith(
              overlayColor:
                  const WidgetStatePropertyAll(AppTheme.hankoPressWash),
            ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const ExcludeSemantics(
              child: SizedBox(
                width: 40,
                height: AppTheme.hankoTouch,
                child: Icon(Icons.drag_handle_sharp,
                    color: AppTheme.hankoStone),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An empty place in the editor: its number in ash, Hanko's dashed slot with
/// its plus, and "Add a title", one button for a screen reader.
class _Top9EmptyRow extends StatelessWidget {
  const _Top9EmptyRow({required this.place, required this.onTap});

  final int place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter - 8, 2, AppTheme.hankoGutter - 8, 2),
      child: Semantics(
        container: true,
        button: true,
        label: 'Place $place, empty. Add a title',
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text('$place',
                        style: AppTheme.hankoSerif(
                            fontSize: 22,
                            height: 1,
                            color: AppTheme.hankoAsh)),
                  ),
                  const SizedBox(width: 6),
                  const HankoSeal.unrated(size: 62, width: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Add a title',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoListTitleSize,
                            color: AppTheme.hankoStone,
                            height: 1.3)),
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

/// The editor's main action, Done, drawn as Save card is: a washi tile with
/// sumi words (15.34:1), 2 px corners, pressed with a sumi wash, no ripple;
/// one screen-reader button with its tap and focus.
class _DoneTile extends StatelessWidget {
  const _DoneTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        color: AppTheme.hankoWashi,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: InkWell(
          onTap: onTap,
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
                  const Icon(Icons.check_sharp,
                      size: 20, color: AppTheme.hankoSumi),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text('Done',
                        style: AppTheme.hankoSans(
                          fontSize: 15,
                          weight: FontWeight.w600,
                          color: AppTheme.hankoSumi,
                          height: 1.2,
                        )),
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

/// Choosing a title for a place in your Top 9 (round seven): your whole
/// list, rated titles first by your rating (the 1-10 scale only, question
/// 96), then the rest by name, with a search. A title already in your nine
/// says which place it holds; choosing it swaps the two.
class _Top9PickScreen extends StatefulWidget {
  const _Top9PickScreen({
    required this.entries,
    required this.picks,
    required this.place,
  });

  final List<_AnimeEntry> entries;

  /// Your nine as they stand in the editor.
  final List<String> picks;

  /// The place being chosen for, from 0.
  final int place;

  @override
  State<_Top9PickScreen> createState() => _Top9PickScreenState();
}

class _Top9PickScreenState extends State<_Top9PickScreen> {
  String _query = '';

  static double? _rating(_AnimeEntry a) {
    final r = a.rating;
    return r != null && _Top9Place._onScale(r) ? r : null;
  }

  late final List<_AnimeEntry> _sorted = [...widget.entries]..sort((a, b) {
      final ra = _rating(a), rb = _rating(b);
      if (ra != null && rb != null && ra != rb) return rb.compareTo(ra);
      if (ra != null && rb == null) return -1;
      if (ra == null && rb != null) return 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _sorted
        : _sorted.where((a) => a.title.toLowerCase().contains(q)).toList();
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      borderSide: const BorderSide(color: AppTheme.hankoEdge),
    );
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_sharp),
          color: AppTheme.hankoWashi,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Place ${widget.place + 1}',
            style: AppTheme.hankoSerif(fontSize: 20)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTheme.hankoGutter, 8, AppTheme.hankoGutter, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              style: AppTheme.hankoSans(fontSize: AppTheme.hankoListTitleSize),
              cursorColor: AppTheme.hankoWashi,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search your list',
                hintStyle: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoListTitleSize,
                    color: AppTheme.hankoAsh),
                prefixIcon:
                    const Icon(Icons.search_sharp, color: AppTheme.hankoStone),
                filled: true,
                fillColor: AppTheme.hankoSumi2,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                    borderSide: const BorderSide(color: AppTheme.hankoWashi)),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.hankoGutter),
                      child: Text('Nothing on your list matches “$_query”.',
                          style: AppTheme.hankoSans(
                              color: AppTheme.hankoStone, height: 1.5)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final a = shown[i];
                      return _Top9PickRow(
                        entry: a,
                        rating: _rating(a),
                        heldAt: widget.picks.indexOf(a.id),
                        onTap: () => Navigator.pop(context, a.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One title in the picker: the cover, the title, your seal, and the place
/// it already holds in your nine, if any; one button for a screen reader.
class _Top9PickRow extends StatelessWidget {
  const _Top9PickRow({
    required this.entry,
    required this.rating,
    required this.heldAt,
    required this.onTap,
  });

  final _AnimeEntry entry;

  /// Your rating on the 1-10 scale, or null.
  final double? rating;

  /// The place it holds in your nine, from 0; -1 if none.
  final int heldAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rating = this.rating;
    final held = heldAt < 0 ? null : 'Number ${heldAt + 1} in your Top 9';
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.hankoGutter - 8, vertical: 2),
      child: Semantics(
        container: true,
        button: true,
        label: [
          entry.title,
          if (rating != null) 'your rating ${HankoSeal.formatScore(rating)}',
          ?held,
        ].join(', '),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(
                      width: 40,
                      height: 56,
                      child: _PrintCover(url: entry.imageUrl)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(entry.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoListTitleSize,
                                height: 1.3)),
                        if (rating != null || held != null) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (rating != null)
                                HankoSeal.score(rating, size: 24),
                              if (held != null)
                                Text(held,
                                    style: AppTheme.hankoSans(
                                        fontSize: AppTheme.hankoMetaSize,
                                        color: AppTheme.hankoStone,
                                        height: 1.3)),
                            ],
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
}

// ─────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────

class _AnimeEntry {
  /// The list entry's document id (the AniList id, or a MyAnimeList id for
  /// some older imports), which users/{uid}.top9 stores.
  final String id;
  final String title;
  final String? imageUrl;
  final double? rating;
  final String status;
  final List<String> genres;
  final DateTime? addedAt;

  const _AnimeEntry({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.status,
    this.rating,
    this.genres = const [],
    this.addedAt,
  });
}


