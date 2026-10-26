import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'hanko_seal.dart';

/// Whose ratings a [HankoSealRegister] shows.
enum HankoRegisterOwner {
  /// Your ratings, in your seal's colour.
  yours,

  /// The crowd's scores from AniList, in quiet indigo.
  crowd,
}

/// Hanko's ratings graph, the "seal register": option A of frame 10 in
/// `design/mockups/looks/hanko.html`, drawn in place of a bar chart.
///
/// Every score keeps its place on the rating ruler, 1 to 10 in half steps.
/// That is Hanj's stored scale; the mockup draws 0.5 to 10. How often a score
/// was given becomes the area of its seal impression: the side grows with the
/// square root of the count, so twice the ratings reads as twice the area. The
/// most-given score is the filled seal and carries its number, and a caret
/// marks the average. The scale's numbers, that label and, at Profile width,
/// "average 7.6" are drawn as words, so no meaning rests on colour alone.
///
/// One painter, no blur, two layouts by width:
/// - 200 px and wider (Profile's 320): impressions up to 15 px over a ruler
///   with half-step ticks and every whole number; the most-given number above
///   its seal; the caret and "average 7.6" below. 84 px tall.
/// - Narrower (Detail's 112): impressions up to 11 px with the caret above
///   them; below the ruler only the ends and the most-given number. 40 px
///   tall.
///
/// With no ratings it draws the empty ruler and one sentence. The numbers in
/// the drawing keep their size at any text-scale setting; [summary] and the
/// screen-reader label carry the same facts as text.
class HankoSealRegister extends StatelessWidget {
  /// A register of [counts]: how many times each score was given, keyed by
  /// score. Scores are rounded to the nearest half step, and any that land
  /// outside 1 to 10 (an imported rating on another scale, D20) are left out
  /// rather than drawn at an end.
  const HankoSealRegister({
    super.key,
    required this.counts,
    this.owner = HankoRegisterOwner.yours,
    this.tone = HankoSealTone.coral,
    this.average,
    this.semanticLabel,
  });

  /// Your register from your ratings, one per rated show.
  factory HankoSealRegister.fromRatings(
    Iterable<double> ratings, {
    Key? key,
    HankoSealTone tone = HankoSealTone.coral,
    String? semanticLabel,
  }) {
    final counts = <double, int>{};
    for (final r in ratings) {
      final score = (r * 2).round() / 2;
      counts[score] = (counts[score] ?? 0) + 1;
    }
    return HankoSealRegister(key: key, counts: counts, tone: tone, semanticLabel: semanticLabel);
  }

  /// The crowd's register from AniList's `stats.scoreDistribution`: each
  /// bucket's score (10, 20 … 100) and how many users gave it.
  ///
  /// AniList reports its users' scores only in these ten 10-point buckets, so
  /// the crowd has no half steps. Each bucket sits on its whole number on
  /// Hanj's ruler, 10 → 1, 20 → 2 … 100 → 10: the same straight division by
  /// ten that turns AniList's 100-point scale into 10 points. Nothing is drawn
  /// on the halves, because AniList doesn't say what falls there.
  /// [averageScore] is AniList's own 0–100 average (91 sits at 9.1); without
  /// it the caret sits at the mean of the buckets.
  factory HankoSealRegister.anilist(
    Map<int, int> distribution, {
    Key? key,
    int? averageScore,
    String? semanticLabel,
  }) {
    return HankoSealRegister(
      key: key,
      counts: {for (final e in distribution.entries) e.key / 10: e.value},
      owner: HankoRegisterOwner.crowd,
      average: averageScore == null ? null : averageScore / 10,
      semanticLabel: semanticLabel,
    );
  }

  /// How many times each score was given, keyed by score on the 1–10 scale.
  final Map<double, int> counts;

  final HankoRegisterOwner owner;

  /// Your seal's colour. The crowd is always indigo.
  final HankoSealTone tone;

  /// Where the caret sits on the 1–10 scale. Defaults to the mean of [counts].
  final double? average;

  /// What a screen reader says. Defaults to [summary] followed by every
  /// score's count.
  final String? semanticLabel;

  /// The key numbers as one sentence, for a caption beside the register:
  /// "109 rated, average 7.6, most often 8." or, for the crowd, "213,823
  /// ratings, average 9.1, most often 10."
  String get summary => _Stats(counts, average).sentence(owner);

  @override
  Widget build(BuildContext context) {
    final stats = _Stats(counts, average);
    final label = semanticLabel ??
        '${owner == HankoRegisterOwner.yours ? 'Your ratings' : 'AniList scores'}: '
            '${stats.sentence(owner)}${stats.countsInWords()}';
    return Semantics(
      container: true,
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;
            final compact = width < 200;
            return CustomPaint(
              size: Size(width, compact ? 40 : 84),
              painter: _RegisterPainter(stats, owner, tone, compact),
            );
          },
        ),
      ),
    );
  }
}

