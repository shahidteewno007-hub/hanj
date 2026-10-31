import 'dart:math' as math;

import 'package:flutter/material.dart';

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
