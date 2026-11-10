import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'hanko_cover_colour.dart';

// Vibes, for the rest of the app (r9, 2026-11-10). Shahid: "I loved new
// vibes change, if we can bring that change to other tabs/features wherever
// needed that would be great".
//
// Discover's VIBES tab (features/discovery/emotional_categories.dart, round
// seven) draws a group of shows as a board: a field tinted by its own covers,
// a few of them held in a hand whose pose says what the group is, and a small
// printed label saying what feeds it; its posters are printed cards. These
// are the same pieces, redrawn so other screens can use them. The VIBES tab
// keeps its own private copies: CLAUDE.md forbids moving code between files.

/// AniList's covers are 230 × 326.
const double hankoCoverRatio = 326 / 230;

/// A group of shows as one object (Vibes): a field tinted by the group's own
/// covers, with Hanko's 2 px corners.
///
/// [tint] is the group's colour, usually from [HankoCoverTint]; null is plain
/// sumi 2. The [face] lies on a pool of it, [AppTheme.hankoTintOpacity] (20%)
/// at [centre] fading to 5% at [radius] (of the board's shorter side), mixed
/// into sumi 2 so the board stays opaque. An optional [strip] runs under the
/// face at a flat 5%, as a Vibes board's list opens on. Put the crowd's ai
/// numbers there: ai drops to 3.4:1 on the 20% pool of the lightest cover
/// colours and keeps 5.4:1 at 5% (computed). On the pool itself, text is
/// washi or stone hi (7.9:1 and 5.5:1 at worst).
///
/// A tint arriving or changing crossfades in 300 ms, or at once with Remove
/// animations on. It's gradients only: no blur, no layer.
class HankoBoard extends StatelessWidget {
  const HankoBoard({
    super.key,
    required this.tint,
    required this.face,
    this.strip,
    this.centre = const Alignment(0.62, 0.3),
    this.radius = 0.95,
  });

  final Color? tint;
  final Widget face;
  final Widget? strip;
  final Alignment centre;
  final double radius;

  /// [tint] at [strength] over sumi 2, opaque.
  static Color mix(Color? tint, double strength) => tint == null
      ? AppTheme.hankoSumi2
      : Color.alphaBlend(tint.withValues(alpha: strength), AppTheme.hankoSumi2);

  /// The colour a board takes from its covers' [colours], in order: the first
  /// that isn't within Hanko's hue guard of the seal
  /// ([AppTheme.hankoCoverTint]), so no board reads as coral, which is only
  /// ever yours. Null: plain sumi 2.
  static Color? tintOf(Iterable<Color?> colours) {
    for (final c in colours) {
      if (AppTheme.hankoCoverTint(c) != null) return c;
    }
    return null;
  }

  /// A board's printed label ("ALL ANIME · BY SCORE"): Jost 500, tabular and
  /// tracked. Callers set it in caps. Stone hi on a board, stone on sumi.
  static TextStyle labelStyle({Color color = AppTheme.hankoStoneHi}) =>
      AppTheme.hankoSans(
        fontSize: AppTheme.hankoDataSmallSize,
        weight: FontWeight.w500,
        color: color,
        letterSpacing: 1.2,
        height: 1.4,
        tabular: true,
      );

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300);
    const corner = Radius.circular(AppTheme.hankoRadius);
    final strip = this.strip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: duration,
          decoration: BoxDecoration(
            borderRadius: strip == null
                ? const BorderRadius.all(corner)
                : const BorderRadius.vertical(top: corner),
            gradient: RadialGradient(
              center: centre,
              radius: radius,
              colors: [mix(tint, AppTheme.hankoTintOpacity), mix(tint, 0.05)],
            ),
          ),
          child: face,
        ),
        if (strip != null)
          AnimatedContainer(
            duration: duration,
            decoration: BoxDecoration(
              color: mix(tint, 0.05),
              borderRadius: const BorderRadius.vertical(bottom: corner),
            ),
            child: strip,
          ),
      ],
    );
  }
}