/// The 19 half-step slots from 1 to 10 and what follows from them.
class _Stats {
  factory _Stats(Map<double, int> counts, double? average) {
    final slots = List<int>.filled(19, 0);
    counts.forEach((score, n) {
      final i = ((score - 1) * 2).round();
      if (i >= 0 && i < slots.length && n > 0) slots[i] += n;
    });
    var total = 0;
    var weighted = 0.0;
    for (var i = 0; i < slots.length; i++) {
      total += slots[i];
      weighted += slots[i] * (1 + i / 2);
    }
    final most = slots.reduce(math.max);
    return _Stats._(
      slots,
      total,
      total == 0 ? null : (average ?? weighted / total).clamp(1.0, 10.0),
      most,
    );
  }

  _Stats._(this.slots, this.total, this.average, this.most);

  final List<int> slots;
  final int total;
  final double? average;
  final int most;

  static double scoreAt(int i) => 1 + i / 2;

  bool get hasHalves => [for (var i = 1; i < slots.length; i += 2) slots[i]].any((n) => n > 0);

  List<int> get modes => [
        for (var i = 0; i < slots.length; i++)
          if (most > 0 && slots[i] == most) i,
      ];

  String sentence(HankoRegisterOwner owner) {
    if (total == 0) {
      return owner == HankoRegisterOwner.yours ? 'No ratings yet.' : 'No AniList scores yet.';
    }
    final head = owner == HankoRegisterOwner.yours
        ? '$total rated'
        : '${thousands(total)} ${total == 1 ? 'rating' : 'ratings'}';
    // "Most often" means something only once a score was given twice.
    final often = most > 1 ? ', most often ${_list([for (final i in modes) score(scoreAt(i))])}' : '';
    return '$head, average ${average!.toStringAsFixed(1)}$often.';
  }

  String countsInWords() {
    if (total == 0) return '';
    final parts = [
      for (var i = 0; i < slots.length; i++)
        if (slots[i] > 0) '${score(scoreAt(i))}: ${thousands(slots[i])}',
    ];
    return ' Counts by score: ${parts.join('; ')}.';
  }

  static String score(double s) => s == s.roundToDouble() ? s.toInt().toString() : s.toStringAsFixed(1);

  static String thousands(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _list(List<String> items) => items.length < 2
      ? items.join()
      : '${items.sublist(0, items.length - 1).join(', ')} and ${items.last}';
}

class _RegisterPainter extends CustomPainter {
  _RegisterPainter(this.stats, this.owner, this.tone, this.compact)
      : super(repaint: PaintingBinding.instance.systemFonts);

  final _Stats stats;
  final HankoRegisterOwner owner;
  final HankoSealTone tone;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final x0 = compact ? 5.0 : 8.0;
    final x1 = w - x0;
    double xOf(double score) => x0 + (score - 1) / 9 * (x1 - x0);

    final crowd = owner == HankoRegisterOwner.crowd;
    final shu = !crowd && tone == HankoSealTone.shu;
    final ink = crowd ? AppTheme.hankoAiDeep : (shu ? AppTheme.hankoShu : AppTheme.hankoCoral);
    final key = crowd ? AppTheme.hankoAi : ink;
    final rulerY = compact ? 27.0 : 46.0;
    final placed = <Rect>[];

    // The ruler: a hairline, with half-step ticks on the wide layout.
    canvas.drawRect(
      Rect.fromLTRB(x0, rulerY - 0.5, x1, rulerY + 0.5),
      Paint()..color = AppTheme.hankoEdge,
    );
    if (!compact) {
      for (var i = 0; i < 19; i++) {
        final whole = i.isEven;
        canvas.drawRect(
          Rect.fromLTWH(xOf(_Stats.scoreAt(i)) - 0.5, rulerY, 1, whole ? 6 : 3),
          Paint()..color = whole ? AppTheme.hankoStone : AppTheme.hankoEdge,
        );
      }
    }

