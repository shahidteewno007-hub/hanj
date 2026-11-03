import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../models/anime_model.dart';
import '../../services/anilist_service.dart';
import '../anime_detail/anime_detail_screen.dart';

// ─────────────────────────────────────────────────────────────
// Category data model — icon-based, no emojis
// ─────────────────────────────────────────────────────────────

class _Category {
  final IconData icon;
  final String name;
  final String tagline;
  final String genre;
  final String sort;
  final Color color;
  final Color bgColor;
  final bool isHiddenGems;

  const _Category({
    required this.icon,
    required this.name,
    required this.tagline,
    required this.genre,
    required this.sort,
    required this.color,
    required this.bgColor,
    this.isHiddenGems = false,
  });
}

const _categories = [
  // ── Hidden Gems — featured at top ──────────────────────────
  _Category(
    icon: Icons.diamond_outlined,
    name: 'Hidden Gems',
    tagline: 'Highly rated, rarely discussed',
    genre: 'Psychological',
    sort: 'SCORE_DESC',
    color: Color(0xFF818CF8),
    bgColor: Color(0xFF0C0A1E),
    isHiddenGems: true,
  ),
  // ── Core vibes ─────────────────────────────────────────────
  _Category(
    icon: Icons.bolt_rounded,
    name: 'Hype Machine',
    tagline: 'Gets the blood pumping',
    genre: 'Action',
    sort: 'TRENDING_DESC',
    color: Color(0xFFF97316),
    bgColor: Color(0xFF1E0A03),
  ),
  _Category(
    icon: Icons.water_drop_outlined,
    name: 'Emotional Journey',
    tagline: 'Feels that stay with you',
    genre: 'Drama',
    sort: 'SCORE_DESC',
    color: Color(0xFF60A5FA),
    bgColor: Color(0xFF060E1A),
  ),
  _Category(
    icon: Icons.hub_outlined,
    name: 'Mind-Bending',
    tagline: 'You won\'t see it coming',
    genre: 'Mystery',
    sort: 'SCORE_DESC',
    color: Color(0xFF818CF8),
    bgColor: Color(0xFF0C0A1E),
  ),
  _Category(
    icon: Icons.nightlight_round,
    name: 'Cozy Night',
    tagline: 'Slow down and stay awhile',
    genre: 'Slice of Life',
    sort: 'POPULARITY_DESC',
    color: Color(0xFFD4A96A),
    bgColor: Color(0xFF1A1004),
  ),
  _Category(
    icon: Icons.people_outline_rounded,
    name: 'Found Family',
    tagline: 'They chose each other',
    genre: 'Adventure',
    sort: 'SCORE_DESC',
    color: Color(0xFF34D399),
    bgColor: Color(0xFF041A0E),
  ),
  _Category(
    icon: Icons.bedtime_outlined,
    name: 'Tragic Masterpieces',
    tagline: 'Not every story needs light',
    genre: 'Horror',
    sort: 'SCORE_DESC',
    color: Color(0xFFF87171),
    bgColor: Color(0xFF1A0608),
  ),
  _Category(
    icon: Icons.auto_awesome_outlined,
    name: 'Peak Fiction',
    tagline: 'Certified masterpieces only',
    genre: 'Supernatural',
    sort: 'SCORE_DESC',
    color: Color(0xFFF97316),
    bgColor: Color(0xFF1A0A03),
  ),
  _Category(
    icon: Icons.explore_outlined,
    name: 'Deep Lore',
    tagline: 'Entire wikis exist for these',
    genre: 'Sci-Fi',
    sort: 'SCORE_DESC',
    color: Color(0xFF22D3EE),
    bgColor: Color(0xFF031418),
  ),
];

// ─────────────────────────────────────────────────────────────
// Moods — how each vibe holds its covers (round seven)
// ─────────────────────────────────────────────────────────────
// Since round seven a vibe is told apart by its own covers and by the way it
// holds them, not by a hue of its own: the seven hues above (color, bgColor)
// and the icons are kept as data but no longer drawn. Hanko's palette leaves
// colour to the art, and the board's tint comes from the covers themselves.

/// One cover in a vibe's hand. [cover] is which of the vibe's covers it
/// shows (0 is AniList's first); [dx] and [dy] place its centre from the
/// hand's centre in cover widths, so a hand keeps its shape at any size;
/// [tilt] is in degrees; [veil] (0–1) is a sumi veil for covers that
/// recede. A hand is drawn in list order, so the last card is nearest.
class _Card {
  final int cover;
  final double dx;
  final double dy;
  final double tilt;
  final double scale;
  final double veil;

