import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Episode progress as a reel: one tick per episode.
///
/// Solid ticks are watched, outlined ones have aired and are waiting, and
/// short ones haven't aired yet, so a new episode shows in the reel itself
/// with no separate "new" tag. Values come from the Progress entry of the
/// spec card in `design/mockups/looks/hanko.html`: ticks 3 by 10 px, 2 px
/// apart, washi on edge.
///
/// Past [maxTicks] episodes (30, as the spec says), or when one tick per
/// episode won't fit the width it is given, the reel becomes a line with the
/// same three states: a solid 2 px line for watched, an outlined sleeve for
/// aired but unwatched, and a 1 px hairline for episodes still to air.
///
/// An unknown total (a show still airing with no announced episode count)
/// draws only the episodes that are known and ends in an open tail of three
/// dashes instead of a last tick.
class HankoReel extends StatelessWidget {
  const HankoReel({
    super.key,
    required this.watched,
    this.total,
    this.aired,
    this.maxTicks = 30,
    this.lineWidth,
    this.semanticLabel,
  });

  /// Episodes watched.
  final int watched;

  /// The episode count, or null when it hasn't been announced.
  final int? total;

  /// Episodes aired so far. Null means every one of [total] has aired; when
  /// [total] is null too, nothing is known beyond [watched].
  final int? aired;

  /// The most episodes drawn as separate ticks.
  final int maxTicks;

  /// The line's length once the reel becomes a line. Defaults to the width of
  /// [maxTicks] ticks, so a 30-episode reel and a 31-episode line end level.
  final double? lineWidth;

  /// What a screen reader says. Defaults to a sentence such as "3 of 12
  /// watched; episode 4 has aired and is waiting".
  final String? semanticLabel;

  /// The reel's height in every state.
  static const double height = 10;

  static const double _tick = 3;
  static const double _gap = 2;
  static const double _tail = 12; // a gap, then three 2 px dashes 2 px apart

  /// The width of [n] ticks side by side.
  static double ticksWidth(int n) => n <= 0 ? 0 : n * (_tick + _gap) - _gap;

  @override
  Widget build(BuildContext context) {
    final total = this.total != null && this.total! > 0 ? this.total : null;
    final w = total == null ? math.max(0, watched) : watched.clamp(0, total);
    final a = math.max(w, math.min(aired ?? total ?? w, total ?? 1 << 30));
    final count = total ?? a; // episodes with a known place on the reel
    final open = total == null;

    return Semantics(
      container: true,
      image: true,
      label: semanticLabel ?? _describe(w, a, total),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tail = open ? _tail : 0.0;
            final ticks = ticksWidth(count) + tail;
            final asTicks = count <= maxTicks && ticks <= constraints.maxWidth;
            final width = asTicks
                ? ticks
                : math.min(lineWidth ?? ticksWidth(maxTicks) + tail, constraints.maxWidth);
            return CustomPaint(
              size: Size(width, height),
              painter: _ReelPainter(
                watched: w,
                aired: a,
                count: count,
                open: open,
                asTicks: asTicks,
              ),
            );
          },
        ),
      ),
    );
  }

  static String _describe(int w, int a, int? total) {
    if (total == null) {
      final soFar = a > w ? '; $a aired so far' : '';
      return '$w watched$soFar; episode count not announced';
    }
    final head = '$w of $total watched';
    if (a > w) {
      if (a - w == 1) return '$head; episode ${w + 1} has aired and is waiting';
      if (a == total) return '$head; all $total have aired';
      return '$head; episodes ${w + 1} to $a have aired';
    }
    if (w < total) return '$head; the next episode has not aired yet';
    return head;
  }
}

class _ReelPainter extends CustomPainter {
  const _ReelPainter({
    required this.watched,
    required this.aired,
    required this.count,
    required this.open,
    required this.asTicks,
  });

  final int watched;
  final int aired;
  final int count;
  final bool open;
  final bool asTicks;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final solid = Paint()..color = AppTheme.hankoWashi;
    final edge = Paint()..color = AppTheme.hankoEdge;
    final outline = Paint()
      ..color = AppTheme.hankoEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    double end;
    double tailY;
    if (asTicks) {
      for (var i = 0; i < count; i++) {
        final x = i * (HankoReel._tick + HankoReel._gap);
        if (i < watched) {
          canvas.drawRRect(
            RRect.fromLTRBR(x, 0, x + HankoReel._tick, h, const Radius.circular(0.5)),
            solid,
          );
        } else if (i < aired) {
          canvas.drawRect(Rect.fromLTWH(x + 0.5, 0.5, HankoReel._tick - 1, h - 1), outline);
        } else {
          canvas.drawRect(Rect.fromLTWH(x + 1, h - 4, 1, 4), edge);
        }
      }
      end = HankoReel.ticksWidth(count);
      tailY = h - 1; // level with the feet of the short ticks
    } else {
      final lineEnd = math.max(0.0, open ? size.width - HankoReel._tail : size.width);
      final unit = count > 0 ? lineEnd / count : 0.0;
      final mid = h / 2;
      // Keep every state that exists visible, however long the show.
      var xw = watched > 0 ? math.max(watched * unit, 2.0) : 0.0;
      var xa = aired > watched ? math.max(aired * unit, xw + 4) : xw;
      xa = math.min(xa, lineEnd);
      xw = math.min(xw, xa);
      if (xa < lineEnd) {
        canvas.drawRect(Rect.fromLTRB(xa, mid - 0.5, lineEnd, mid + 0.5), edge);
      }
      if (xa > xw) {
        canvas.drawRect(Rect.fromLTRB(xw + 0.5, mid - 1.5, xa - 0.5, mid + 1.5), outline);
      }
      if (xw > 0) {
        canvas.drawRect(Rect.fromLTRB(0, mid - 1, xw, mid + 1), solid);
      }
      end = lineEnd;
      tailY = mid - 0.5;
    }

    if (open) {
      var x = end + (count > 0 ? HankoReel._gap : 0);
      for (var i = 0; i < 3; i++) {
        canvas.drawRect(Rect.fromLTWH(x, tailY, 2, 1), edge);
        x += 4;
      }
    }
  }

  @override
  bool shouldRepaint(_ReelPainter old) =>
      watched != old.watched ||
      aired != old.aired ||
      count != old.count ||
      open != old.open ||
      asTicks != old.asTicks;
}
