import 'dart:math';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/anime_model.dart';
import '../../services/anilist_service.dart';
import '../../services/firestore_service.dart';
import '../anime_detail/anime_detail_screen.dart';

// ─────────────────────────────────────────────────────────────
// Tonight's Watch Card (home screen entry point)
// ─────────────────────────────────────────────────────────────

class TonightWatchCard extends StatelessWidget {
  const TonightWatchCard({super.key});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'MORNING'
        : hour < 17
            ? 'AFTERNOON'
            : hour < 21
                ? 'EVENING'
                : 'LATE NIGHT';

    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const TonightWatchSheet(),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A0F0A),
              const Color(0xFF2A1510),
              AppTheme.primary.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hour >= 20 || hour < 6
                    ? Icons.nightlight_round
                    : hour < 12
                        ? Icons.wb_sunny_rounded
                        : Icons.wb_twilight_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: AppTheme.mono(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Find your next anime',
                    style: AppTheme.serif(
                      fontSize: 17,
                      weight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Curated for tonight',
                    style: AppTheme.sans(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Discover',
                style: AppTheme.sans(
                  fontSize: 12,
                  weight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Bottom Sheet — Mood → Result (two steps)
// ─────────────────────────────────────────────────────────────

class TonightWatchSheet extends StatefulWidget {
  const TonightWatchSheet({super.key});

  @override
  State<TonightWatchSheet> createState() => _TonightWatchSheetState();
}

class _TonightWatchSheetState extends State<TonightWatchSheet>
    with TickerProviderStateMixin {
  final _anilist   = AnilistService();
  final _firestore = FirestoreService();

  // 0 = mood picker, 1 = result
  int _step = 0;
  String? _mood;

  Anime?  _recommendation;
  String? _reasonText;
  bool    _isLoading = false;

  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  // ── Mood options — icons only, no emojis ──────────────────────
  static const _moods = [
    _Option(Icons.bolt_rounded,           Icons.flash_on_rounded,
        'Hype',         'TRENDING_DESC',   'Action',
        Color(0xFF8B1A0A), Color(0xFF1A0603)),
    _Option(Icons.water_drop_outlined,    Icons.opacity_rounded,
        'Emotional',    'SCORE_DESC',      'Drama',
        Color(0xFF1A3A6B), Color(0xFF060D1A)),
    _Option(Icons.nightlight_round,       Icons.bedtime_outlined,
        'Cozy',         'POPULARITY_DESC', 'Slice of Life',
        Color(0xFF3A2A6B), Color(0xFF0C091A)),
    _Option(Icons.dark_mode_outlined,     Icons.nights_stay_rounded,
        'Dark',         'SCORE_DESC',      'Thriller',
        Color(0xFF1C1C1C), Color(0xFF080808)),
    _Option(Icons.theater_comedy_outlined,Icons.sentiment_satisfied_alt_outlined,
        'Funny',        'POPULARITY_DESC', 'Comedy',
        Color(0xFF6B4A10), Color(0xFF1A1106)),
    _Option(Icons.hub_outlined,           Icons.all_inclusive_rounded,
        'Mind-bending', 'SCORE_DESC',      'Mystery',
        Color(0xFF1A4A3A), Color(0xFF051A12)),
  ];

  static const _reasons = {
    'Hype':         'Tonight calls for something impossible.',
    'Emotional':    'Sometimes you just need to feel something real.',
    'Cozy':         'Slow down and stay awhile.',
    'Dark':         'Not every story needs light.',
    'Funny':        'Life\'s too short — laugh a little.',
    'Mind-bending': 'Leave reality at the door.',
  };

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _pickMood(String mood) {
    _fadeCtrl.reset();
    setState(() {
      _mood = mood;
      _step = 1;
      _isLoading = true;
    });
    _fadeCtrl.forward();
    _fetchRecommendation();
  }

  Future<void> _fetchRecommendation() async {
    final moodObj = _moods.firstWhere((m) => m.label == _mood);

    try {
      final results = await _anilist.searchAnime(
          '', genre: moodObj.genre, sort: moodObj.sort);

      if (results.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final pick = results[Random().nextInt(min(results.length, 10))];
      setState(() {
        _recommendation = pick;
        _reasonText     = _reasons[moodObj.label] ?? 'A great pick for tonight.';
        _isLoading      = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _reset() {
    _fadeCtrl.reset();
    setState(() {
      _step = 0;
      _mood = null;
      _recommendation = null;
      _reasonText = null;
      _isLoading = false;
    });
    _fadeCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0B08),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Tonight's Watch",
                        style: AppTheme.serif(
                            fontSize: 22, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      _step == 0 ? 'What pulls you tonight?' : 'Curated for your mood',
                      style: AppTheme.sans(
                          fontSize: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const Spacer(),
                if (_step == 1)
                  GestureDetector(
                    onTap: _reset,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text('Reset',
                          style: AppTheme.sans(
                              color: AppTheme.textMuted, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Expanded(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _step == 0 ? _buildMoodStep() : _buildResultStep(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 0: Mood grid ─────────────────────────────────────────
  Widget _buildMoodStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.25,
        children: _moods.map((mood) => _MoodCard(
          icon:       mood.icon,
          watermark:  mood.watermark,
          label:      mood.label,
          colorLight: mood.colorLight,
          colorDark:  mood.colorDark,
          onTap:      () => _pickMood(mood.label),
        )).toList(),
      ),
    );
  }

  // ── Step 1: Result ────────────────────────────────────────────
  Widget _buildResultStep() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
                color: AppTheme.primary, strokeWidth: 2),
            const SizedBox(height: 16),
            Text('Finding your perfect watch...',
                style: AppTheme.sans(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }

    if (_recommendation == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                color: AppTheme.textMuted, size: 48),
            const SizedBox(height: 16),
            Text('Couldn\'t find a match',
                style: AppTheme.serif(fontSize: 18)),
            const SizedBox(height: 8),
            TextButton(onPressed: _reset, child: const Text('Try again')),
          ],
        ),
      );
    }

    final anime   = _recommendation!;
    final moodObj = _moods.firstWhere((m) => m.label == _mood,
        orElse: () => _moods.first);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mood chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: moodObj.colorLight.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: moodObj.colorLight.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(moodObj.icon, size: 12, color: Colors.white70),
                const SizedBox(width: 6),
                Text(moodObj.label,
                    style: AppTheme.mono(
                        fontSize: 10,
                        color: Colors.white70,
                        letterSpacing: 0.6)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Anime result card — mood-aware glow
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(
                      builder: (_) => AnimeDetailScreen(anime: anime)));
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [moodObj.colorDark, AppTheme.surface],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: moodObj.colorLight.withValues(alpha: 0.4),
                    width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: moodObj.colorLight.withValues(alpha: 0.12),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                    child: anime.imageUrl != null
                        ? Image.network(anime.imageUrl!,
                            width: 110, height: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder())
                        : _placeholder(),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            anime.titleEnglish ?? anime.title,
                            style: AppTheme.serif(
                                fontSize: 15, weight: FontWeight.w600,
                                height: 1.3),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          if (anime.genres.isNotEmpty)
                            Text(
                              anime.genres.take(2).join(' · '),
                              style: AppTheme.mono(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                  letterSpacing: 0.5),
                            ),
                          if (anime.averageScore != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    color: Colors.amber, size: 13),
                                const SizedBox(width: 4),
                                Text(
                                  (anime.averageScore! / 10)
                                      .toStringAsFixed(1),
                                  style: AppTheme.sans(
                                      fontSize: 12,
                                      color: Colors.amber,
                                      weight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Watch Now →',
                                style: AppTheme.sans(
                                    fontSize: 11,
                                    weight: FontWeight.w600,
                                    color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Reason box
          if (_reasonText != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(moodObj.icon, size: 15, color: AppTheme.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_reasonText!,
                        style: AppTheme.sans(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            height: 1.5)),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Why this pick?
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Why this pick?',
                    style: AppTheme.sans(
                        fontSize: 12,
                        weight: FontWeight.w600,
                        color: AppTheme.textSecondary)),
                const SizedBox(height: 10),
                for (final reason in [
                  'Matches your selected mood',
                  'Highly rated by the community',
                  'Curated from top ${moodObj.genre} titles',
                ]) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_rounded,
                          size: 13, color: AppTheme.completed),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(reason,
                            style: AppTheme.sans(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                                height: 1.4)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Change the vibe'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 110, height: 160,
        color: AppTheme.surfaceLight,
        child: const Icon(Icons.movie_outlined,
            color: AppTheme.textMuted, size: 32),
      );
}

// ─────────────────────────────────────────────────────────────
// Mood Card — icon-based, no emojis
// ─────────────────────────────────────────────────────────────

class _MoodCard extends StatelessWidget {
  final IconData icon;
  final IconData watermark;
  final String label;
  final Color colorLight;
  final Color colorDark;
  final VoidCallback onTap;

  const _MoodCard({
    required this.icon,
    required this.watermark,
    required this.label,
    required this.colorLight,
    required this.colorDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colorLight, colorDark],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorLight.withValues(alpha: 0.5)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Watermark icon — large, bottom-right, very faint
              Positioned(
                right: -8, bottom: -8,
                child: Icon(watermark,
                    size: 60,
                    color: Colors.white.withValues(alpha: 0.09)),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 44, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(icon, size: 18, color: Colors.white60),
                    const SizedBox(height: 10),
                    Text(label,
                        style: AppTheme.serif(
                            fontSize: 17,
                            weight: FontWeight.w600,
                            color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────

class _Option {
  final IconData icon;
  final IconData watermark;
  final String label;
  final String sort;
  final String genre;
  final Color colorLight;
  final Color colorDark;

  const _Option(this.icon, this.watermark, this.label, this.sort, this.genre,
      this.colorLight, this.colorDark);
}
