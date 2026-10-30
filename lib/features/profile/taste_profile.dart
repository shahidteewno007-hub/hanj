import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// Taste Profile Screen
// ─────────────────────────────────────────────────────────────

class TasteProfileScreen extends StatefulWidget {
  const TasteProfileScreen({super.key});

  @override
  State<TasteProfileScreen> createState() => _TasteProfileScreenState();
}

class _TasteProfileScreenState extends State<TasteProfileScreen>
    with TickerProviderStateMixin {
  bool _isLoading = true;
  TasteProfile? _profile;

  /// The list couldn't be read (question 97).
  bool _failed = false;

  late AnimationController _revealCtrl;
  late Animation<double> _revealAnim;

  /// The screen before Hanko (question 73): a coral-tinted archetype card
  /// with emoji, boxed traits, eight coloured genre bars and coloured pills.
  /// Kept switched off as design history; _buildPreHankoProfile() holds it.
  static const bool _preHanko = false;

  @override
  void initState() {
    super.initState();
    // Hanko's motion is feedback, quick and once: the page fades in over
    // the sheets' 240 ms (it took 800), and not at all with Reduce Motion.
    _revealCtrl = AnimationController(
        vsync: this,
        duration: _preHanko
            ? const Duration(milliseconds: 800)
            : AppTheme.hankoSheetRise);
    _revealAnim =
        CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOut);
    _analyze();
  }

  @override
  void dispose() {
    _revealCtrl.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    setState(() {
      _isLoading = true;
      _failed = false;
    });
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _isLoading = false); return; }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('animeList').get();
      if (!mounted) return;

      final docs = snapshot.docs;
      if (docs.isEmpty) {
        setState(() { _isLoading = false; });
        return;
      }

      _profile = TasteAnalyzer.analyze(docs);
      setState(() => _isLoading = false);
      _revealCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      // Said as a failure (question 97); it showed the empty page, as if
      // the list were empty.
      setState(() {
        _isLoading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(
              _preHanko ? Icons.arrow_back_rounded : Icons.arrow_back_sharp,
              color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Anime Taste', style: AppTheme.hankoSerif(fontSize: 20)),
      ),
      body: _isLoading
          ? _buildLoading()
          : _failed
              ? _buildFailed()
              : _profile == null
                  ? _buildEmpty()
                  : _preHanko
                      ? _buildPreHankoProfile()
                      : _buildProfile(),
    );
  }

  /// The list couldn't be read (question 97): Profile's line and its Retry,
  /// at the top of the column, where the page showed its empty state as if
  /// your list were empty. The line names no cause the app can't verify
  /// (ANILIST-OFFLINE-0908-REPORT.md's rule). Retry reads the list again.
  Widget _buildFailed() {
    return _column(SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 28, AppTheme.hankoGutter, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shippori draws the typewriter apostrophe as a straight tick, so
          // the line is set with the typographic one.
          Text('Couldn’t load your list just now.',
              style: AppTheme.hankoSerif(fontSize: 17, height: 1.5)),
          const SizedBox(height: 12),
          _TextTile(label: 'Retry', onTap: _analyze),
        ],
      ),
    ));
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
                color: AppTheme.hankoWashi, strokeWidth: 2),
          ),
          const SizedBox(height: 20),
          Text('Analyzing your taste...',
              textAlign: TextAlign.center,
              style: AppTheme.hankoSans(fontSize: 15)),
          const SizedBox(height: 6),
          Text('This might take a moment',
              textAlign: TextAlign.center,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  color: AppTheme.hankoStone)),
        ],
      ),
    );
  }

  /// Nothing to read: what the page is for, at the top of its column. A
  /// failed read has its own state now (_buildFailed), so this means an
  /// empty list.
  Widget _buildEmpty() {
    return _column(SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 28, AppTheme.hankoGutter, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your taste profile',
              style: AppTheme.hankoSerif(
                  fontSize: AppTheme.hankoFeaturedSize, height: 1.25)),
          const SizedBox(height: 8),
          Text(
            'It\'s drawn from the shows on your list: your archetype, '
            'your traits, your genres and how you watch.',
            style: AppTheme.hankoSans(color: AppTheme.hankoStone, height: 1.5),
          ),
        ],
      ),
    ));
  }

  /// On a wide window the page keeps Profile's reading column (440 px plus
  /// gutters), hung on the left; on a phone it does nothing.
  Widget _column(Widget child) => Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              maxWidth: Responsive.proseMaxWidth + 2 * AppTheme.hankoGutter),
          child: child,
        ),
      );

  /// Your taste in Hanko (question 73), as one page in Profile's grammar:
  /// your archetype as its headline, in Shippori and washi, as Profile's
  /// Taste row names it; the archetype's sentence; three figures; then your
  /// traits, your genres and how you watch, each under a Shippori head, with
  /// space between them and no boxes. Gone: the coral-tinted card, the emoji
  /// (the archetype's, the traits' and the viewing style's), the eight
  /// colours of the genre bars and the coloured pills. One meaning per
  /// colour: coral is only your seal, so nothing here is coral.
  Widget _buildProfile() {
    final p = _profile!;
    final noMotion = MediaQuery.disableAnimationsOf(context);
    return FadeTransition(
      opacity: noMotion ? const AlwaysStoppedAnimation(1) : _revealAnim,
      child: _column(SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, 12, AppTheme.hankoGutter, 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your archetype',
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoLabelSize,
                    color: AppTheme.hankoStone,
                    height: 1.3)),
            const SizedBox(height: 4),
            Semantics(
              header: true,
              child: Text(p.archetype,
                  style: AppTheme.hankoSerif(fontSize: 28, height: 1.15)),
            ),
            const SizedBox(height: 12),
            // Shippori draws the typewriter apostrophe as a straight tick
            // ("doesn't"), so the sentence is set with the typographic one.
            Text(p.archetypeDesc.replaceAll("'", '’'),
                style: AppTheme.hankoSerif(fontSize: 17, height: 1.5)),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _HankoFigure('${p.totalWatched}', 'completed')),
                // With no rating on the 1–10 scale there is nothing to
                // average: a dash, as the Taste Card prints it, not "0.0".
                Expanded(
                    child: _HankoFigure(
                        p.avgRating > 0 ? p.avgRating.toStringAsFixed(1) : '—',
                        'average rating')),
                Expanded(
                    child: _HankoFigure(
                        '${(p.completionRate * 100).round()}%',
                        'completion rate')),
              ],
            ),
            // Under the average, what it leaves out (question 96), in
            // Profile's words for its seal register.
            if (p.offScaleRatings > 0) ...[
              const SizedBox(height: 12),
              Text(
                p.offScaleRatings == 1
                    ? '1 imported rating is on another scale, so it isn\'t '
                        'in the\u00A0average.'
                    : '${p.offScaleRatings} imported ratings are on another '
                        'scale, so they aren\'t in the\u00A0average.',
                style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoMetaSize,
                    color: AppTheme.hankoStone,
                    height: 1.4),
              ),
            ],
            const SizedBox(height: 36),
            const _HankoHead('Your traits'),
            for (final t in p.traits) _HankoTrait(trait: t),
            const SizedBox(height: 22),
            _HankoHead('Genre DNA',
                aside: p.topGenres.isEmpty
                    ? null
                    : 'Share of your ${p.topGenres.first.total} titles'),
            _HankoGenres(genres: p.topGenres),
            const SizedBox(height: 22),
            const _HankoHead('Viewing style'),
            _HankoViewingStyle(profile: p),
          ],
        ),
      )),
    );
  }

  /// The page before Hanko (_preHanko).
  Widget _buildPreHankoProfile() {
    final p = _profile!;
    return FadeTransition(
      opacity: _revealAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Personality card ──────────────────────────────
            _PersonalityCard(profile: p),

            const SizedBox(height: 24),

            // ── Traits ────────────────────────────────────────
            Text('Your Traits',
                style: AppTheme.serif(
                    fontSize: 18, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...p.traits.map((t) => _TraitRow(trait: t)),

            const SizedBox(height: 24),

            // ── Genre DNA ─────────────────────────────────────
            Text('Genre DNA',
                style: AppTheme.serif(
                    fontSize: 18, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            _GenreDNA(genres: p.topGenres),

            const SizedBox(height: 24),

            // ── Viewing style ─────────────────────────────────
            Text('Viewing Style',
                style: AppTheme.serif(
                    fontSize: 18, weight: FontWeight.w700)),
            const SizedBox(height: 12),
            _ViewingStyleCard(profile: p),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Taste Analyzer — pure logic
// ─────────────────────────────────────────────────────────────

/// Whether a stored rating lands on Hanj's 1–10 scale at its nearest half
/// step, as the seal register places it (Profile's rule, stage H5).
bool _onScale(double rating) {
  final step = (rating * 2).round() / 2;
  return step >= 1 && step <= 10;
}

class TasteAnalyzer {
  static TasteProfile analyze(List<QueryDocumentSnapshot> docs) {
    final Map<String, int> genreCounts   = {};
    final List<double>      ratings      = [];
    int offScale     = 0;
    int completed    = 0;
    int dropped      = 0;
    int watching     = 0;
    int planToWatch  = 0;
    int totalEps     = 0;

    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';
      final genres = (data['genres'] as List<dynamic>?)?.cast<String>() ?? [];
      final rating = (data['userRating'] as num?)?.toDouble();
      final eps    = (data['episodes'] as num?)?.toInt() ?? 0;

      for (final g in genres) {
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
      }

      // Only ratings on Hanj's 1–10 scale are averaged (question 96), as
      // Profile and Advanced Stats count them. An imported rating on another
      // scale (D20: a 70 from a 100-point list) would pull the average far
      // off: one 70 beside an 8 and a 6.5 made it 28.2, and gave "High
      // standards". Those are counted instead, so the page can say so.
      if (rating != null) {
        if (_onScale(rating)) {
          ratings.add(rating);
        } else {
          offScale++;
        }
      }
      if (status == 'COMPLETED') { completed++; totalEps += eps; }
      if (status == 'DROPPED')   dropped++;
      if (status == 'WATCHING')  watching++;
      if (status == 'PLAN_TO_WATCH') planToWatch++;
    }

    final total = docs.length;
    final avgRating = ratings.isEmpty
        ? 0.0
        : ratings.reduce((a, b) => a + b) / ratings.length;

    // Sort genres
    final sortedGenres = (genreCounts.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(8)
        .map((e) => GenreData(e.key, e.value, total))
        .toList();

    // Determine archetype
    final topGenres = sortedGenres.take(3).map((g) => g.name).toList();
    final archetype = _archetype(topGenres, avgRating, dropped, completed);

    // Build traits
    final traits = _buildTraits(
      topGenres: topGenres,
      avgRating: avgRating,
      dropped: dropped,
      completed: completed,
      total: total,
      watching: watching,
    );

    // Viewing style
    final completionRate = total > 0 ? completed / total : 0.0;
    final dropRate       = total > 0 ? dropped / total   : 0.0;

    return TasteProfile(
      archetype:      archetype,
      archetypeEmoji: _archetypeEmoji(archetype),
      archetypeDesc:  _archetypeDesc(archetype),
      traits:         traits,
      topGenres:      sortedGenres,
      avgRating:      avgRating,
      offScaleRatings: offScale,
      completionRate: completionRate,
      dropRate:       dropRate,
      totalWatched:   completed,
      totalEpisodes:  totalEps,
      watching:       watching,
      planToWatch:    planToWatch,
    );
  }

  static String _archetype(List<String> genres, double avg,
      int dropped, int completed) {
    final g = genres.join(' ');
    if (g.contains('Action') && g.contains('Thriller')) return 'The Thrill Seeker';
    if (g.contains('Drama') && g.contains('Romance'))   return 'The Emotional Soul';
    if (g.contains('Mystery') || g.contains('Psychological')) return 'The Deep Thinker';
    if (g.contains('Slice of Life') || g.contains('Comedy')) return 'The Comfort Watcher';
    if (g.contains('Fantasy') && g.contains('Adventure')) return 'The World Builder';
    if (g.contains('Sci-Fi') || g.contains('Mecha'))    return 'The Visionary';
    if (g.contains('Horror') || g.contains('Supernatural')) return 'The Dark Explorer';
    if (avg >= 8.0 && dropped < 2)  return 'The Connoisseur';
    if (dropped > completed / 3)    return 'The Picky Viewer';
    return 'The All-Rounder';
  }

  static String _archetypeEmoji(String archetype) {
    final map = {
      'The Thrill Seeker':  '⚡',
      'The Emotional Soul': '💙',
      'The Deep Thinker':   '🧠',
      'The Comfort Watcher':'🌙',
      'The World Builder':  '🌍',
      'The Visionary':      '🔭',
      'The Dark Explorer':  '🖤',
      'The Connoisseur':    '✨',
      'The Picky Viewer':   '🎯',
      'The All-Rounder':    '⚖️',
    };
    return map[archetype] ?? '🎌';
  }

  static String _archetypeDesc(String archetype) {
    final map = {
      'The Thrill Seeker':
          'You live for the rush. High stakes, intense action, and tension that keeps you on the edge — that\'s your anime.',
      'The Emotional Soul':
          'You watch anime to feel. The kind that wrecks you emotionally and stays with you for days.',
      'The Deep Thinker':
          'You\'re drawn to complexity. Unreliable narrators, mind-bending twists, and stories that make you question everything.',
      'The Comfort Watcher':
          'Anime is your safe place. You prefer warmth, laughter, and stories that feel like home.',
      'The World Builder':
          'You want to get lost. The bigger the world, the better — lore, magic systems, epic adventures.',
      'The Visionary':
          'You gravitate toward the future. Technology, philosophy, and ideas that challenge what it means to be human.',
      'The Dark Explorer':
          'You\'re not afraid of the dark. Horror, tragedy, and morally complex stories are where you thrive.',
      'The Connoisseur':
          'Quality over quantity. You have high standards and an eye for what separates good anime from great anime.',
      'The Picky Viewer':
          'You know what you want. Life\'s too short for mediocre anime — you\'re not afraid to drop something that doesn\'t click.',
      'The All-Rounder':
          'You watch everything. Genre doesn\'t define your taste — a good story is a good story.',
    };
    return map[archetype] ?? 'Your taste is uniquely yours.';
  }

  static List<Trait> _buildTraits({
    required List<String> topGenres,
    required double avgRating,
    required int dropped,
    required int completed,
    required int total,
    required int watching,
  }) {
    final traits = <Trait>[];
    final g = topGenres.join(' ');

    if (g.contains('Action') || g.contains('Thriller')) {
      traits.add(Trait(
        icon: '⚡',
        label: 'High-tension storytelling',
        desc: 'You prefer anime that keeps you locked in.',
      ));
    }
    if (g.contains('Drama') || g.contains('Romance')) {
      traits.add(Trait(
        icon: '💔',
        label: 'Emotional storytelling',
        desc: 'You don\'t shy away from stories that hurt.',
      ));
    }
    if (g.contains('Mystery') || g.contains('Psychological')) {
      traits.add(Trait(
        icon: '🧩',
        label: 'Complex narratives',
        desc: 'You love piecing things together.',
      ));
    }
    if (g.contains('Slice of Life') || g.contains('Comedy')) {
      traits.add(Trait(
        icon: '☕',
        label: 'Comfort-driven viewing',
        desc: 'You use anime to unwind and recharge.',
      ));
    }
    if (g.contains('Fantasy') || g.contains('Adventure')) {
      traits.add(Trait(
        icon: '🗺️',
        label: 'World-building appreciation',
        desc: 'The more immersive the world, the better.',
      ));
    }
    if (avgRating >= 8.0) {
      traits.add(Trait(
        icon: '🎯',
        label: 'High standards',
        desc: 'You rate critically — your 10s actually mean something.',
      ));
    }
    if (avgRating < 6.5 && avgRating > 0) {
      traits.add(Trait(
        icon: '😤',
        label: 'Hard to impress',
        desc: 'You don\'t hand out high scores easily.',
      ));
    }
    if (watching > 3) {
      traits.add(Trait(
        icon: '📺',
        label: 'Always watching',
        desc: 'You keep multiple series running at once.',
      ));
    }
    if (dropped < 2 && completed > 5) {
      traits.add(Trait(
        icon: '🏁',
        label: 'Dedicated finisher',
        desc: 'Once you start, you see it through.',
      ));
    }
    if (dropped > total * 0.25 && total > 4) {
      traits.add(Trait(
        icon: '⚔️',
        label: 'Ruthlessly selective',
        desc: 'You know when an anime isn\'t working for you.',
      ));
    }

    // Always include at least 3
    if (traits.length < 3) {
      traits.add(Trait(
        icon: '🎌',
        label: 'Genuine anime fan',
        desc: 'Your list speaks for itself.',
      ));
    }

    return traits.take(5).toList();
  }
}

// ─────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────

class TasteProfile {
  final String archetype;
  final String archetypeEmoji;
  final String archetypeDesc;
  final List<Trait> traits;
  final List<GenreData> topGenres;

  /// The average of your ratings on Hanj's 1–10 scale; 0 with none.
  final double avgRating;

  /// Imported ratings on another scale, left out of [avgRating].
  final int offScaleRatings;
  final double completionRate;
  final double dropRate;
  final int totalWatched;
  final int totalEpisodes;
  final int watching;
  final int planToWatch;

  const TasteProfile({
    required this.archetype,
    required this.archetypeEmoji,
    required this.archetypeDesc,
    required this.traits,
    required this.topGenres,
    required this.avgRating,
    required this.offScaleRatings,
    required this.completionRate,
    required this.dropRate,
    required this.totalWatched,
    required this.totalEpisodes,
    required this.watching,
    required this.planToWatch,
  });
}

class Trait {
  final String icon;
  final String label;
  final String desc;
  const Trait({required this.icon, required this.label, required this.desc});
}

class GenreData {
  final String name;
  final int count;
  final int total;
  const GenreData(this.name, this.count, this.total);
  double get percentage => total > 0 ? count / total : 0;
}

// ─────────────────────────────────────────────────────────────
// UI Widgets
// ─────────────────────────────────────────────────────────────

class _PersonalityCard extends StatelessWidget {
  final TasteProfile profile;
  const _PersonalityCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.2),
            const Color(0xFF1A0F08),
            AppTheme.surfaceMid,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(profile.archetypeEmoji,
                  style: const TextStyle(fontSize: 40)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR ARCHETYPE',
                      style: AppTheme.mono(
                          fontSize: 10,
                          color: AppTheme.primary,
                          letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      profile.archetype,
                      style: AppTheme.serif(
                          fontSize: 22, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            profile.archetypeDesc,
            style: AppTheme.sans(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.6),
          ),
          const SizedBox(height: 20),
          // Quick stats row
          Row(
            children: [
              _StatPill('${profile.totalWatched}', 'completed'),
              const SizedBox(width: 8),
              _StatPill(
                  (profile.avgRating).toStringAsFixed(1), 'avg rating'),
              const SizedBox(width: 8),
              _StatPill(
                  '${(profile.completionRate * 100).round()}%',
                  'completion'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String value;
  final String label;
  const _StatPill(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Text(value,
              style: AppTheme.sans(
                  fontSize: 14,
                  weight: FontWeight.w700,
                  color: AppTheme.primary)),
          Text(label,
              style: AppTheme.mono(fontSize: 9, letterSpacing: 0.5)),
        ],
      ),
    );
  }
}

class _TraitRow extends StatelessWidget {
  final Trait trait;
  const _TraitRow({required this.trait});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          Text(trait.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(trait.label,
                    style: AppTheme.sans(
                        fontSize: 14, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(trait.desc,
                    style: AppTheme.sans(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GenreDNA extends StatelessWidget {
  final List<GenreData> genres;
  const _GenreDNA({required this.genres});

  static const _genreColors = [
    AppTheme.primary,
    Color(0xFF4A7FB5),
    Color(0xFF4A9B6F),
    Color(0xFFD4A96A),
    Color(0xFFCF6679),
    Color(0xFF7B68EE),
    Color(0xFF20B2AA),
    Color(0xFFFF8C00),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: genres.asMap().entries.map((entry) {
          final i     = entry.key;
          final genre = entry.value;
          final color = _genreColors[i % _genreColors.length];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(genre.name,
                        style: AppTheme.sans(
                            fontSize: 13, weight: FontWeight.w500)),
                    const Spacer(),
                    Text('${genre.count} anime',
                        style: AppTheme.mono(
                            fontSize: 10, color: AppTheme.textMuted)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: genre.percentage),
                    duration: Duration(
                        milliseconds: 600 + i * 100),
                    curve: Curves.easeOut,
                    builder: (_, value, _) => LinearProgressIndicator(
                      value: value,
                      backgroundColor:
                          AppTheme.border.withValues(alpha: 0.5),
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 6,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ViewingStyleCard extends StatelessWidget {
  final TasteProfile profile;
  const _ViewingStyleCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final completionPct = (profile.completionRate * 100).round();
    final dropPct       = (profile.dropRate * 100).round();

    String style;
    String styleDesc;
    String styleEmoji;

    if (completionPct >= 80) {
      style = 'Dedicated Finisher';
      styleDesc = 'You commit. Once you start something, you see it through to the end.';
      styleEmoji = '🏆';
    } else if (dropPct >= 30) {
      style = 'Selective Sampler';
      styleDesc = 'You\'re not afraid to move on. You know your taste and respect your time.';
      styleEmoji = '⚔️';
    } else if (profile.watching > 3) {
      style = 'Serial Multitasker';
      styleDesc = 'You juggle multiple series at once. Variety keeps things interesting.';
      styleEmoji = '🎭';
    } else {
      style = 'Measured Viewer';
      styleDesc = 'You\'re thoughtful about what you pick up and deliberate about how you watch.';
      styleEmoji = '🎯';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(styleEmoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(style,
                    style: AppTheme.serif(
                        fontSize: 18, weight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(styleDesc,
              style: AppTheme.sans(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5)),
          const SizedBox(height: 16),
          Row(
            children: [
              _ViewingPill(
                  '$completionPct%', 'completion', AppTheme.completed),
              const SizedBox(width: 8),
              _ViewingPill('$dropPct%', 'drop rate', AppTheme.error),
              const SizedBox(width: 8),
              _ViewingPill(
                  '${profile.watching}', 'watching now', AppTheme.watching),
            ],
          ),
        ],
      ),
    );
  }
}

class _ViewingPill extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _ViewingPill(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(value,
                style: AppTheme.sans(
                    fontSize: 16,
                    weight: FontWeight.w700,
                    color: color)),
            Text(label,
                style: AppTheme.mono(fontSize: 9, letterSpacing: 0.3),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// The full taste profile in Hanko (question 73)
// ─────────────────────────────────────────────────────────────

/// A section head as Profile's (_SectionHead there, private to that file):
/// Shippori 16 in washi, an optional aside in Jost 12 stone that wraps under
/// the head when the line is too short, so large text never pushes it off.
class _HankoHead extends StatelessWidget {
  const _HankoHead(this.title, {this.aside});

  final String title;
  final String? aside;

  @override
  Widget build(BuildContext context) {
    final aside = this.aside;
    final head = Semantics(
      header: true,
      child: Text(title,
          style: AppTheme.hankoSerif(
              fontSize: AppTheme.hankoSectionSize, height: 1.3)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: aside == null
          ? head
          : SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                runSpacing: 2,
                children: [
                  head,
                  Text(aside,
                      style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoLabelSize,
                        color: AppTheme.hankoStone,
                        height: 1.3,
                      )),
                ],
              ),
            ),
    );
  }
}

/// A figure: the number in Shippori 22, washi, over its word in Jost 12,
/// stone. No pill, no colour of its own: the word says what it is.
class _HankoFigure extends StatelessWidget {
  const _HankoFigure(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: AppTheme.hankoSerif(fontSize: 22, height: 1.15)),
          const SizedBox(height: 4),
          Text(label,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  color: AppTheme.hankoStone,
                  height: 1.3)),
        ],
      ),
    );
  }
}

/// One trait: its name in Jost 15 500, washi, and its line in Jost 13,
/// stone. Grouped by space alone, without the box and the emoji it had.
class _HankoTrait extends StatelessWidget {
  const _HankoTrait({required this.trait});

  final Trait trait;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(trait.label,
              style: AppTheme.hankoSans(
                  fontSize: 15, weight: FontWeight.w500, height: 1.3)),
          const SizedBox(height: 2),
          Text(trait.desc,
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  color: AppTheme.hankoStone,
                  height: 1.4)),
        ],
      ),
    );
  }
}

/// Your genres: each name in washi with its count in stone at the line's
/// end, over a 4 px bar whose washi length is the genre's share of your
/// list, on a hairline track. One colour for all of them, as the reel draws
/// what you watched: the eight colours the bars had meant nothing, and
/// colour is kept for meaning. The bars stand at their length at once.
class _HankoGenres extends StatelessWidget {
  const _HankoGenres({required this.genres});

  final List<GenreData> genres;

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) {
      return Text('No genres on your list yet.',
          style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoMetaSize,
              color: AppTheme.hankoStone,
              height: 1.4));
    }
    return Column(
      children: [
        for (final g in genres)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Semantics(
              label: '${g.name}: ${g.count} of ${g.total} titles',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(g.name,
                            style: AppTheme.hankoSans(height: 1.3)),
                      ),
                      const SizedBox(width: 12),
                      Text('${g.count}',
                          style: AppTheme.hankoSans(
                              fontSize: AppTheme.hankoMetaSize,
                              weight: FontWeight.w500,
                              color: AppTheme.hankoStone,
                              height: 1.3,
                              tabular: true)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 4,
                    child: ColoredBox(
                      color: AppTheme.hankoHairline,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: g.percentage.clamp(0.0, 1.0),
                        child: const ColoredBox(color: AppTheme.hankoWashi),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// How you watch: the style's name in Shippori 19, its sentence in Jost 14
/// stone, and three figures. The style is read from the same thresholds as
/// before (_ViewingStyleCard); its emoji and the green, pink and coral
/// pills are gone, since the words already say what each number is.
class _HankoViewingStyle extends StatelessWidget {
  const _HankoViewingStyle({required this.profile});

  final TasteProfile profile;

  @override
  Widget build(BuildContext context) {
    final completionPct = (profile.completionRate * 100).round();
    final dropPct = (profile.dropRate * 100).round();

    final String style;
    final String styleDesc;
    if (completionPct >= 80) {
      style = 'Dedicated Finisher';
      styleDesc = 'You commit. Once you start something, you see it through to the end.';
    } else if (dropPct >= 30) {
      style = 'Selective Sampler';
      styleDesc = 'You\'re not afraid to move on. You know your taste and respect your time.';
    } else if (profile.watching > 3) {
      style = 'Serial Multitasker';
      styleDesc = 'You juggle multiple series at once. Variety keeps things interesting.';
    } else {
      style = 'Measured Viewer';
      styleDesc = 'You\'re thoughtful about what you pick up and deliberate about how you watch.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(style,
            style: AppTheme.hankoSerif(
                fontSize: AppTheme.hankoFeaturedSize, height: 1.25)),
        const SizedBox(height: 6),
        Text(styleDesc,
            style: AppTheme.hankoSans(color: AppTheme.hankoStone, height: 1.5)),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _HankoFigure('$completionPct%', 'completion')),
            Expanded(child: _HankoFigure('$dropPct%', 'drop rate')),
            Expanded(
                child: _HankoFigure('${profile.watching}', 'watching now')),
          ],
        ),
      ],
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

// ─────────────────────────────────────────────────────────────
// Compact card for Profile Screen
// ─────────────────────────────────────────────────────────────

/// Your taste on Profile, in Hanko (question 57): one of the quiet rows
/// below Profile's hairline, drawn as that screen's rows are. Your archetype
/// is its title, in washi; "Your taste:" and your top three genres are its
/// line, in stone; a chevron; and it opens the full taste profile, as the
/// card did.
///
/// What changed from the card, and why:
///  - no coral. In Hanko coral marks only your verdicts (your seal, your
///    ratings), and an archetype is a reading of your list, not a verdict.
///    The coral "YOUR TASTE" label measured 3.61:1 on the card's tinted box
///    and the genre line 4.30:1, both under AA's 4.5:1 for small text. Washi
///    on sumi measures 15.3:1 and stone 6.9:1.
///  - no emoji. Hanko draws icons, never emoji (DESIGN.md §5.4), so the
///    archetype's name carries it. The full profile still shows the emoji.
///  - while your list is read, the row already stands, titled "Your taste",
///    so nothing below it moves when it fills in. The card showed a coral
///    spinner in an 80 px box that the result then replaced.
/// The card as it was is kept behind [_TasteProfileCardState._preHankoCard].
class TasteProfileCard extends StatefulWidget {
  const TasteProfileCard({super.key});

  @override
  State<TasteProfileCard> createState() => _TasteProfileCardState();
}

class _TasteProfileCardState extends State<TasteProfileCard> {
  TasteProfile? _profile;
  bool _loading = true;

  /// The card before Hanko: a coral-tinted box with the archetype's emoji
  /// and a coral "YOUR TASTE" label. Kept, switched off, as design history.
  static const bool _preHankoCard = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('animeList').get();
      if (snapshot.docs.isNotEmpty) {
        _profile = TasteAnalyzer.analyze(snapshot.docs);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_preHankoCard) return _buildPreHanko(context);

    final profile = _profile;
    // Nothing to read (an empty list, or the read failed): no row, as the
    // card showed nothing.
    if (!_loading && profile == null) return const SizedBox.shrink();

    final genres = profile == null
        ? const <String>[]
        : profile.topGenres.take(3).map((g) => g.name).toList();
    final title = profile?.archetype ?? 'Your taste';
    final String? line = profile == null
        ? null
        : genres.isEmpty
            ? 'Your taste'
            : 'Your taste: ${_inList(genres)}';

    // Tappable while it loads too: the taste profile reads your list itself.
    // One screen-reader button, as Profile's other rows (question 104): its
    // own semantics node (container), named by the archetype and the line,
    // with the InkWell's tap and focus inside it. Over excluded semantics
    // the label left the node with neither. The row's own words are left
    // out of the tree, since the label already says them.
    return Semantics(
      container: true,
      button: true,
      label: line == null ? title : '$title. $line',
      child: InkWell(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TasteProfileScreen())),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.psychology_sharp,
                      size: 22, color: AppTheme.hankoStone),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: AppTheme.hankoSans(
                                fontSize: 15,
                                weight: FontWeight.w500,
                                height: 1.25)),
                        if (line != null) ...[
                          const SizedBox(height: 2),
                          Text(line,
                              style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoMetaSize,
                                color: AppTheme.hankoStone,
                                height: 1.3,
                              )),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.chevron_right_sharp,
                      size: 20, color: AppTheme.hankoStone),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "A", "A and B", "A, B and C", as Profile writes its lists.
  static String _inList(List<String> items) => items.length < 2
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';

  /// The card as it was before Hanko ([_preHankoCard]).
  Widget _buildPreHanko(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 80,
        child: Center(child: CircularProgressIndicator(
            color: AppTheme.primary, strokeWidth: 2)));
    }

    if (_profile == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const TasteProfileScreen())),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.primary.withValues(alpha: 0.15),
              AppTheme.surfaceMid,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Text(_profile!.archetypeEmoji,
                style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR TASTE',
                    style: AppTheme.mono(
                        fontSize: 9,
                        color: AppTheme.primary,
                        letterSpacing: 1.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _profile!.archetype,
                    style: AppTheme.serif(
                        fontSize: 16, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _profile!.topGenres.take(3).map((g) => g.name).join(' · '),
                    style: AppTheme.sans(
                        fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