/// Builds with the colour a board takes from the covers at [urls]
/// ([HankoBoard.tintOf]), read from the covers themselves by
/// [HankoCoverColour] (Print Room: a 16 px decode of the URL the screen
/// already shows, no request, kept in memory). Colours already known paint in
/// the first frame; the rest arrive as they're read. A cover that can't be
/// read counts as grey, so a board without colour stays sumi 2.
///
/// [guard] false takes the first colour whatever its hue, for a Print Room
/// field behind one show ([AppTheme.hankoField] has no hue guard).
class HankoCoverTint extends StatefulWidget {
  const HankoCoverTint({
    super.key,
    required this.urls,
    required this.builder,
    this.guard = true,
  });

  final List<String> urls;
  final Widget Function(BuildContext context, Color? tint) builder;
  final bool guard;

  @override
  State<HankoCoverTint> createState() => _HankoCoverTintState();
}

class _HankoCoverTintState extends State<HankoCoverTint> {
  Color? _tint;
  // Bumped by each read, so an answer for covers since replaced is dropped.
  int _reads = 0;

  @override
  void initState() {
    super.initState();
    _tint = _known();
    _read();
  }

  @override
  void didUpdateWidget(HankoCoverTint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_same(oldWidget.urls, widget.urls)) {
      _tint = _known();
      _read();
    }
  }

  // Whether a cover's colour can be the tint.
  bool _usable(Color? c) =>
      widget.guard ? AppTheme.hankoCoverTint(c) != null : c != null;

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The tint from colours already in memory, as far as that decides it: an
  /// unknown cover ahead of the first usable colour could still be the one.
  Color? _known() {
    for (final u in widget.urls) {
      if (u.isEmpty) continue;
      if (!HankoCoverColour.knows(u)) return null;
      final c = HankoCoverColour.peek(u);
      if (_usable(c)) return c;
    }
    return null;
  }

  Future<void> _read() async {
    final read = ++_reads;
    Color? tint;
    for (final u in widget.urls) {
      if (u.isEmpty) continue;
      final c = await HankoCoverColour.ofUrl(u);
      if (!mounted || read != _reads) return;
      if (_usable(c)) {
        tint = c;
        break;
      }
    }
    if (tint != _tint) setState(() => _tint = tint);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tint);
}

/// One cover as a printed card (Vibes): the art inside a 2 px sumi keyline,
/// 2 px corners, on sumi 3 while it loads, with a hard print shadow (no blur,
/// so no blur cost) and, for a cover that recedes, a sumi [veil] (0–1).
/// [lifted] drops the shadow further, for a card under a pointer or keyboard
/// focus. Decorative: the screen names the show in its own node.
class HankoCard extends StatelessWidget {
  const HankoCard({
    super.key,
    required this.url,
    this.veil = 0,
    this.lifted = false,
  });

