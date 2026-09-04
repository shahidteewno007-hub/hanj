import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  late AnimationController _revealCtrl;
  late Animation<double> _revealAnim;

  @override
  void initState() {
    super.initState();
    _revealCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
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
    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _isLoading = false); return; }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('animeList').get();

      final docs = snapshot.docs;
      if (docs.isEmpty) {
        setState(() { _isLoading = false; });
        return;
      }

      _profile = TasteAnalyzer.analyze(docs);
      setState(() => _isLoading = false);
      _revealCtrl.forward();
    } catch (e) {
      setState(() => _isLoading = false);
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
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Anime Taste',
            style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
      ),
      body: _isLoading
          ? _buildLoading()
          : _profile == null
              ? _buildEmpty()
              : _buildProfile(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
              color: AppTheme.primary, strokeWidth: 2),
          const SizedBox(height: 20),
          Text('Analyzing your taste...',
              style: AppTheme.sans(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Text('This might take a moment',
              style: AppTheme.sans(
                  color: AppTheme.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.psychology_outlined,
              color: AppTheme.textMuted, size: 64),
          const SizedBox(height: 20),
          Text('No data yet',
              style: AppTheme.serif(fontSize: 22, weight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Add some anime to your list\nto generate your taste profile',
            textAlign: TextAlign.center,
            style: AppTheme.sans(
                color: AppTheme.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildProfile() {
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

class TasteAnalyzer {
  static TasteProfile analyze(List<QueryDocumentSnapshot> docs) {
    final Map<String, int> genreCounts   = {};
    final List<double>      ratings      = [];
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

      if (rating != null) ratings.add(rating);
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
  final double avgRating;
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
// Compact card for Profile Screen
// ─────────────────────────────────────────────────────────────

class TasteProfileCard extends StatefulWidget {
  const TasteProfileCard({super.key});

  @override
  State<TasteProfileCard> createState() => _TasteProfileCardState();
}

class _TasteProfileCardState extends State<TasteProfileCard> {
  TasteProfile? _profile;
  bool _loading = true;

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