  const _Card(this.cover, this.dx, this.dy, this.tilt,
      {this.scale = 1, this.veil = 0});
}

const _defaultHand = [
  _Card(2, -0.55, 0.08, -9),
  _Card(1, 0, -0.1, 0),
  _Card(0, 0.55, 0.08, 9),
];

const _moods = <String, List<_Card>>{
  // The featured spread: five in an arc, AniList's first nearest.
  'Hidden Gems': [
    _Card(4, -1.3, 0.24, -14),
    _Card(3, 1.3, 0.24, 14),
    _Card(2, -0.66, 0.06, -7),
    _Card(1, 0.66, 0.06, 7),
    _Card(0, 0, 0, 0),
  ],
  // Splayed wide, mid-swing.
  'Hype Machine': [
    _Card(2, -0.62, 0.14, -13),
    _Card(1, 0.02, -0.12, -2),
    _Card(0, 0.6, 0.06, 12),
  ],
  // A slow cascade, each cover a little lower than the last.
  'Emotional Journey': [
    _Card(2, -0.54, -0.16, -3),
    _Card(1, 0, 0, 2),
    _Card(0, 0.54, 0.16, 7),
  ],
  // Tilts that disagree.
  'Mind-Bending': [
    _Card(2, -0.5, 0.1, 10),
    _Card(1, 0.04, -0.12, -9),
    _Card(0, 0.55, 0.06, 14),
  ],
  // Huddled close.
  'Cozy Night': [
    _Card(2, -0.36, 0.04, -4),
    _Card(1, 0, -0.03, 0),
    _Card(0, 0.36, 0.04, 4),
  ],
  // Upright, shoulder to shoulder.
  'Found Family': [
    _Card(2, -0.64, 0, 0),
    _Card(1, 0, 0, 0),
    _Card(0, 0.64, 0, 0),
  ],
  // Falling away to one side, the nearest still standing.
  'Tragic Masterpieces': [
    _Card(2, -0.52, 0.16, -16, veil: 0.4),
    _Card(1, -0.06, 0.06, -8, veil: 0.2),
    _Card(0, 0.5, 0, 0),
  ],
  // A podium: the middle one raised, larger and nearest.
  'Peak Fiction': [
    _Card(1, -0.62, 0.14, -5, scale: 0.9),
    _Card(2, 0.62, 0.14, 5, scale: 0.9),
    _Card(0, 0, -0.1, 0, scale: 1.08),
  ],
  // Volumes going back into the dark.
  'Deep Lore': [
    _Card(2, -0.4, -0.22, 0, scale: 0.82, veil: 0.45),
    _Card(1, -0.14, -0.09, 0, scale: 0.91, veil: 0.22),
    _Card(0, 0.14, 0.06, 0),
  ],
};

List<_Card> _handOf(_Category c) => _moods[c.name] ?? _defaultHand;

// A vibe's sort order on its label, in the words Discover's tabs use.
const _sortWords = {
  'SCORE_DESC': 'Top rated',
  'TRENDING_DESC': 'Trending',
  'POPULARITY_DESC': 'Popular',
};

// AniList's covers are 230 × 326.
const _coverRatio = 326 / 230;

// A press or a hover spreads a hand: covers move out and tilt further.
const _spreadDx = 0.14;
const _spreadTilt = 0.35;
const _spreadLift = 0.05;

/// What a hand covers at full spread, in cover widths, around the hand's
/// centre: the hands of a layout share one, so their boards line up.
Rect _handExtent(Iterable<List<_Card>> hands) {
  var l = 0.0, t = 0.0, r = 0.0, b = 0.0;
  for (final hand in hands) {
    for (final c in hand) {
      final a = (c.tilt * (1 + _spreadTilt)).abs() * math.pi / 180;
      final hw = (math.cos(a) + _coverRatio * math.sin(a)) / 2 * c.scale;
      final hh = (math.sin(a) + _coverRatio * math.cos(a)) / 2 * c.scale;
      final x = c.dx * (1 + _spreadDx);
      l = math.min(l, x - hw);
      r = math.max(r, x + hw);
      t = math.min(t, c.dy - _spreadLift - hh);
      b = math.max(b, c.dy + hh);
    }
  }
  return Rect.fromLTRB(l, t, r, b);
}

