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
    // Hanko (stage H4, item h): a Home section like the others, a Shippori
    // heading over a sentence and an outlined tile, instead of a coral
    // gradient card with a coral border, a coral icon disc and a coral pill.
    // In Hanko coral is your seal, so nothing here is coral. The time of day
    // moves from a tracked eyebrow ("LATE NIGHT") into the sentence, and its
    // icon onto the tile.
    final hour = DateTime.now().hour;
    final when = hour < 12
        ? 'this morning'
        : hour < 17
            ? 'this afternoon'
            : hour < 21
                ? 'this evening'
                : 'tonight';
    final icon = hour >= 20 || hour < 6
        ? Icons.nightlight_sharp
        : hour < 12
            ? Icons.wb_sunny_sharp
            : Icons.wb_twilight_sharp;
    final sentence = 'One show for $when, picked for your mood.';

    void open() => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const TonightWatchSheet(),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text("Tonight's watch",
                style: AppTheme.hankoSerif(height: 1.3)),
          ),
          const SizedBox(height: 6),
          // The sentence and the tile are one button, as the old card was.
          // excludeSemantics drops the InkWell's own tap action with the
          // rest of the subtree, so the node carries onTap itself.
          Semantics(
            button: true,
            label: 'Choose a mood. $sentence',
            onTap: open,
            excludeSemantics: true,
            child: InkWell(
              onTap: open,
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sentence,
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize,
                        color: AppTheme.hankoStone,
                        height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  _HankoTile(label: 'Choose a mood', icon: icon),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hanko's tile (hanko.html .tile): 48 dp tall, square 2 px corners, Jost 600
/// 15. Outlined, sumi 3 with a 1 px edge outline (4.02:1), for a secondary
/// action; [main] fills it washi with a sumi label, for a screen's one main
/// action. Without [onTap] it is drawn only, as part of a larger button.
class _HankoTile extends StatelessWidget {
  const _HankoTile({
    required this.label,
    this.icon,
    this.onTap,
    this.main = false,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool main;
  final bool expand;

  // The press on a washi tile: sumi at 10%, as washi at 8% is on sumi.
  static const _sumiWash = Color(0x1A121110);

  @override
  Widget build(BuildContext context) {
    final ink = main ? AppTheme.hankoSumi : AppTheme.hankoWashi;
    final radius = BorderRadius.circular(AppTheme.hankoRadius);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(
          minHeight: AppTheme.hankoTouch, minWidth: AppTheme.hankoTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: ink),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppTheme.hankoSans(
                    fontSize: 15,
                    weight: FontWeight.w600,
                    color: ink,
                    height: 1.2),
              ),
            ),
          ],
        ),
      ),
    );
    final decoration = ShapeDecoration(
      color: main ? AppTheme.hankoWashi : AppTheme.hankoSumi3,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: main
            ? BorderSide.none
            : const BorderSide(color: AppTheme.hankoEdge),
      ),
    );
    if (onTap == null) {
      return DecoratedBox(decoration: decoration, child: content);
    }
    return Semantics(
      button: true,
      child: Material(
        color: decoration.color,
        shape: decoration.shape,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: main ? _sumiWash : AppTheme.hankoPressWash,
          hoverColor: main ? _sumiWash : AppTheme.hankoPressWash,
          borderRadius: radius,
          child: content,
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
  // Hanko draws the sharp icons and none of the mood colours (stage H4,
  // item h): six accent colours would be decoration. The colours and the
  // watermark icons stay here, undrawn, as a record of the old cards. Dark
  // takes its own watermark's moon behind a cloud: the sharp set has no
  // outlined crescent, and two filled crescents read as the same mood.
  static const _moods = [
    _Option(Icons.bolt_sharp,             Icons.flash_on_rounded,
        'Hype',         'TRENDING_DESC',   'Action',
        Color(0xFF8B1A0A), Color(0xFF1A0603)),
    _Option(Icons.water_drop_sharp,       Icons.opacity_rounded,
        'Emotional',    'SCORE_DESC',      'Drama',
        Color(0xFF1A3A6B), Color(0xFF060D1A)),
    _Option(Icons.nightlight_sharp,       Icons.bedtime_outlined,
        'Cozy',         'POPULARITY_DESC', 'Slice of Life',
        Color(0xFF3A2A6B), Color(0xFF0C091A)),
    _Option(Icons.nights_stay_sharp,      Icons.nights_stay_rounded,
        'Dark',         'SCORE_DESC',      'Thriller',
        Color(0xFF1C1C1C), Color(0xFF080808)),
    _Option(Icons.theater_comedy_sharp,   Icons.sentiment_satisfied_alt_outlined,
        'Funny',        'POPULARITY_DESC', 'Comedy',
        Color(0xFF6B4A10), Color(0xFF1A1106)),
    _Option(Icons.hub_sharp,              Icons.all_inclusive_rounded,
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
      if (!mounted) return;

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
      if (!mounted) return;
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
    // Hanko (stage H4, item h; hanko.html's sheet): sumi 2 with 6 px top
    // corners and an edge grab, a Shippori title, and Hanko's tiles. The
    // steps, the data and where each tap goes are as they were.
    return Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: const BoxDecoration(
        color: AppTheme.hankoSumi2,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.hankoSheetRadius)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          // Handle
          Container(
            width: 32, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.hankoEdge.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text("Tonight's watch",
                            style: AppTheme.hankoSerif(
                                fontSize: AppTheme.hankoLedeSize,
                                height: 1.2)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _step == 0 ? 'What pulls you tonight?' : 'Curated for your mood',
                        style: AppTheme.hankoSans(
                            fontSize: AppTheme.hankoMetaSize,
                            color: AppTheme.hankoStone,
                            height: 1.3),
                      ),
                    ],
                  ),
                ),
                if (_step == 1) ...[
                  const SizedBox(width: 12),
                  _HankoTile(label: 'Reset', onTap: _reset),
                ],
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
    // Six outlined tiles, two across, each tall enough for its label on two
    // lines at the reader's text size, so large text never overflows a tile.
    final extent = max(
        64.0, MediaQuery.textScalerOf(context).scale(15) * 1.25 * 2 + 28);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
      child: GridView(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: extent,
        ),
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
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  color: AppTheme.hankoWashi, strokeWidth: 1.5),
            ),
            const SizedBox(height: 16),
            Text('Finding your perfect watch...',
                style: AppTheme.hankoSans(color: AppTheme.hankoStone)),
          ],
        ),
      );
    }

    if (_recommendation == null) {
      // An empty answer and a failed request land here alike, so the copy
      // names no cause it can't verify (ANILIST-OFFLINE-0908-REPORT.md).
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Couldn't find a pick just now.",
                  textAlign: TextAlign.center,
                  style: AppTheme.hankoSerif(
                      fontSize: AppTheme.hankoFeaturedSize, height: 1.3)),
              const SizedBox(height: 16),
              _HankoTile(label: 'Try again', onTap: _reset),
            ],
          ),
        ),
      );
    }

    final anime   = _recommendation!;
    final moodObj = _moods.firstWhere((m) => m.label == _mood,
        orElse: () => _moods.first);
    final title = anime.titleEnglish ?? anime.title;
    final facts = anime.genres.take(2).join(' · ');
    final score = anime.averageScore == null
        ? null
        : (anime.averageScore! / 10).toStringAsFixed(1);
    void openShow() {
      Navigator.pop(context);
      Navigator.push(context,
          MaterialPageRoute(
              builder: (_) => AnimeDetailScreen(anime: anime)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The mood, as a label rather than a chip: it isn't a control.
          Row(
            children: [
              Icon(moodObj.icon, size: 16, color: AppTheme.hankoStone),
              const SizedBox(width: 8),
              Flexible(
                child: Text(moodObj.label,
                    style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize,
                        weight: FontWeight.w500,
                        color: AppTheme.hankoStone)),
              ),
            ],
          ),
          // The reason is Hanj speaking, so it is set in the voice's face.
          if (_reasonText != null) ...[
            const SizedBox(height: 8),
            Text(_reasonText!,
                style: AppTheme.hankoSerif(height: 1.4)),
          ],
          const SizedBox(height: 20),

          // The pick: the cover, the whole title (the sheet scrolls, so it
          // is never cut), the facts, the crowd's score in indigo, and Open,
          // the sheet's one main action. Cover and words are one button.
          Semantics(
            button: true,
            label: [
              'Open $title',
              if (facts.isNotEmpty) facts,
              if (score != null) 'AniList $score',
            ].join(', '),
            onTap: openShow,
            excludeSemantics: true,
            child: InkWell(
              onTap: openShow,
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius:
                        BorderRadius.circular(AppTheme.hankoRadius),
                    child: anime.imageUrl != null
                        ? Image.network(anime.imageUrl!,
                            width: 104, height: 156,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder())
                        : _placeholder(),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTheme.hankoSerif(
                              fontSize: AppTheme.hankoFeaturedSize,
                              height: 1.15),
                        ),
                        if (facts.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            facts,
                            style: AppTheme.hankoSans(
                                fontSize: AppTheme.hankoMetaSize,
                                color: AppTheme.hankoStone,
                                height: 1.4),
                          ),
                        ],
                        if (score != null) ...[
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(
                              text: 'AniList ',
                              style: AppTheme.hankoSans(
                                  fontSize: AppTheme.hankoMetaSize,
                                  color: AppTheme.hankoStone,
                                  height: 1.4),
                              children: [
                                TextSpan(
                                  text: score,
                                  style: AppTheme.hankoSans(
                                    fontSize: AppTheme.hankoMetaSize,
                                    weight: FontWeight.w500,
                                    color: AppTheme.hankoAi,
                                    height: 1.4,
                                    tabular: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        const _HankoTile(label: 'Open', main: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Why this pick? Plain lines with stone checks: no boxes, and no
          // green, which would read as a status.
          Text('Why this pick?',
              style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoMetaSize,
                  weight: FontWeight.w500)),
          const SizedBox(height: 8),
          for (final reason in [
            'Matches your selected mood',
            'Highly rated by the community',
            'Curated from top ${moodObj.genre} titles',
          ]) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_sharp,
                      size: 14, color: AppTheme.hankoStone),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(reason,
                      style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoMetaSize,
                          color: AppTheme.hankoStone,
                          height: 1.4)),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],

          const SizedBox(height: 18),

          _HankoTile(
            label: 'Change the vibe',
            icon: Icons.refresh_sharp,
            onTap: _reset,
            expand: true,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Missing art stays an empty sumi 3 print, never a stand-in picture.
  Widget _placeholder() => const SizedBox(
        width: 104, height: 156,
        child: ColoredBox(color: AppTheme.hankoSumi3),
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
    // Hanko (stage H4, item h): an outlined tile, sumi 3 with a 1 px edge
    // outline and 2 px corners, the sharp icon in stone and the mood in Jost
    // 500 washi. The gradient, its border and the watermark were the mood's
    // colours; Hanko doesn't draw them, so colorLight, colorDark and
    // watermark are kept but unused.
    final radius = BorderRadius.circular(AppTheme.hankoRadius);
    return Semantics(
      button: true,
      child: Material(
        color: AppTheme.hankoSumi3,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: const BorderSide(color: AppTheme.hankoEdge),
        ),
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.hankoStone),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.hankoSans(
                          fontSize: 15,
                          weight: FontWeight.w500,
                          height: 1.25)),
                ),
              ],
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