    final average = stats.average;
    if (stats.total == 0) {
      final sentence = stats.sentence(owner);
      _text(canvas, sentence, AppTheme.hankoSans(
        fontSize: compact ? AppTheme.hankoDataSmallSize : AppTheme.hankoMetaSize,
        color: AppTheme.hankoStone,
      ), Offset(w / 2, compact ? 16 : 28), _Anchor.centre, maxWidth: w);
    } else {
      // The impressions: area proportional to count; small ones filled.
      final pitch = (x1 - x0) / (stats.hasHalves ? 18 : 9);
      final maxSide = math.min(compact ? 11.0 : 15.0, pitch * 0.94);
      final cy = compact ? 16.0 : 28.0;
      final stroke = Paint()..style = PaintingStyle.stroke;
      for (var i = 0; i < 19; i++) {
        final n = stats.slots[i];
        if (n == 0) continue;
        final mode = n == stats.most;
        final side = mode ? maxSide : math.max(1.6, maxSide * math.sqrt(n / stats.most));
        final r = Rect.fromCenter(center: Offset(xOf(_Stats.scoreAt(i)), cy), width: side, height: side);
        if (mode) {
          canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1)), Paint()..color = key);
          if (!compact) {
            canvas.drawRect(
              r.deflate(2.5),
              stroke
                ..strokeWidth = 1
                ..color = shu
                    ? AppTheme.hankoWashi.withValues(alpha: 0.5)
                    : AppTheme.hankoSumi.withValues(alpha: 0.45),
            );
          }
        } else if (compact || side < 5) {
          canvas.drawRect(r, Paint()..color = ink);
        } else {
          canvas.drawRect(r.deflate(0.75), stroke..strokeWidth = 1.5..color = ink);
          if (side >= 11) {
            canvas.drawRect(
              r.deflate(3.25),
              stroke
                ..strokeWidth = 1
                ..color = ink.withValues(alpha: 0.55),
            );
          }
        }
      }

      // The average: a caret below the ruler (wide) or above the seals (narrow).
      if (average != null) {
        final xa = xOf(average);
        final caret = Path();
        if (compact) {
          caret
            ..moveTo(xa - 3, 2)
            ..lineTo(xa + 3, 2)
            ..lineTo(xa, 7);
        } else {
          caret
            ..moveTo(xa, 54)
            ..lineTo(xa + 3.5, 60)
            ..lineTo(xa - 3.5, 60);
          placed.add(Rect.fromLTRB(xa - 4.5, 52, xa + 4.5, 66));
        }
        canvas.drawPath(caret..close(), Paint()..color = AppTheme.hankoWashi);
      }

      // The most-given score's number: above its seal (wide), below the
      // ruler (narrow, where the caret takes the space above).
      final keyStyle = AppTheme.hankoSans(
        fontSize: compact ? AppTheme.hankoDataSmallSize : AppTheme.hankoLabelSize,
        weight: FontWeight.w500,
        color: AppTheme.hankoWashi,
        height: 1,
      );
      for (final i in stats.modes) {
        final at = Offset(xOf(_Stats.scoreAt(i)), compact ? 39 : 14.5);
        final rect = _text(canvas, _Stats.score(_Stats.scoreAt(i)), keyStyle, at, _Anchor.baseline,
            avoid: placed, width: w);
        if (rect != null) placed.add(rect);
      }
    }

    // The scale's numbers: every whole number (wide) or the two ends (narrow).
    final numStyle = AppTheme.hankoSans(
      fontSize: AppTheme.hankoDataSmallSize,
      weight: FontWeight.w500,
      color: AppTheme.hankoAsh,
      height: 1,
      tabular: true,
    );
    if (compact) {
      _text(canvas, '1', numStyle, const Offset(4, 39), _Anchor.start, avoid: placed, width: w);
      _text(canvas, '10', numStyle, Offset(w - 4, 39), _Anchor.end, avoid: placed, width: w);
    } else {
      for (var k = 1; k <= 10; k++) {
        _text(canvas, '$k', numStyle, Offset(xOf(k.toDouble()), 64), _Anchor.baseline,
            avoid: placed, width: w);
      }
      if (average != null && stats.total > 0) {
        _text(
          canvas,
          'average ${average.toStringAsFixed(1)}',
          AppTheme.hankoSans(
            fontSize: AppTheme.hankoDataSmallSize,
            color: AppTheme.hankoStone,
            height: 1,
          ),
          Offset(xOf(average), 80),
          _Anchor.baseline,
          width: w,
        );
      }
    }
  }

  /// Paints [text] at [at] and returns where it went, or null when it would
  /// have collided with one of [avoid] (with 2 px to spare) and was skipped.
  /// Centred text is kept inside [width].
  Rect? _text(Canvas canvas, String text, TextStyle style, Offset at, _Anchor anchor,
      {List<Rect> avoid = const [], double? width, double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final scale = maxWidth != null && tp.width > maxWidth - 8 ? (maxWidth - 8) / tp.width : 1.0;
    final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    var left = switch (anchor) {
      _Anchor.start => at.dx,
      _Anchor.end => at.dx - tp.width,
      _Anchor.baseline || _Anchor.centre => at.dx - tp.width * scale / 2,
    };
    if (width != null) left = left.clamp(0.0, math.max(0.0, width - tp.width * scale));
    final top = anchor == _Anchor.centre ? at.dy - tp.height * scale / 2 : at.dy - base;
    final rect = Rect.fromLTWH(left, top, tp.width * scale, tp.height * scale);
    if (avoid.any((r) => r.inflate(2).overlaps(rect))) {
      tp.dispose();
      return null;
    }
    canvas
      ..save()
      ..translate(left, top)
      ..scale(scale);
    tp.paint(canvas, Offset.zero);
    canvas.restore();
    tp.dispose();
    return rect;
  }

  @override
  bool shouldRepaint(_RegisterPainter old) =>
      owner != old.owner ||
      tone != old.tone ||
      compact != old.compact ||
      stats.average != old.stats.average ||
      !listEquals(stats.slots, old.stats.slots);
}

enum _Anchor { start, end, baseline, centre }