// ─────────────────────────────────────────────────────────────
// Covers — one request for every vibe's hand (round seven)
// ─────────────────────────────────────────────────────────────

class _Cover {
  final int id;
  final String url;
  final String? hex;

  const _Cover(this.id, this.url, this.hex);

  /// coverImage.color, AniList's own pick of the cover's main colour.
  Color? get color {
    final h = hex;
    if (h == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(h)) return null;
    return Color(0xFF000000 | int.parse(h.substring(1), radix: 16));
  }

  Map<String, dynamic> toJson() => {'id': id, 'url': url, 'hex': hex};

  static _Cover? fromJson(Object? m) {
    if (m is! Map) return null;
    final url = m['url'];
    if (url is! String || url.isEmpty) return null;
    return _Cover(m['id'] is int ? m['id'] as int : 0, url, m['hex'] as String?);
  }
}

/// The tint a board takes from its covers: the first cover whose colour
/// isn't within Hanko's hue guard of the seal (AppTheme.hankoCoverTint), so
/// no board reads as coral, which is only ever yours. Null: plain sumi.
Color? _tintOf(List<_Cover> covers) {
  for (final c in covers) {
    final color = c.color;
    if (AppTheme.hankoCoverTint(color) != null) return color;
  }
  return null;
}

// ─────────────────────────────────────────────────────────────
// Main Tab Widget
// ─────────────────────────────────────────────────────────────

class EmotionalCategoriesTab extends StatefulWidget {
  const EmotionalCategoriesTab({super.key});

  @override
  State<EmotionalCategoriesTab> createState() => _EmotionalCategoriesTabState();
}

