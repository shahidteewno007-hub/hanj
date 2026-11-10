import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Whose verdict a [HankoSeal] shows. Filled, outlined or dashed, so "mine"
/// never depends on colour alone.
enum HankoSealKind {
  /// Your rating: the filled seal.
  yours,

  /// Someone else's rating: the same square, drawn in ink.
  theirs,

  /// Not rated yet: an empty dashed slot where your seal will go.
  unrated,
}

/// The red your own seal is pressed in.
enum HankoSealTone {
  /// Hanj's coral, the default. Its numerals are knocked out to sumi
  /// (5.64:1); washi on coral would be 2.72:1, so that pairing never occurs.
  coral,

  /// The deeper shu option, with washi numerals (4.74:1). As a shape it is
  /// thin on sheets and tiles (3.00 and 2.75:1), so keep its keyline on.
  shu,
}

/// Hanko's seal (判子): a rating pressed onto a title like a signature.
///
/// One object with three states ([HankoSealKind]). Your seal is filled in
/// coral, or shu as the option, and carries a 2 px sumi keyline painted
/// outside its box the way CSS `box-shadow` is, so it stays separate from any
/// art or tint it is pressed across without changing its layout size. Someone
/// else's is the same square in a 1 px edge outline. An unrated one is a
/// dashed slot with a plus.
///
/// Values come from the spec card in `design/mockups/looks/hanko.html`. The
/// spec's sizes 24, 28, 40 and 56 set their numerals at 11.5, 12.5, 16 and
/// 22; sizes in between interpolate. Seals of 40 and up carry the thin inner
/// rule. A score that would overflow ("10.0" at 24, or a large text-scale
/// setting) shrinks to fit inside the square instead of spilling out.
///
/// The spec's tiny initial in the corner of large seals is left out on
/// purpose: beside a score, a lone "A" reads as a letter grade.
///
/// The seal is never a button, so it handles no taps of its own.
class HankoSeal extends StatelessWidget {
  /// A seal showing [label], usually a score such as "8.5". [label] is
  /// required unless [kind] is [HankoSealKind.unrated].
  const HankoSeal({
    super.key,
    this.label,
    this.size = 28,
    this.width,
    this.fontSize,
    this.kind = HankoSealKind.yours,
    this.tone = HankoSealTone.coral,
    this.keyline = true,
    this.showAdd = true,
    this.semanticLabel,
  }) : assert(label != null || kind == HankoSealKind.unrated);

  /// A seal showing [score] the way the app prints ratings, to one decimal.
  HankoSeal.score(
    double score, {
    super.key,
    this.size = 28,
    this.width,
    this.fontSize,
    this.kind = HankoSealKind.yours,
    this.tone = HankoSealTone.coral,
    this.keyline = true,
    this.semanticLabel,
  })  : label = formatScore(score),
        showAdd = true;

  /// The empty dashed slot where your seal will go.
  const HankoSeal.unrated({
    super.key,
    this.size = 28,
    this.width,
    this.showAdd = true,
    this.semanticLabel,
  })  : label = null,
        fontSize = null,
        kind = HankoSealKind.unrated,
        tone = HankoSealTone.coral,
        keyline = false;

  /// The text pressed into the seal. Ignored when unrated.
  final String? label;

  /// The seal's height, and its width unless [width] is set.
  final double size;

  /// Overrides the width, for the slightly wide seal set inline in a
  /// sentence (the spec's 2.3 by 2 em).
  final double? width;

  /// Overrides the numeral size that [size] implies.
  final double? fontSize;

  final HankoSealKind kind;

  /// Only your own seal is coloured, so this applies to [HankoSealKind.yours].
  final HankoSealTone tone;

  /// The 2 px sumi ring around your seal. Other people's seals and the empty
  /// slot never have one.
  final bool keyline;

  /// Whether the empty slot shows its plus.
  final bool showAdd;

  /// What a screen reader says. Defaults to "Your rating, 8.5",
  /// "Rating, 8.5" or "Not rated yet"; pass one that names the person for
  /// someone else's seal.
  final String? semanticLabel;

  /// Scores print to one decimal everywhere in the app, so "8.0", not "8".
  static String formatScore(double score) => score.toStringAsFixed(1);

  /// The numeral size for a seal of [size], from the spec's four sizes.
  static double numeralSizeFor(double size) {
    const anchors = <(double, double)>[(24, 11.5), (28, 12.5), (40, 16), (56, 22)];
    var i = 0;
    while (i < anchors.length - 2 && size > anchors[i + 1].$1) {
      i++;
    }
    final (x0, y0) = anchors[i];
    final (x1, y1) = anchors[i + 1];
    return math.max(8, y0 + (size - x0) * (y1 - y0) / (x1 - x0));
  }