  final String? url;
  final double veil;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.hankoSumi3,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          border: Border.all(
              color: AppTheme.hankoSumi, width: AppTheme.hankoKeyline),
          boxShadow: [
            BoxShadow(
              color: const Color(0x8C000000),
              offset: Offset(0, lifted ? 6 : 3),
            ),
          ],
        ),
        position: DecorationPosition.background,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.hankoKeyline),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null && url.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => const SizedBox.expand(),
                ),
              if (veil > 0)
                ColoredBox(color: AppTheme.hankoSumi.withValues(alpha: veil)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One cover in a hand (Vibes). [cover] is which of the hand's covers it
/// shows (0 is the first); [dx] and [dy] place its centre from the hand's
/// centre in cover widths, so a hand keeps its shape at any size; [tilt] is in
/// degrees; [veil] (0–1) darkens a cover that recedes. A hand is drawn in list
/// order, so the last card is nearest. The poses are Vibes' own.
class HankoPose {
  const HankoPose(this.cover, this.dx, this.dy, this.tilt,
      {this.scale = 1, this.veil = 0});

  final int cover;
  final double dx;
  final double dy;
  final double tilt;
  final double scale;
  final double veil;

  /// The featured spread (Hidden Gems): five in an arc, the first nearest.
  static const featured = [
    HankoPose(4, -1.3, 0.24, -14),
    HankoPose(3, 1.3, 0.24, 14),
    HankoPose(2, -0.66, 0.06, -7),
    HankoPose(1, 0.66, 0.06, 7),
    HankoPose(0, 0, 0, 0),
  ];

  /// Splayed wide, mid-swing (Hype Machine): cards in play.
  static const splay = [
    HankoPose(2, -0.62, 0.14, -13),
    HankoPose(1, 0.02, -0.12, -2),
    HankoPose(0, 0.6, 0.06, 12),
  ];

  /// Upright, shoulder to shoulder (Found Family).
  static const level = [
    HankoPose(2, -0.64, 0, 0),
    HankoPose(1, 0, 0, 0),
    HankoPose(0, 0.64, 0, 0),
  ];

  /// Volumes going back into the dark (Deep Lore).
  static const recede = [
    HankoPose(2, -0.4, -0.22, 0, scale: 0.82, veil: 0.45),
    HankoPose(1, -0.14, -0.09, 0, scale: 0.91, veil: 0.22),
    HankoPose(0, 0.14, 0.06, 0),
  ];

  /// Falling away to one side, the nearest still standing (Tragic
  /// Masterpieces).
  static const fallAway = [
    HankoPose(2, -0.52, 0.16, -16, veil: 0.4),
    HankoPose(1, -0.06, 0.06, -8, veil: 0.2),
    HankoPose(0, 0.5, 0, 0),
  ];

  /// Vibes' default hand: a fan.
  static const fan = [
    HankoPose(2, -0.55, 0.08, -9),
    HankoPose(1, 0, -0.1, 0),
    HankoPose(0, 0.55, 0.08, 9),
  ];
}

/// A few covers posed (Vibes' hand). The covers start stacked in the middle
/// and fan out to the pose once when [dealIn]; [lifted] (a press, hover or
/// keyboard focus on what holds it) spreads them. Callers pass both as false
/// with Remove animations on. Sized to its own pose at full spread, so a lift
/// never moves the layout. Decorative: the holder names the shows.
class HankoHand extends StatelessWidget {
  const HankoHand({
    super.key,
    required this.poses,
    required this.urls,
    required this.coverWidth,
    required this.lifted,
    required this.dealIn,
  });

  final List<HankoPose> poses;

  /// The covers, by [HankoPose.cover]. A pose past the end shows sumi 3.
  final List<String> urls;
  final double coverWidth;
  final bool lifted;
  final bool dealIn;

  // A press or a hover spreads a hand: covers move out and tilt further.
  static const _spreadDx = 0.14;
  static const _spreadTilt = 0.35;
  static const _spreadLift = 0.05;

  /// What [poses] cover at full spread, in cover widths, around the hand's
  /// centre.
  static Rect extentOf(List<HankoPose> poses) {
    var l = 0.0, t = 0.0, r = 0.0, b = 0.0;
    for (final c in poses) {
      final a = (c.tilt * (1 + _spreadTilt)).abs() * math.pi / 180;
      final hw = (math.cos(a) + hankoCoverRatio * math.sin(a)) / 2 * c.scale;
      final hh = (math.sin(a) + hankoCoverRatio * math.cos(a)) / 2 * c.scale;
      final x = c.dx * (1 + _spreadDx);
      l = math.min(l, x - hw);
      r = math.max(r, x + hw);
      t = math.min(t, c.dy - _spreadLift - hh);
      b = math.max(b, c.dy + hh);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  @override
  Widget build(BuildContext context) {
    final extent = extentOf(poses);
    return ExcludeSemantics(
      child: RepaintBoundary(
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
                  for (final c in poses) _placed(c, extent, deal, lift),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _placed(HankoPose c, Rect extent, double deal, double lift) {
    final w = coverWidth;
    final h = w * hankoCoverRatio;
    final dx = c.dx * (1 + _spreadDx * lift) * deal * w;
    final dy = (c.dy * deal + 0.12 * (1 - deal) - _spreadLift * lift) * w;
    final tilt = c.tilt * (1 + _spreadTilt * lift) * deal;
    final scale = 0.94 + (c.scale - 0.94) * deal;
    return Positioned(
      left: -extent.left * w - w / 2 + dx,
      top: -extent.top * w - h / 2 + dy,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: tilt * math.pi / 180,
        child: Transform.scale(
          scale: scale,
          child: HankoCard(
            url: c.cover < urls.length ? urls[c.cover] : null,
            veil: c.veil,
          ),
        ),
      ),
    );
  }
}

/// A show as a printed poster in a grid (Vibes' list poster): the cover as a
/// [HankoCard], the title in Jost 500 on two lines, and the crowd's score in
/// ai, with no star. [rank] prints a plate number in the cover's corner, as
/// the Top 9 card numbers its plates. One button for a screen reader ("4,
/// Frieren, AniList 9.1"). A press presses the cover in (not with Remove
/// animations on); a pointer or keyboard focus drops its shadow further. Its
/// width comes from its parent.
class HankoPoster extends StatefulWidget {
  const HankoPoster({
    super.key,
    required this.url,
    required this.title,
    required this.score,
    required this.onTap,
    this.rank,
    this.caption,
  });

  final String? url;
  final String title;

  /// AniList's averageScore (0–100), or null.
  final double? score;
  final VoidCallback onTap;
  final int? rank;

  /// One line under the title in stone, such as a person's role on the
  /// show ("Director") or the character they voiced.
  final String? caption;

  /// The poster's height at [width]: the cover, the gaps, two lines of title
  /// and the score line at the reader's text size, and the [caption]'s line
  /// when [captioned].
  static double heightFor(double width, TextScaler scaler,
          {bool captioned = false}) =>
      width * hankoCoverRatio +
      8 +
      scaler.scale(AppTheme.hankoLabelSize) * 1.25 * (captioned ? 4 : 3) +
      (captioned ? 7 : 4);

  @override
  State<HankoPoster> createState() => _HankoPosterState();
}

class _HankoPosterState extends State<HankoPoster> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final score = widget.score;
    final scoreText = score == null ? null : (score / 10).toStringAsFixed(1);
    final rank = widget.rank;
    final caption = widget.caption;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      button: true,
      label: [
        if (rank != null) '$rank',
        widget.title,
        ?caption,
        if (scoreText != null) 'AniList $scoreText',
      ].join(', '),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (v) => setState(() => _pressed = v),
          onHover: (v) => setState(() => _hovered = v),
          onFocusChange: (v) => setState(() => _focused = v),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          child: ExcludeSemantics(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedScale(
                      scale: _pressed && !still ? 0.97 : 1,
                      duration: const Duration(milliseconds: 120),
                      child: SizedBox(
                        width: w,
                        height: w * hankoCoverRatio,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            HankoCard(
                                url: widget.url, lifted: _hovered || _focused),
                            if (rank != null)
                              Positioned(
                                left: 0,
                                top: 0,
                                child: HankoPlateNumber(rank: rank),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.title,
                      style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoLabelSize,
                        weight: FontWeight.w500,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (caption != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        caption,
                        style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoLabelSize,
                          color: AppTheme.hankoStone,
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (scoreText != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        scoreText,
                        style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoLabelSize,
                          weight: FontWeight.w500,
                          color: AppTheme.hankoAi,
                          height: 1.25,
                          tabular: true,
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// A plate number cut into a print's corner: washi figures on the sumi of
/// the card's keyline (15:1), as the Top 9 card numbers its plates.
class HankoPlateNumber extends StatelessWidget {
  const HankoPlateNumber({super.key, required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(color: AppTheme.hankoSumi),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 1, 6, 2),
          child: Text(
            '$rank',
            style: AppTheme.hankoSans(
              fontSize: AppTheme.hankoDataSmallSize,
              weight: FontWeight.w600,
              height: 1.3,
              tabular: true,
            ),
          ),
        ),
      );
}

/// A printed tab (Vibes' label as a control): Jost 500 caps, tabular and
/// tracked; washi with sumi figures when [selected] (CLAUDE.md: the selected
/// tab is washi, never coral), stone on sumi 3 otherwise. Drawn 36 dp tall,
/// touched at 48. One button for a screen reader, with keyboard focus on it.
class HankoTab extends StatelessWidget {
  const HankoTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
        child: Center(
          widthFactor: 1,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              child: ExcludeSemantics(
                child: AnimatedContainer(
                  duration: still
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  constraints: const BoxConstraints(
                      minHeight: AppTheme.hankoChipHeight),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.hankoWashi : AppTheme.hankoSumi3,
                    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                  ),
                  child: Text(
                    label.toUpperCase(),
                    style: HankoBoard.labelStyle(
                      color: selected ? AppTheme.hankoSumi : AppTheme.hankoStone,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of [HankoTab]s that scrolls sideways when it doesn't fit (at 360 dp
/// most rows don't), and brings the [selected] tab into view whenever it
/// changes, a swipe included, and when it starts past the edge. It scrolls
/// only its own row, never the page around it.
class HankoTabStrip extends StatefulWidget {
  const HankoTabStrip({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  State<HankoTabStrip> createState() => _HankoTabStripState();
}

class _HankoTabStripState extends State<HankoTabStrip> {
  late final List<GlobalKey> _keys =
      List.generate(widget.labels.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    if (widget.selected > 0) _reveal();
  }

  @override
  void didUpdateWidget(HankoTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) _reveal();
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.selected < 0 || widget.selected >= _keys.length) {
          return;
        }
        final tab = _keys[widget.selected].currentContext;
        final box = tab?.findRenderObject();
        final row = tab == null ? null : Scrollable.maybeOf(tab)?.position;
        if (box == null || row == null) return;
        row.ensureVisible(
          box,
          alignment: 0.5,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          curve: Curves.easeOut,
        );
      });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < widget.labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              HankoTab(
                key: _keys[i],
                label: widget.labels[i],
                selected: i == widget.selected,
                onTap: () => widget.onSelect(i),
              ),
            ],
          ],
        ),
      );
}

/// A printed chip (Vibes' print cues): washi words on sumi 3, 2 px corners,
/// drawn 36 dp tall and touched at 48, with a washi keyline when [on]. [icon]
/// leads and [trailing] follows. One button for a screen reader, named by
/// [semanticLabel].
class HankoChip extends StatelessWidget {
  const HankoChip({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.icon,
    this.trailing,
    this.on = false,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback onTap;
  final IconData? icon;
  final IconData? trailing;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final trailing = this.trailing;
    return Semantics(
      container: true,
      button: true,
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch),
        child: Center(
          widthFactor: 1,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              splashFactory: NoSplash.splashFactory,
              highlightColor: AppTheme.hankoPressWash,
              hoverColor: AppTheme.hankoPressWash,
              borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(
                      minHeight: AppTheme.hankoChipHeight),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.hankoSumi3,
                    borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
                    border: Border.all(
                      color: on ? AppTheme.hankoWashi : AppTheme.hankoSumi3,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 16, color: AppTheme.hankoWashi),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        label,
                        style: AppTheme.hankoSans(
                          fontSize: AppTheme.hankoLabelSize,
                          weight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 6),
                        Icon(trailing, size: 14, color: AppTheme.hankoStone),
                      ],
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
}

/// Deals a card in once (Vibes' posters): it slides from [from] and fades in,
/// a beat after the one before ([index] × 45 ms), the first six only. Nothing
/// moves when [play] is false or with Remove animations on.
class HankoDeal extends StatelessWidget {
  const HankoDeal({
    super.key,
    required this.index,
    required this.play,
    required this.from,
    required this.child,
  });

  final int index;
  final bool play;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!play || index > 5 || MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final delay = 45.0 * index;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: (260 + delay).round()),
      curve: Interval(delay / (260 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: from * (1 - t), child: child),
      ),
      child: child,
    );
  }
}

/// An empty hand: three dashed slots in Vibes' fan, where shows will go.
/// Decorative.
class HankoEmptyHand extends StatelessWidget {
  const HankoEmptyHand({super.key});

  static const double _width = 40;

  @override
  Widget build(BuildContext context) {
    const poses = HankoPose.fan;
    final extent = HankoHand.extentOf(poses);
    const w = _width, h = _width * hankoCoverRatio;
    return ExcludeSemantics(
      child: SizedBox(
        width: extent.width * w,
        height: extent.height * w,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final c in poses)
              Positioned(
                left: -extent.left * w - w / 2 + c.dx * w,
                top: -extent.top * w - h / 2 + c.dy * w,
                width: w,
                height: h,
                child: Transform.rotate(
                  angle: c.tilt * math.pi / 180,
                  child: const CustomPaint(painter: _DashedSlot()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashedSlot extends CustomPainter {
  const _DashedSlot();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.hankoEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(AppTheme.hankoRadius)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(
            metric.extractPath(d, math.min(d + 4, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedSlot oldDelegate) => false;
}