class _EmotionalCategoriesTabState extends State<EmotionalCategoriesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // ── Every vibe's covers, from one AniList request ──────────
  // Memory (survives tab switches) → SharedPreferences (1 h) → network,
  // with the saved copy as the stale fallback, the shape of
  // OfflineCacheService. A board without covers still opens: its row
  // fetches its own list on a tap, as before.
  static Map<String, List<_Cover>>? _coverCache;
  static DateTime? _coverCacheAt;
  static Future<(Map<String, List<_Cover>>, bool)?>? _coverFetch;
  static const _coversKey = 'cache_vibe_covers_v1';
  static const _coversTtl = Duration(hours: 1);

  Map<String, List<_Cover>> _covers = const {};

  @override
  void initState() {
    super.initState();
    final cached = _coverCache;
    if (cached != null) _covers = cached;
    _loadCovers();
  }

  Future<void> _loadCovers() async {
    final at = _coverCacheAt;
    if (_coverCache != null &&
        at != null &&
        DateTime.now().difference(at) < _coversTtl) {
      return;
    }
    // One request at a time, shared by every Discover on the stack.
    final got = await (_coverFetch ??=
        _fetchCovers().whenComplete(() => _coverFetch = null));
    if (got == null) return;
    final (covers, fresh) = got;
    _coverCache = covers;
    // Saved covers stand in after a failure but don't count as fresh, so
    // the next visit asks AniList again.
    if (fresh) _coverCacheAt = DateTime.now();
    if (mounted) setState(() => _covers = covers);
  }

  static Future<(Map<String, List<_Cover>>, bool)?> _fetchCovers() async {
    SharedPreferences? prefs;
    Map<String, List<_Cover>>? saved;
    int? savedAt;
    try {
      prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_coversKey);
      savedAt = prefs.getInt('${_coversKey}_ts');
      if (raw != null) saved = _decodeCovers(raw);
    } catch (_) {}
    if (saved != null &&
        savedAt != null &&
        DateTime.now().millisecondsSinceEpoch - savedAt <
            _coversTtl.inMilliseconds) {
      return (saved, true);
    }

    final data = await _query({'query': _coversQuery()});
    final fetched = data == null ? null : _parseCovers(data);
    if (fetched != null && fetched.values.any((l) => l.isNotEmpty)) {
      try {
        await prefs?.setString(
            _coversKey,
            jsonEncode(fetched.map((k, v) =>
                MapEntry(k, v.map((c) => c.toJson()).toList()))));
        await prefs?.setInt(
            '${_coversKey}_ts', DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
      return (fetched, true);
    }
    // Stale fallback: the last covers that loaded beat empty hands.
    return saved == null ? null : (saved, false);
  }

  /// Every vibe's first few covers in one request: one aliased Page per
  /// vibe, with the same filters its row sends through searchAnime (type,
  /// isAdult, genre, sort), so a hand shows shows from the top of its own
  /// list. A few spares each let _parseCovers deal a cover to one hand only.
  static String _coversQuery() {
    final pages = [
      for (var i = 0; i < _categories.length; i++)
        'v$i: Page(page: 1, perPage: ${_categories[i].isHiddenGems ? 10 : 6}) '
            '{ media(type: ANIME, isAdult: false, '
            'genre: ${jsonEncode(_categories[i].genre)}, '
            'sort: [${_categories[i].sort}]) '
            '{ id averageScore coverImage { large color } } }',
    ];
    return 'query { ${pages.join(' ')} }';
  }

  static Map<String, List<_Cover>>? _parseCovers(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! Map) return null;
    final out = <String, List<_Cover>>{};
    // Genres overlap, so the same top shows head several lists. Each cover
    // goes to the first hand that has it; later hands take their spares,
    // and only repeat a cover when they run out.
    final dealt = <int>{};
    for (var i = 0; i < _categories.length; i++) {
      final cat = _categories[i];
      final page = data['v$i'];
      final media = page is Map && page['media'] is List
          ? page['media'] as List
          : const [];
      final covers = <_Cover>[];
      for (final m in media) {
        if (m is! Map) continue;
        final image = m['coverImage'];
        final url = image is Map ? image['large'] : null;
        if (url is! String || url.isEmpty) continue;
        // The row's own rule for Hidden Gems (averageScore >= 80).
        final score = m['averageScore'];
        if (cat.isHiddenGems && (score is! num || score < 80)) continue;
        covers.add(_Cover(
          m['id'] is int ? m['id'] as int : 0,
          url,
          image is Map ? image['color'] as String? : null,
        ));
      }
      final n = _handOf(cat).length;
      final pick = [
        for (final c in covers)
          if (!dealt.contains(c.id)) c,
      ].take(n).toList();
      for (final c in covers) {
        if (pick.length >= n) break;
        if (!pick.contains(c)) pick.add(c);
      }
      dealt.addAll(pick.map((c) => c.id));
      out[cat.name] = pick;
    }
    return out;
  }

  static Map<String, List<_Cover>>? _decodeCovers(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      return {
        for (final e in m.entries)
          if (e.key is String && e.value is List)
            e.key as String: [
              for (final c in e.value as List) ?_Cover.fromJson(c),
            ],
      };
    } catch (_) {
      return null;
    }
  }

  /// PulseService._query's shape: the shared throttle, the 15 s timeout,
  /// the availability signal, AniList's rate-limit headers and a backoff
  /// on 429. Null on any failure, so the caller falls back.
  static Future<Map<String, dynamic>?> _query(Map<String, dynamic> body) async {
    await AnilistService.throttle();
    try {
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
        AnilistService.noteStatus(0, 'vibes');
        rethrow;
      }
      AnilistService.noteStatus(response.statusCode, 'vibes');
      AnilistService.noteLimits(response.headers);
      if (response.statusCode == 429) {
        final retryAfter =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 10;
        AnilistService.backoff(retryAfter);
        return null;
      }
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Widget _row(_Category c, {required bool wide}) => _CategoryRow(
        key: ValueKey(c.name),
        category: c,
        covers: _covers[c.name] ?? const [],
        wide: wide,
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final columns = Responsive.columnsFor(MediaQuery.sizeOf(context).width);
    if (columns == 1) {
      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        itemCount: _categories.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _row(_categories[i], wide: false),
        ),
      );
    }
    // Desktop: the featured vibe across the top, the rest in columns, each
    // of which grows on its own when one of its vibes opens.
    final rest = _categories.skip(1).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(_categories.first, wide: true),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < columns; col++) ...[
                if (col > 0) const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    children: [
                      for (var i = col; i < rest.length; i += columns)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: _row(rest[i], wide: true),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Category Row
// ─────────────────────────────────────────────────────────────
// Since round seven, a board: the vibe's name, its tagline and its covers in
// the vibe's hand, on a tint taken from those covers. A tap opens the vibe's
// list in place, on the same board, as before.

class _CategoryRow extends StatefulWidget {
  final _Category category;
  final List<_Cover> covers;
  final bool wide;
  const _CategoryRow({
    super.key,
    required this.category,
    required this.covers,
    required this.wide,
  });

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  final _anilist = AnilistService();
  List<Anime> _anime = [];
  bool _loading = false;
  bool _expanded = false;
  bool _hasFetched = false;
  // Outcome of this row's own last fetch (null = AniList answered). The
  // empty message follows this, not AnilistService's app-wide flag, which
  // a 200 anywhere else clears while this row still holds a failed fetch.
  int? _failStatus;
  // A press, a hover or keyboard focus lifts the hand.
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  // Whether this board deals its hand in: the first time it is built in a
  // session, so the deal comes with scrolling to a vibe, not on every visit.
  late final bool _dealIn;

  // ── Static cache keyed by category name — survives widget rebuilds ──
  static final Map<String, List<Anime>> _globalCache = {};
  static final Set<String> _dealt = {};

  @override
  void initState() {
    super.initState();
    _dealIn = _dealt.add(widget.category.name);
    // Seed from cache immediately — no re-fetch needed on rebuild
    final cached = _globalCache[widget.category.name];
    if (cached != null) {
      _anime     = cached;
      _hasFetched = true;
    }
  }

  Future<void> _load() async {
    if (_hasFetched) return; // already loaded, don't re-fetch
    setState(() => _loading = true);
    try {
      final results = await _anilist.searchAnime(
        '',
        genre: widget.category.genre,
        sort: widget.category.sort,
      );
      // searchAnime has no await after its request, so the flag still holds
      // this row's own outcome here — no other request can land in between.
      final failStatus = AnilistService.lastFailStatus;
      if (mounted) {
        setState(() {
          _failStatus = failStatus;
          _anime = widget.category.isHiddenGems
              ? results.where((a) =>
                  a.averageScore != null && a.averageScore! >= 80).toList()
              : results;
          _loading = false;
          _hasFetched = true;
        });
        // Save to static cache so rebuild doesn't re-fetch
        if (_anime.isNotEmpty) {
          _globalCache[widget.category.name] = _anime;
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (!_hasFetched) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final still = MediaQuery.disableAnimationsOf(context);
    final tint = _tintOf(widget.covers);
    final hero = cat.isHiddenGems;
    final lifted = !still && (_pressed || _hovered || _focused);

    // The tint: AniList's colour for the covers, at Hanko's cover-tint
    // strength (20%) behind the hand, fading to 5% by the words. Mixed into
    // sumi 2 here so the board stays opaque.
    Color mix(double a) => tint == null
        ? AppTheme.hankoSumi2
        : Color.alphaBlend(tint.withValues(alpha: a), AppTheme.hankoSumi2);
    final field = BoxDecoration(
      borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
      gradient: RadialGradient(
        center: hero && !widget.wide
            ? const Alignment(0, 0.45)
            : const Alignment(0.62, 0.3),
        radius: hero && !widget.wide ? 1.1 : 0.95,
        colors: [mix(AppTheme.hankoTintOpacity), mix(0.05)],
      ),
    );

    final cw = hero ? (widget.wide ? 76.0 : 58.0) : (widget.wide ? 62.0 : 54.0);
    final hand = _Hand(
      cards: _handOf(cat),
      covers: widget.covers,
      coverWidth: cw,
      extent: hero ? _handExtent([_handOf(cat)]) : _standardExtent,
      lifted: lifted,
      dealIn: _dealIn && !still,
    );
    // What the vibe is made of, as a printed label: its genre and the order
    // AniList sorts it in, in the words Discover's own tabs use.
    final label = Text(
      '${cat.genre} · ${_sortWords[cat.sort] ?? cat.sort}'.toUpperCase(),
      style: AppTheme.hankoSans(
        fontSize: AppTheme.hankoDataSmallSize,
        weight: FontWeight.w500,
        color: AppTheme.hankoStoneHi,
        letterSpacing: 1.2,
        height: 1.4,
        tabular: true,
      ),
    );

    final name = Text(
      cat.name,
      style: AppTheme.hankoSerif(
        fontSize: hero ? AppTheme.hankoLedeSize : AppTheme.hankoFeaturedSize,
        height: 1.2,
      ),
    );
    final tagline = Text(
      cat.tagline,
      style: AppTheme.hankoSans(
        fontSize: AppTheme.hankoMetaSize,
        color: AppTheme.hankoStoneHi,
        height: 1.35,
      ),
    );
    final chevron = AnimatedRotation(
      turns: _expanded ? 0.5 : 0,
      duration: still ? Duration.zero : const Duration(milliseconds: 200),
      child: const Icon(Icons.keyboard_arrow_down_sharp,
          color: AppTheme.hankoStoneHi, size: 22),
    );

    final Widget face;
    if (hero && !widget.wide) {
      // The featured board: the name, then the spread.
      face = Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: name), chevron],
            ),
            const SizedBox(height: 2),
            tagline,
            const SizedBox(height: 6),
            label,
            const SizedBox(height: 12),
            Center(child: hand),
          ],
        ),
      );
    } else {
      // A board: the name across the top; under it the tagline and label on
      // the left, the hand on the right. The name gets the whole width, so
      // a long one ("Tragic Masterpieces") never breaks inside a word.
      face = Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: name), chevron],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [tagline, const SizedBox(height: 8), label],
                  ),
                ),
                const SizedBox(width: 8),
                hand,
              ],
            ),
          ],
        ),
      );
    }

    // One semantics node (container) with the InkWell's tap and focus
    // inside it, Hanko's pattern for a custom control (CLAUDE.md, Design
    // system). The words and covers are left out of the tree, since the
    // label says them.
    final header = Semantics(
      container: true,
      button: true,
      expanded: _expanded,
      label: '${cat.name}. ${cat.tagline}',
      child: AnimatedScale(
        scale: _pressed && !still ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration:
                    still ? Duration.zero : const Duration(milliseconds: 300),
                decoration: field,
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _toggle,
                onHighlightChanged: (v) => setState(() => _pressed = v),
                onHover: (v) => setState(() => _hovered = v),
                onFocusChange: (v) => setState(() => _focused = v),
                splashFactory: NoSplash.splashFactory,
                highlightColor: AppTheme.hankoPressWash,
                hoverColor: AppTheme.hankoPressWash,
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                child: ExcludeSemantics(child: face),
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        // ── The vibe's list, opened on the same board ───────────
        AnimatedSize(
          duration: still ? Duration.zero : AppTheme.hankoSheetRise,
          curve: AppTheme.hankoSheetCurve,
          alignment: Alignment.topCenter,
          child: _expanded
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: mix(0.05),
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(AppTheme.hankoRadius)),
                  ),
                  child: _results(cat, still),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _results(_Category cat, bool still) {
    final scaler = MediaQuery.textScalerOf(context);
    final height = _AnimeCard.heightFor(scaler);
    if (_loading) {
      // Covers on sumi 3 while they load, as everywhere in Hanko.
      return SizedBox(
        height: height + 28,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, _) => Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: _AnimeCard.width,
              height: _AnimeCard.width * _coverRatio,
              decoration: BoxDecoration(
                color: AppTheme.hankoSumi3,
                borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              ),
            ),
          ),
        ),
      );
    }
    if (_anime.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
        child: Text(
          AnilistService.messageFor(_failStatus) ?? 'No titles found',
          style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoMetaSize, color: AppTheme.hankoStoneHi),
        ),
      );
    }
    return SizedBox(
      height: height + 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        itemCount: _anime.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _AnimeCard(
          anime: _anime[i],
          accentColor: AppTheme.hankoAi,
          index: i,
          still: still,
        ),
      ),
    );
  }
}