  @override
  Widget build(BuildContext context) {
    final mine = kind == HankoSealKind.yours;
    final shu = tone == HankoSealTone.shu;
    final numeral = fontSize ?? numeralSizeFor(size);

    final Widget content;
    if (kind == HankoSealKind.unrated) {
      // 16 at the 28 px list size, 24 at Detail's 56, as the spec draws it.
      final iconSize = (16 + (size - 28) * 8 / 28).clamp(12.0, 28.0);
      content = showAdd
          ? Icon(Icons.add_sharp, size: iconSize, color: AppTheme.hankoWashi)
          : const SizedBox.shrink();
    } else {
      final text = Padding(
        padding: EdgeInsets.symmetric(horizontal: math.max(2, size * 0.08)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label!,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: AppTheme.hankoSerif(
              fontSize: numeral,
              color: mine && !shu ? AppTheme.hankoSumi : AppTheme.hankoWashi,
              height: 1,
              letterSpacing: -0.01 * numeral,
            ).copyWith(leadingDistribution: TextLeadingDistribution.even),
          ),
        ),
      );
      // Mincho figures sit a little low in their line box; the spec lifts
      // them 1 px on the larger seals.
      content = size >= 40
          ? Transform.translate(offset: const Offset(0, -1), child: text)
          : text;
    }

