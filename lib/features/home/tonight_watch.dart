import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/theme/app_theme.dart';
import '../../models/anime_model.dart';
import '../../services/anilist_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/hanko_cover_colour.dart';
import '../../widgets/hanko_field.dart';
import '../../widgets/hanko_print.dart';
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
            // The typographic apostrophe: Shippori draws the typewriter one
            // as a straight tick (questions 109 and 154).
            child: Text('Tonight’s watch',
                style: AppTheme.hankoSerif(height: 1.3)),
          ),
          const SizedBox(height: 6),
          // The sentence and the tile are one button, as the old card was:
          // its own semantics node (container), named by its label, with
          // the InkWell's tap and focus inside it (question 119, as
          // Profile's rows since dafb7c5). A tap given to the node over
          // excluded semantics let a screen reader press it but left out
          // the InkWell's focus, so on the web it couldn't take focus. The
          // sentence and the tile are left out of the tree, since the label
          // says them.
          Semantics(
            container: true,
            button: true,
            label: 'Choose a mood. $sentence',
            child: InkWell(
              onTap: open,
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              child: ExcludeSemantics(
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

  // ── Round nine: the moods as prints ───────────────────────────
  // Shahid, 2026-11-10: "Tonight's watch choose a mood needs better
  // visuals [...] can we make posters a bit bigger like popular this
  // season". Switched as Home's Print Room is (P2's idiom); false gives
  // 07faabe back.
  //
  // The mood picker as six boards, each holding three of its mood's own
  // covers as prints on a mat of their colour, fed by one request for all
  // six moods when the sheet opens. A pick then needs no request of its
  // own. False: the outlined tiles, and a request for each mood tapped.
  static const bool _moodBoards = true;

  // The pick as a hero print, 168 x 238 from 104 x 156, on a band of its
  // own colour, with Another pick. False: the row, and Why this pick?
  static const bool _pickOnBand = true;

  // The pick's print: Print Room's "art is the largest thing on every
  // screen", short of Detail's 208 so the reason keeps 136 dp beside it on
  // a 360 dp phone and Open stays on the first screen.
  static const double _printWidth = 168;
  static const double _printHeight = 238;

  // The pick's mood's top ten, and the rest of them in a shuffled order,
  // for Another pick (with _pickOnBand).
  List<Anime> _top = const [];
  List<Anime> _queue = [];

  // ── Every mood's top ten, from one AniList request (round nine) ──
  // The filters each mood's searchAnime sends (type, isAdult, genre,
  // sort), ten each: the ten a pick has always been drawn from. Kept in
  // memory for an hour and shared in flight; a failed refresh keeps the
  // last good ones. Nothing is saved on the device (Print Room: nothing
  // new stored from AniList).
  static Map<String, List<Anime>>? _pools;
  static Map<String, Color> _poolColours = {};
  static DateTime? _poolsAt;
  static Future<Map<String, List<Anime>>?>? _poolsFetch;
  static const _poolsTtl = Duration(hours: 1);

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
    'Funny':        'Life’s too short — laugh a little.',
    'Mind-bending': 'Leave reality at the door.',
  };

  // How each mood's board holds its covers (round nine), in cover widths
  // and degrees, as the vibe of the same name holds them on Discover
  // (round seven). Dark goes back into the dark as Deep Lore's volumes
  // do, and Funny bounces.
  static const _poses = <String, List<_Pose>>{
    // Splayed wide, mid-swing.
    'Hype': [
      _Pose(2, -0.62, 0.14, -13),
      _Pose(1, 0.02, -0.12, -2),
      _Pose(0, 0.6, 0.06, 12),
    ],
    // A slow cascade, each cover a little lower than the last.
    'Emotional': [
      _Pose(2, -0.54, -0.16, -3),
      _Pose(1, 0, 0, 2),
      _Pose(0, 0.54, 0.16, 7),
    ],
    // Huddled close.
    'Cozy': [
      _Pose(2, -0.36, 0.04, -4),
      _Pose(1, 0, -0.03, 0),
      _Pose(0, 0.36, 0.04, 4),
    ],
    // Receding, the furthest veiled most.
    'Dark': [
      _Pose(2, -0.3, -0.2, 0, scale: 0.82, veil: 0.45),
      _Pose(1, -0.04, -0.07, 0, scale: 0.91, veil: 0.22),
      _Pose(0, 0.24, 0.08, 0),
    ],
    // A bounce: the middle one hops, tilted against its neighbours.
    'Funny': [
      _Pose(2, -0.6, 0.12, -11),
      _Pose(1, 0.6, 0.1, 10),
      _Pose(0, 0, -0.14, -5),
    ],
    // Tilts that disagree.
    'Mind-bending': [
      _Pose(2, -0.5, 0.1, 10),
      _Pose(1, 0.04, -0.12, -9),
      _Pose(0, 0.55, 0.06, 14),
    ],
  };

  // A mood's sort order on its board, in the words Discover's vibes use.
  // "top rated" doesn't break.
  static const _sortWords = {
    'SCORE_DESC':      'top\u00A0rated',
    'TRENDING_DESC':   'trending',
    'POPULARITY_DESC': 'popular',
  };

  // The gap between boards, both ways.
  static const double _boardGap = 10;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
    if (_moodBoards) _loadPools();
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
      // With the boards, the mood's ten came with them or are on their
      // way, so a pick asks AniList for nothing. Without them, or when
      // that request failed, the mood asks for its own, as before.
      List<Anime>? pool;
      if (_moodBoards) {
        pool = (_pools ?? await _poolsFetch)?[moodObj.label];
        if (!mounted) return;
      }
      final results = pool != null && pool.isNotEmpty
          ? pool
          : await _anilist.searchAnime(
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
        if (_pickOnBand) {
          _top = results.take(10).toList();
          _queue = [
            for (final anime in _top)
              if (anime.id != pick.id) anime,
          ]..shuffle();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPools() async {
    final at = _poolsAt;
    if (_pools != null &&
        at != null &&
        DateTime.now().difference(at) < _poolsTtl) {
      return;
    }
    // One request at a time, shared with a mood tapped while it's on its
    // way, and with any other sheet opened meanwhile.
    final got = await (_poolsFetch ??=
        _fetchPools().whenComplete(() => _poolsFetch = null));
    if (got != null && mounted) setState(() {});
  }

  static Future<Map<String, List<Anime>>?> _fetchPools() async {
    final json = await _query({'query': _poolsQuery()});
    final data = json?['data'];
    if (data is! Map) return null;
    final pools = <String, List<Anime>>{};
    final colours = <String, Color>{};
    for (var i = 0; i < _moods.length; i++) {
      final page = data['m$i'];
      final media = page is Map && page['media'] is List
          ? page['media'] as List
          : const [];
      final pool = <Anime>[];
      for (final m in media) {
        final anime = _animeOf(m);
        if (anime == null) continue;
        pool.add(anime);
        final colour = _colourOf(m);
        if (colour != null) colours[anime.id] = colour;
      }
      pools[_moods[i].label] = pool;
    }
    if (pools.values.every((pool) => pool.isEmpty)) return null;
    _pools = pools;
    _poolColours = colours;
    _poolsAt = DateTime.now();
    return pools;
  }

  /// Every mood's top ten in one request: an aliased Page per mood, with
  /// the filters its searchAnime sends and the fields the pick shows, plus
  /// each cover's colour (AniList's own pick of it) for the mats. Detail
  /// asks for the rest when it opens (getAnimeById).
  static String _poolsQuery() {
    final pages = [
      for (var i = 0; i < _moods.length; i++)
        'm$i: Page(page: 1, perPage: 10) { media(type: ANIME, '
            'isAdult: false, genre: ${jsonEncode(_moods[i].genre)}, '
            'sort: [${_moods[i].sort}]) { id title { romaji english } '
            'coverImage { large color } averageScore episodes status '
            'seasonYear season format genres } }',
    ];
    return 'query { ${pages.join(' ')} }';
  }

  /// PulseService._query's shape: the shared throttle, a 15 s timeout, the
  /// availability signal, AniList's rate-limit headers and a backoff on a
  /// 429. Null on any failure, so the caller falls back.
  static Future<Map<String, dynamic>?> _query(
      Map<String, dynamic> body) async {
    await AnilistService.throttle();
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('https://graphql.anilist.co'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'User-Agent': 'Hanj/1.0',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      AnilistService.noteStatus(0, 'moods');
      return null;
    }
    AnilistService.noteStatus(response.statusCode, 'moods');
    AnilistService.noteLimits(response.headers);
    if (response.statusCode == 429) {
      final retryAfter =
          int.tryParse(response.headers['retry-after'] ?? '') ?? 10;
      AnilistService.backoff(retryAfter);
      return null;
    }
    if (response.statusCode != 200) return null;
    try {
      final json = jsonDecode(response.body);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  /// One show of a pool, built as searchAnime builds it, less the
  /// description and trailer the pool doesn't ask for.
  static Anime? _animeOf(Object? m) {
    if (m is! Map) return null;
    final title = m['title'] is Map ? m['title'] as Map : const {};
    final cover = m['coverImage'] is Map ? m['coverImage'] as Map : const {};
    final score = m['averageScore'];
    final genres = m['genres'];
    return Anime(
      id: '${m['id']}',
      title: title['romaji'] as String? ?? 'Unknown',
      titleEnglish: title['english'] as String?,
      imageUrl: cover['large'] as String?,
      averageScore: score is num ? score.toDouble() : null,
      episodes: m['episodes'] as int?,
      status: m['status'] as String?,
      seasonYear: m['seasonYear'] as int?,
      season: m['season'] as String?,
      format: m['format'] as String?,
      genres: genres is List ? genres.whereType<String>().toList() : const [],
    );
  }

  /// coverImage.color, AniList's own pick of the cover's main colour.
  static Color? _colourOf(Object? m) {
    final cover = m is Map ? m['coverImage'] : null;
    final hex = cover is Map ? cover['color'] : null;
    if (hex is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) {
      return null;
    }
    return Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));
  }

  void _reset() {
    _fadeCtrl.reset();
    setState(() {
      _step = 0;
      _mood = null;
      _recommendation = null;
      _reasonText = null;
      _isLoading = false;
      _top = const [];
      _queue = [];
    });
    _fadeCtrl.forward();
  }

  // Another of the mood's ten, with no request (round nine): the rest come
  // in a shuffled order, so none comes back until all have been shown.
  void _another() {
    final current = _recommendation;
    if (current == null || _top.length < 2) return;
    if (_queue.isEmpty) {
      _queue = [
        for (final anime in _top)
          if (anime.id != current.id) anime,
      ]..shuffle();
    }
    setState(() => _recommendation = _queue.removeAt(0));
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
                        child: Text('Tonight’s watch',
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
            // Round nine: with Remove animations on, a step changes at once.
            // The step's fade ran regardless before.
            child: (_moodBoards || _pickOnBand) &&
                    MediaQuery.disableAnimationsOf(context)
                ? (_step == 0 ? _buildMoodStep() : _buildResultStep())
                : FadeTransition(
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
    if (_moodBoards) return _buildBoards();
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

  // ── Step 0, round nine: the mood boards ───────────────────────
  // Six boards, two across (three where there's room for 520 dp), all on
  // the first screen of a 360 dp phone at 1.0x. Each holds three of its
  // mood's own covers, the ones a pick is drawn from, as prints posed the
  // way the vibe of the same name holds them, on a mat of the front cover's
  // colour (the field rule, so its washi words keep 5.69:1 or better).
  // Every board is as tall as the tallest one's words at the reader's text
  // size, so large text is never cut. Until the covers come, the prints are
  // empty places in their poses and the mats are sumi 3.
  Widget _buildBoards() {
    final scaler = MediaQuery.textScalerOf(context);
    final dealt = _dealt();
    return LayoutBuilder(builder: (context, constraints) {
      final room = constraints.maxWidth - 2 * AppTheme.hankoGutter;
      final columns = room >= 520 ? 3 : 2;
      final board = (room - (columns - 1) * _boardGap) / columns;
      final words = board - 2 * _MoodBoard.pad;
      final extent = _handExtent(_poses.values);
      final coverWidth = min(56.0, (words / extent.width).floorToDouble());
      double tallest(TextStyle style, String Function(_Option) text) {
        var most = 0.0;
        for (final mood in _moods) {
          final painter = TextPainter(
            text: TextSpan(text: text(mood), style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout(maxWidth: words);
          most = max(most, painter.height);
          painter.dispose();
        }
        return most;
      }

      return GridView(
        padding: const EdgeInsets.fromLTRB(
            AppTheme.hankoGutter, 0, AppTheme.hankoGutter, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: _boardGap,
          mainAxisSpacing: _boardGap,
          mainAxisExtent: _MoodBoard.heightFor(
            hand: extent.height * coverWidth,
            name: tallest(_MoodBoard.nameStyle, (m) => m.label),
            feeds: tallest(_MoodBoard.feedsStyle, _feeds),
          ),
        ),
        children: [
          for (final mood in _moods)
            _PrintButton(
              label: '${mood.label}. ${_feeds(mood)}',
              onTap: () => _pickMood(mood.label),
              builder: (context, lifted) => _MoodBoard(
                mood: mood.label,
                feeds: _feeds(mood),
                poses: _poses[mood.label] ?? const [],
                covers: dealt[mood.label] ?? const [],
                colour: _colourFor(dealt[mood.label] ?? const []),
                coverWidth: coverWidth,
                extent: extent,
                lifted: lifted,
              ),
            ),
        ],
      );
    });
  }

  // What a mood is made of, as its board says it: its genre and the order
  // AniList sorts it in. The genre's spaces don't break either, so "Slice
  // of Life, popular" wraps after the comma, never inside the genre.
  static String _feeds(_Option mood) =>
      '${mood.genre.replaceAll(' ', '\u00A0')}, '
      '${_sortWords[mood.sort] ?? mood.sort}';

  // Each board's covers: the first three of its mood's ten that no board
  // before it holds (Drama, Thriller and Mystery share top shows), so the
  // six boards show eighteen different shows. None until the request
  // answers.
  Map<String, List<Anime>> _dealt() {
    final pools = _pools;
    final out = <String, List<Anime>>{};
    if (pools == null) return out;
    final taken = <String>{};
    for (final mood in _moods) {
      final pool = pools[mood.label] ?? const <Anime>[];
      final n = (_poses[mood.label] ?? const []).length;
      final hand = [
        for (final anime in pool)
          if (!taken.contains(anime.id)) anime,
      ].take(n).toList();
      for (final anime in pool) {
        if (hand.length >= n) break;
        if (!hand.contains(anime)) hand.add(anime);
      }
      taken.addAll(hand.map((anime) => anime.id));
      out[mood.label] = hand;
    }
    return out;
  }

  // A board's mat takes its front cover's colour, or the next one's.
  static Color? _colourFor(List<Anime> covers) {
    for (final anime in covers) {
      final colour = _poolColours[anime.id];
      if (colour != null) return colour;
    }
    return null;
  }

  // What the six hands cover at rest, in cover widths around a hand's
  // centre: one for all of them, so the boards line up. A press spreads a
  // hand a little past it, into the board's padding.
  static Rect _handExtent(Iterable<List<_Pose>> hands) {
    var l = 0.0, t = 0.0, r = 0.0, b = 0.0;
    for (final hand in hands) {
      for (final p in hand) {
        final a = p.tilt.abs() * pi / 180;
        final hw = (cos(a) + _coverRatio * sin(a)) / 2 * p.scale;
        final hh = (sin(a) + _coverRatio * cos(a)) / 2 * p.scale;
        l = min(l, p.dx - hw);
        r = max(r, p.dx + hw);
        t = min(t, p.dy - hh);
        b = max(b, p.dy + hh);
      }
    }
    return Rect.fromLTRB(l, t, r, b);
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
      // The typographic apostrophe, as Home's failure line (question 154).
      return Center(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Couldn’t find a pick just now.",
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
    if (_pickOnBand) return _buildPickOnBand(anime, moodObj);
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
          // the sheet's one main action. Cover and words are one button:
          // its own semantics node with the InkWell's tap and focus inside
          // it, as the card on Home (question 119). The InkWell paints on a
          // transparent Material of its own: ink is drawn under a
          // Material's children, and the sheet's sumi 2 fill sits over the
          // bottom sheet's Material, which hid the press wash and would hide
          // the focus wash too.
          Semantics(
            container: true,
            button: true,
            label: [
              'Open $title',
              if (facts.isNotEmpty) facts,
              if (score != null) 'AniList $score',
            ].join(', '),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: openShow,
                splashFactory: NoSplash.splashFactory,
                highlightColor: AppTheme.hankoPressWash,
                hoverColor: AppTheme.hankoPressWash,
                child: ExcludeSemantics(
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

  // ── Step 1, round nine: the pick on its band ──────────────────
  // The pick as a hero print on a band of its own colour, as Home's hero
  // and watchlist band have theirs (Print Room): the mood and the reason
  // beside the print, the band faded in from the sheet and out at the
  // print's foot, so the title and its facts sit on the sheet's sumi 2,
  // where stone and ai keep their contrast. The print is 168 x 238, from
  // 104 x 156, with the large shadow and the 460 px cover (a hero's). One
  // button for the show, as before, with Open drawn at its foot; Another
  // pick and Change the vibe are buttons of their own under it.
  Widget _buildPickOnBand(Anime anime, _Option moodObj) {
    final title = anime.titleEnglish ?? anime.title;
    final facts = anime.genres.take(2).join(' · ');
    final score = anime.averageScore == null
        ? null
        : (anime.averageScore! / 10).toStringAsFixed(1);
    final line = _poolLine(moodObj, _top.length);
    final still = MediaQuery.disableAnimationsOf(context);
    void openShow() {
      Navigator.pop(context);
      Navigator.push(context,
          MaterialPageRoute(
              builder: (_) => AnimeDetailScreen(anime: anime)));
    }

    final quiet = AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize,
        color: AppTheme.hankoStone,
        height: 1.4);
    // Everything on the band is washi, as on every field.
    final band = _ShowColour(
      colour: _poolColours[anime.id],
      url: anime.imageUrl,
      builder: (context, colour) => HankoField(
        colour: colour,
        solidTo: 0.75,
        child: Stack(
          children: [
            // A pool of the colour behind the print, where no text sits.
            Positioned(
              top: 4,
              right: AppTheme.hankoGutter - 48,
              width: _printWidth + 96,
              height: _printHeight + 48,
              child: IgnorePointer(child: _PickGlow(colour: colour)),
            ),
            // The band fades in from the sheet, as Home's from the page.
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              height: 40,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppTheme.hankoSumi2,
                        AppTheme.hankoSumi2.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppTheme.hankoGutter, 28, AppTheme.hankoGutter, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(moodObj.icon,
                                size: 16, color: AppTheme.hankoWashi),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(moodObj.label,
                                  style: AppTheme.hankoSans(
                                      fontSize: AppTheme.hankoMetaSize,
                                      weight: FontWeight.w500,
                                      height: 1.3)),
                            ),
                          ],
                        ),
                        // The reason is Hanj speaking, in the voice's face.
                        if (_reasonText != null) ...[
                          const SizedBox(height: 10),
                          Text(_reasonText!,
                              style: AppTheme.hankoSerif(
                                  fontSize: AppTheme.hankoFeaturedSize,
                                  height: 1.3)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Another pick swaps the print in a short crossfade.
                  AnimatedSwitcher(
                    duration: still
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    child: HankoPrint(
                      key: ValueKey(anime.id),
                      url: anime.imageUrl,
                      width: _printWidth,
                      height: _printHeight,
                      lift: HankoPrintLift.large,
                      sharp: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final words = Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 4, AppTheme.hankoGutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The whole title: the sheet scrolls, so it's never cut.
          Text(title,
              style: AppTheme.hankoSerif(
                  fontSize: AppTheme.hankoDisplaySize, height: 1.2)),
          if (facts.isNotEmpty || score != null) ...[
            const SizedBox(height: 8),
            // The crowd's score in indigo, so it never reads as yours.
            Text.rich(
              TextSpan(
                style: quiet,
                children: [
                  TextSpan(text: facts),
                  if (score != null) ...[
                    TextSpan(text: facts.isEmpty ? 'AniList ' : ' · AniList '),
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
                ],
              ),
            ),
          ],
          if (line != null) ...[
            const SizedBox(height: 4),
            Text(line, style: quiet),
          ],
          const SizedBox(height: 18),
          const _HankoTile(label: 'Open', main: true, expand: true),
        ],
      ),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PrintButton(
            label: [
              'Open $title',
              if (facts.isNotEmpty) facts,
              if (score != null) 'AniList $score',
            ].join(', '),
            onTap: openShow,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [band, words],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppTheme.hankoGutter),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (_top.length > 1)
                  _HankoTile(label: 'Another pick', onTap: _another),
                _HankoTile(label: 'Change the vibe', onTap: _reset),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Where the pick is from, in one line, in place of Why this pick?'s
  // three checks, one of which ("Highly rated by the community") wasn't
  // true of the moods AniList sorts by popularity or trend. [n] is how
  // many the pick was drawn from.
  static String? _poolLine(_Option mood, int n) {
    if (n < 2) return null;
    final count = n <= 10 ? _counts[n - 2] : '$n';
    return switch (mood.sort) {
      'SCORE_DESC' => 'One of AniList’s $count best-rated ${mood.genre} titles.',
      'POPULARITY_DESC' =>
        'One of AniList’s $count most popular ${mood.genre} titles.',
      _ => 'One of $count ${mood.genre} titles trending on AniList.',
    };
  }

  static const _counts = [
    'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten',
  ];
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
// Mood boards — the moods as prints (round nine)
// ─────────────────────────────────────────────────────────────

// AniList's covers are 230 × 326.
const _coverRatio = 326 / 230;

/// One print in a mood's hand, as Discover's vibes hold theirs: [cover] is
/// which of the board's covers it shows (0 is AniList's first); [dx] and
/// [dy] place its centre from the hand's centre in cover widths, so a hand
/// keeps its shape at any size; [tilt] is in degrees; [scale] sizes it; and
/// [veil] (0–1) is a sumi veil for a print that recedes. A hand is drawn in
/// order, so the last print is nearest.
class _Pose {
  final int cover;
  final double dx;
  final double dy;
  final double tilt;
  final double scale;
  final double veil;

  const _Pose(this.cover, this.dx, this.dy, this.tilt,
      {this.scale = 1, this.veil = 0});
}

/// A button over art (round nine): CLAUDE.md's pattern, its own semantics
/// node named by [label] with the InkWell's tap and focus inside it and the
/// face left out of the tree. The press and hover wash is drawn over the
/// face, since an InkWell's own would lie under its art and its mat, and
/// keyboard focus draws a 2 px washi ring inside the edge. [builder] is
/// told when the button is lifted: pressed, hovered or focused.
class _PrintButton extends StatefulWidget {
  const _PrintButton({
    required this.label,
    required this.onTap,
    required this.builder,
  });

  final String label;
  final VoidCallback onTap;
  final Widget Function(BuildContext context, bool lifted) builder;

  @override
  State<_PrintButton> createState() => _PrintButtonState();
}

class _PrintButtonState extends State<_PrintButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: widget.label,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        onHover: (v) => setState(() => _hovered = v),
        onFocusChange: (v) => setState(() => _focused = v),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: ExcludeSemantics(
          child: Stack(
            children: [
              widget.builder(context, _pressed || _hovered || _focused),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _pressed || _hovered
                          ? AppTheme.hankoPressWash
                          : null,
                      border: _focused
                          ? Border.all(color: AppTheme.hankoWashi, width: 2)
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A mood as a board (round nine): its hand of covers on a mat of the front
/// cover's colour, the mood in Shippori and what feeds it in Jost, all
/// washi, as everything on a field is. Without a colour (or before the
/// covers come), the mat is sumi 3.
class _MoodBoard extends StatelessWidget {
  const _MoodBoard({
    required this.mood,
    required this.feeds,
    required this.poses,
    required this.covers,
    required this.colour,
    required this.coverWidth,
    required this.extent,
    required this.lifted,
  });

  final String mood;
  final String feeds;
  final List<_Pose> poses;
  final List<Anime> covers;
  final Color? colour;
  final double coverWidth;
  final Rect extent;
  final bool lifted;

  /// The board's padding at its sides.
  static const double pad = 10;

  static TextStyle get nameStyle => AppTheme.hankoSerif(
      fontSize: AppTheme.hankoFeaturedSize, height: 1.2);

  static TextStyle get feedsStyle =>
      AppTheme.hankoSans(fontSize: AppTheme.hankoLabelSize, height: 1.3);

  /// The board's height for a hand and its words' heights; 2 dp spare,
  /// since a measured line and a laid-out one can differ by a fraction.
  static double heightFor({
    required double hand,
    required double name,
    required double feeds,
  }) =>
      14 + hand + 10 + name + 2 + feeds + 12 + 2;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: still ? Duration.zero : const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        color: AppTheme.hankoField(colour) ?? AppTheme.hankoSumi3,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(pad, 14, pad, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: _MoodHand(
                poses: poses,
                covers: covers,
                coverWidth: coverWidth,
                extent: extent,
                lifted: lifted && !still,
              ),
            ),
            const SizedBox(height: 10),
            Text(mood, style: nameStyle),
            const SizedBox(height: 2),
            Text(feeds, style: feedsStyle),
          ],
        ),
      ),
    );
  }
}

/// A mood's covers in its pose (round nine), each a print with its small
/// shadow, on the hairline's tone while it loads. Lifted (pressed, hovered
/// or focused), the hand spreads a little, as a vibe's does: the covers
/// move out, tilt further and rise. It only repaints itself.
class _MoodHand extends StatelessWidget {
  const _MoodHand({
    required this.poses,
    required this.covers,
    required this.coverWidth,
    required this.extent,
    required this.lifted,
  });

  final List<_Pose> poses;
  final List<Anime> covers;
  final double coverWidth;
  // What the hands cover at rest around their centre, in cover widths.
  final Rect extent;
  final bool lifted;

  static const _spreadDx = 0.14;
  static const _spreadTilt = 0.35;
  static const _spreadLift = 0.05;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: extent.width * coverWidth,
        height: extent.height * coverWidth,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: lifted ? 1 : 0),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          builder: (context, lift, _) => Stack(
            clipBehavior: Clip.none,
            children: [for (final p in poses) _placed(p, lift)],
          ),
        ),
      ),
    );
  }

  Widget _placed(_Pose p, double lift) {
    final w = coverWidth;
    final h = w * _coverRatio;
    final dx = p.dx * (1 + _spreadDx * lift) * w;
    final dy = (p.dy - _spreadLift * lift) * w;
    final tilt = p.tilt * (1 + _spreadTilt * lift);
    final cover = p.cover < covers.length ? covers[p.cover] : null;
    return Positioned(
      left: -extent.left * w - w / 2 + dx,
      top: -extent.top * w - h / 2 + dy,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: tilt * pi / 180,
        child: Transform.scale(
          scale: p.scale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              HankoPrint(
                url: cover?.imageUrl,
                width: w,
                height: h,
                placeholder: AppTheme.hankoHairline,
              ),
              if (p.veil > 0)
                ColoredBox(
                    color: AppTheme.hankoSumi.withValues(alpha: p.veil)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pick's colour, for its band and its glow (round nine): AniList's
/// own (coverImage.color) when the boards' request brought it, else read
/// from the cover itself by HankoCoverColour, as Home's prints are (no
/// request, nothing stored). Null until it's read, and for a grey cover,
/// so the band stays the sheet's sumi 2.
class _ShowColour extends StatefulWidget {
  const _ShowColour({
    required this.colour,
    required this.url,
    required this.builder,
  });

  final Color? colour;
  final String? url;
  final Widget Function(BuildContext context, Color? colour) builder;

  @override
  State<_ShowColour> createState() => _ShowColourState();
}

class _ShowColourState extends State<_ShowColour> {
  Color? _read;

  @override
  void initState() {
    super.initState();
    _readCover();
  }

  @override
  void didUpdateWidget(_ShowColour oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.colour != widget.colour) {
      _readCover();
    }
  }

  void _readCover() {
    final url = widget.url;
    if (widget.colour != null || url == null || url.isEmpty) {
      _read = null;
      return;
    }
    if (HankoCoverColour.knows(url)) {
      _read = HankoCoverColour.peek(url);
      return;
    }
    _read = null;
    // HankoCoverColour never throws, so nothing here can reach Crashlytics.
    HankoCoverColour.ofUrl(url).then((colour) {
      if (!mounted || widget.url != url || widget.colour != null) return;
      setState(() => _read = colour);
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.colour ?? _read);
}

/// A pool of the pick's colour behind its print (round nine), as Home's
/// hero has one: the field rule's glow, lighter than the band, where no
/// text sits. It crossfades with the band, at once with Remove animations.
class _PickGlow extends StatelessWidget {
  const _PickGlow({required this.colour});

  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final glow = AppTheme.hankoField(colour,
        cap: AppTheme.hankoFieldGlowCap, mix: AppTheme.hankoFieldGlowMix);
    final clear = (glow ?? AppTheme.hankoSumi2).withValues(alpha: 0);
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      decoration: BoxDecoration(
        gradient: RadialGradient(colors: [glow ?? clear, clear]),
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