// The box every three-cover hand shares, so the boards line up.
final Rect _standardExtent = _handExtent([
  _defaultHand,
  for (final c in _categories)
    if (!c.isHiddenGems) _handOf(c),
]);

// ─────────────────────────────────────────────────────────────
// The hand — a vibe's covers, posed (round seven)
// ─────────────────────────────────────────────────────────────

class _Hand extends StatelessWidget {
  final List<_Card> cards;
  final List<_Cover> covers;
  final double coverWidth;
  // What the hand covers around its centre, in cover widths (_handExtent).
  final Rect extent;
  final bool lifted;
  final bool dealIn;

  const _Hand({
    required this.cards,
    required this.covers,
    required this.coverWidth,
    required this.extent,
    required this.lifted,
    required this.dealIn,
  });

  @override
  Widget build(BuildContext context) {
    // The deal: the covers start stacked in the middle and fan out to the
    // vibe's pose, once. The lift: a press, hover or focus spreads them.
    return RepaintBoundary(
      child: SizedBox(
        width: extent.width * coverWidth,
        height: extent.height * coverWidth,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: dealIn ? 0 : 1, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, deal, _) => TweenAnimationBuilder<double>(
            tween: Tween(end: lifted ? 1 : 0),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            builder: (context, lift, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                for (final c in cards) _placed(c, deal, lift),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placed(_Card c, double deal, double lift) {
    final w = coverWidth;
    final h = w * _coverRatio;
    final dx = c.dx * (1 + _spreadDx * lift) * deal * w;
    final dy = (c.dy * deal + 0.12 * (1 - deal) - _spreadLift * lift) * w;
    final tilt = c.tilt * (1 + _spreadTilt * lift) * deal;
    final scale = 0.94 + (c.scale - 0.94) * deal;
    final cover = c.cover < covers.length ? covers[c.cover] : null;
    return Positioned(
      left: -extent.left * w - w / 2 + dx,
      top: -extent.top * w - h / 2 + dy,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: tilt * math.pi / 180,
        child: Transform.scale(
          scale: scale,
          child: _CoverCard(cover: cover, veil: c.veil),
        ),
      ),
    );
  }
}

/// One cover as a printed card: the art inside a 2 px sumi keyline, square
/// 2 px corners, on sumi 3 while it loads, with a hard print shadow (no
/// blur, so no blur cost) and, for covers that recede, a sumi veil.
class _CoverCard extends StatelessWidget {
  final _Cover? cover;
  final double veil;

  const _CoverCard({required this.cover, required this.veil});

  @override
  Widget build(BuildContext context) {
    final c = cover;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.hankoSumi3,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        border: Border.all(
            color: AppTheme.hankoSumi, width: AppTheme.hankoKeyline),
        boxShadow: const [
          BoxShadow(color: Color(0x8C000000), offset: Offset(0, 3)),
        ],
      ),
      position: DecorationPosition.background,
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.hankoKeyline),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (c != null)
              CachedNetworkImage(
                imageUrl: c.url,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.expand(),
              ),
            if (veil > 0)
              ColoredBox(color: AppTheme.hankoSumi.withValues(alpha: veil)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Anime Card
// ─────────────────────────────────────────────────────────────
// Since round seven, a poster on the vibe's board: the cover on sumi 3 while
// it loads, square 2 px corners, the title in Jost 500 under it and the
// crowd's score in ai (no star, as Home's Tonight's drop). The posters deal
// in one after another the first time the list shows.

class _AnimeCard extends StatelessWidget {
  final Anime anime;
  // The colour the crowd's score is set in.
  final Color accentColor;
  final int index;
  final bool still;

  const _AnimeCard({
    required this.anime,
    required this.accentColor,
    required this.index,
    required this.still,
  });

  static const double width = 112;

  /// The cover, the gaps, two lines of title and the score line at the
  /// reader's text size.
  static double heightFor(TextScaler scaler) =>
      width * _coverRatio +
      8 +
      scaler.scale(AppTheme.hankoLabelSize) * 1.25 * 2 +
      4 +
      scaler.scale(AppTheme.hankoLabelSize) * 1.25;

  @override
  Widget build(BuildContext context) {
    final title = anime.titleEnglish ?? anime.title;
    final score = anime.averageScore;
    final scoreText = score == null ? null : (score / 10).toStringAsFixed(1);
    final poster = Semantics(
      container: true,
      button: true,
      label: [title, if (scoreText != null) 'AniList $scoreText'].join(', '),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AnimeDetailScreen(anime: anime)),
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: ExcludeSemantics(
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  child: SizedBox(
                    width: width,
                    height: width * _coverRatio,
                    child: ColoredBox(
                      color: AppTheme.hankoSumi3,
                      child: anime.imageUrl == null
                          ? const SizedBox.expand()
                          : CachedNetworkImage(
                              imageUrl: anime.imageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, _, _) =>
                                  const SizedBox.expand(),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoLabelSize,
                    weight: FontWeight.w500,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (scoreText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    scoreText,
                    style: AppTheme.hankoSans(
                      fontSize: AppTheme.hankoLabelSize,
                      weight: FontWeight.w500,
                      color: accentColor,
                      height: 1.25,
                      tabular: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (still || index > 5) return poster;
    // The deal: each of the first six slides in a beat after the last.
    final delay = 45.0 * index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: (260 + delay).round()),
      curve: Interval(delay / (260 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(16 * (1 - t), 0), child: child),
      ),
      child: poster,
    );
  }
}