    return Semantics(
      container: true,
      image: true,
      label: semanticLabel ??
          switch (kind) {
            HankoSealKind.yours => 'Your rating, $label',
            HankoSealKind.theirs => 'Rating, $label',
            HankoSealKind.unrated => 'Not rated yet',
          },
      child: ExcludeSemantics(
        child: SizedBox(
          width: width ?? size,
          height: size,
          child: CustomPaint(
            painter: _SealPainter(
              kind: kind,
              fill: shu ? AppTheme.hankoShu : AppTheme.hankoCoral,
              rule: mine && size >= 40
                  ? (shu
                      ? AppTheme.hankoWashi.withValues(alpha: 0.5)
                      : AppTheme.hankoSumi.withValues(alpha: 0.42))
                  : null,
              ruleInset: size >= 56 ? 3 : 2.5,
              keyline: mine && keyline,
            ),
            child: Center(child: content),
          ),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({
    required this.kind,
    required this.fill,
    required this.rule,
    required this.ruleInset,
    required this.keyline,
  });

  final HankoSealKind kind;
  final Color fill;
  final Color? rule;
  final double ruleInset;
  final bool keyline;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    switch (kind) {
      case HankoSealKind.yours:
        if (keyline) {
          // Painted outside the box, like box-shadow: 0 0 0 2px sumi.
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              box.inflate(AppTheme.hankoKeyline),
              const Radius.circular(AppTheme.hankoRadius + AppTheme.hankoKeyline),
            ),
            Paint()..color = AppTheme.hankoSumi,
          );
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(AppTheme.hankoRadius)),
          Paint()..color = fill,
        );
        final rule = this.rule;
        if (rule != null) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(box.deflate(ruleInset + 0.5), const Radius.circular(1)),
            line..color = rule,
          );
        }
      case HankoSealKind.theirs:
        canvas.drawRRect(
          RRect.fromRectAndRadius(box.deflate(0.5), const Radius.circular(AppTheme.hankoRadius - 0.5)),
          line..color = AppTheme.hankoEdge,
        );
      case HankoSealKind.unrated:
        _dashedSquare(
          canvas,
          box.deflate(0.5),
          line
            ..color = AppTheme.hankoStoneHi
            ..strokeCap = StrokeCap.square,
        );
    }
  }

  // A 1 px dashed outline with a dash in every corner, about 3 on 3 like the
  // browser's dashed outline. Square caps add half a pixel at each end, so
  // each dash is drawn 1 px short of its length.
  void _dashedSquare(Canvas canvas, Rect r, Paint paint) {
    const dash = 3.0;
    final sides = [
      (r.topLeft, r.topRight),
      (r.topRight, r.bottomRight),
      (r.bottomRight, r.bottomLeft),
      (r.bottomLeft, r.topLeft),
    ];
    for (final (a, b) in sides) {
      final length = (b - a).distance;
      final n = math.max(2, ((length + dash) / (2 * dash)).round());
      final gap = (length - n * dash) / (n - 1);
      final step = (b - a) / length;
      for (var i = 0; i < n; i++) {
        final start = a + step * (i * (dash + gap) + 0.5);
        canvas.drawLine(start, start + step * (dash - 1), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      kind != old.kind ||
      fill != old.fill ||
      rule != old.rule ||
      ruleInset != old.ruleInset ||
      keyline != old.keyline;
}

/// Your seal pressed onto the page (Print Room, P6; DESIGN.md §9.3 A rule
/// 5): when you rate a show, or finish one you've rated.
///
/// Each time [presses] goes up, [child] (your seal) drops onto the print
/// from a little above it, overshoots and settles, and an ink ring in the
/// seal's coral spreads from its edge and fades: 240 ms in all, with one
/// haptic tick as it lands, at 90 ms. With Remove animations on, the seal
/// simply appears, with the tick. Nothing loops.
///
/// It rebuilds nothing, itself included: the seal is built once and moved,
/// scaled and inked by transitions, and the ring is painted from the same
/// controller in a layer of its own, so a press repaints only that layer.
/// The ring takes no room and isn't clipped: it spreads over whatever lies
/// around the seal.
///
/// One press for everything (achievements decision i, Shahid's A-13): the
/// same move presses a badge into the unlock slip, so [ink] gives the ring
/// the badge's own ink (sumi on paper) and [tick] lets the press stay silent
/// when the action already ticked. Left out, the press is the seal's, coral
/// with its tick, exactly as before: coral stays your seal's.
class HankoSealPress extends StatefulWidget {
  const HankoSealPress({
    super.key,
    required this.presses,
    required this.child,
    this.ink,
    this.tick = true,
  });

  /// How many times the seal has been pressed here. A new count presses it.
  final int presses;

  /// The seal.
  final Widget child;

  /// The ring's ink; null is the seal's coral.
  final Color? ink;

  /// Whether the press ticks as it lands (and, with Remove animations on,
  /// as it appears).
  final bool tick;

  static const Duration duration = Duration(milliseconds: 240);

  /// Where the seal lands, as a fraction of [duration]: 90 ms.
  static const double _landing = 90 / 240;

  @override
  State<HankoSealPress> createState() => _HankoSealPressState();
}

class _HankoSealPressState extends State<HankoSealPress>
    with SingleTickerProviderStateMixin {
  // At rest until the first press.
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: HankoSealPress.duration,
    value: 1,
  )..addListener(_land);

  // The seal falls from 1.3x to 0.95 (ease in: it falls), rebounds to 1.02
  // and settles: the storyboard's 0, 90, 160 and 240 ms.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.3, end: 0.95).chain(CurveTween(curve: Curves.easeIn)),
      weight: 90,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 0.95, end: 1.02).chain(CurveTween(curve: Curves.easeOut)),
      weight: 70,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.02, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 80,
    ),
  ]).animate(_press);

  static final Animatable<double> _falling = CurveTween(
      curve: const Interval(0, HankoSealPress._landing, curve: Curves.easeIn));

  // From a little up and to the right (the storyboard's 6 and 10 px for a
  // 44 px seal), held above the paper at 45% ink until it lands.
  late final Animation<Offset> _drop = _press.drive(
      Tween(begin: const Offset(0.14, -0.23), end: Offset.zero).chain(_falling));
  late final Animation<double> _ink =
      _press.drive(Tween(begin: 0.45, end: 1.0).chain(_falling));

  bool _landed = true;

  @override
  void didUpdateWidget(HankoSealPress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.presses <= oldWidget.presses) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _press.value = 1;
      if (widget.tick) _tick();
      return;
    }
    _landed = false;
    _press.forward(from: 0);
  }

  void _land() {
    if (_landed || _press.value < HankoSealPress._landing) return;
    _landed = true;
    if (widget.tick) _tick();
  }

  // One tick as the seal meets the paper. A platform call that fails is
  // only a missing tick: it must never reach Crashlytics (CLAUDE.md).
  static void _tick() =>
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _InkRing(_press, widget.ink ?? AppTheme.hankoCoral),
        child: SlideTransition(
          position: _drop,
          child: ScaleTransition(
            scale: _scale,
            child: FadeTransition(opacity: _ink, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// The ink a press leaves (P6): a ring in the seal's coral (or the press's
/// [ink]) that leaves the seal's edge as it lands, spreads and fades. For
/// the storyboard's 44 px seal, 8 px out at 3 px and 55% at 90 ms, 18 px at
/// 2 px and about 25% at 160 ms, gone at 240; scaled with the seal.
class _InkRing extends CustomPainter {
  _InkRing(this.press, this.ink) : super(repaint: press);

  final Animation<double> press;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const landing = HankoSealPress._landing;
    final t = press.value;
    if (t <= landing || t >= 1) return;
    final spread = (t - landing) / (1 - landing);
    final side = size.shortestSide;
    final out = side * (0.18 + 0.27 * Curves.easeOutCubic.transform(spread));
    final stroke = 3 - 1.5 * spread;
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).inflate(out + stroke / 2),
          Radius.circular(AppTheme.hankoRadius + out * 0.15)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = ink.withValues(alpha: 0.55 * (1 - spread)),
    );
  }

  @override
  bool shouldRepaint(_InkRing old) => old.press != press || old.ink != ink;
}
