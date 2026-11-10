import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A sheet of washi paper with its faint fibre grain (Print Room P3,
/// DESIGN.md §9.3 rule 4): paper is for printed things. The Achievements
/// page prints your record on it, the record slip in an achievement's sheet
/// and day one's "Your record so far".
///
/// The paper and the grain are copied from Ranking Cards' private `_Paper`
/// and `_PaperGrainPainter` (ranking_cards.dart, P3), without the card's
/// masthead and foot, so the two look like one stock. Ranking Cards keeps
/// its own copy untouched (question A-10, Shahid 2026-11-10: as
/// recommended), so a change here can never move a saved card's pixels.
///
/// It has 2 px corners, as every Hanko object, and lies on the page with a
/// print's one rectangle shadow (never a MaskFilter blur, PERF.md S2-2). The
/// grain is painted once into its own layer, under everything, so nothing
/// laid on the paper repaints it. Type on it is sumi ([ink]), with the
/// paper ink ([ink2], 6.07:1 on washi) for secondary words: stone would be
/// 2.21:1.
class HankoPaper extends StatelessWidget {
  const HankoPaper({super.key, required this.child});

  /// What's printed on the paper. The paper takes its size, plus [pad].
  final Widget child;

  /// The margin inside the paper, as P3's cards have it.
  static const double pad = 18;

  static const Color ink = AppTheme.hankoSumi;
  static const Color ink2 = AppTheme.hankoPaperInk;

  /// A print's shadow on paper: P3's warm one. P1's are black, made for
  /// colour fields, and lie on washi like soot.
  static const List<BoxShadow> printShadow = [
    BoxShadow(
        color: Color(0x8C281E14),
        offset: Offset(0, 8),
        blurRadius: 16,
        spreadRadius: -6),
    BoxShadow(color: Color(0x4D281E14), offset: Offset(0, 2), blurRadius: 4),
  ];

  static const _corners = BorderRadius.all(Radius.circular(AppTheme.hankoRadius));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppTheme.hankoWashi,
        borderRadius: _corners,
        boxShadow: AppTheme.hankoPrintShadow,
      ),
      child: ClipRRect(
        borderRadius: _corners,
        child: Stack(
          children: [
            // Its own layer, so a cover arriving on the paper doesn't draw
            // the grain again.
            const Positioned.fill(
              child: RepaintBoundary(
                  child: CustomPaint(painter: HankoPaperGrainPainter())),
            ),
            Padding(padding: const EdgeInsets.all(pad), child: child),
          ],
        ),
      ),
    );
  }
}

/// The paper's fibre grain (P3, question 163), drawn rather than shipped as
/// an asset: short fibres lying mostly along the sheet, a few longer,
/// broader streaks and fine specks, in a warm paper ink at 2 to 9%, with
/// light flecks among them. They sit at fixed places (one seed), so a sheet
/// looks the same on every phone, and their number follows the sheet's
/// area, so a small slip is as fine as a full card. Six draw calls.
///
/// Copied from `_PaperGrainPainter` in ranking_cards.dart, which stays as
/// it is.
class HankoPaperGrainPainter extends CustomPainter {
  const HankoPaperGrainPainter();

  static const Color _fibre = Color(0xFF6B5E4C);

  @override
  void paint(Canvas canvas, Size size) {
    var seed = 20261105;
    double next() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed / 0x7fffffff;
    }

    final area = size.width * size.height;
    // Fibres as pairs of points (PointMode.lines), within about 10° of the
    // sheet's grain, in three strengths.
    final fine = [<Offset>[], <Offset>[], <Offset>[]];
    for (var i = 0; i < area / 300; i++) {
      final a = Offset(next() * size.width, next() * size.height);
      final length = 3 + 24 * next() * next();
      final turn = (next() - 0.5) * 0.36;
      fine[i % 3]
        ..add(a)
        ..add(a + Offset(math.cos(turn), math.sin(turn)) * length);
    }
    final broad = <Offset>[];
    for (var i = 0; i < area / 4500; i++) {
      final a = Offset(next() * size.width, next() * size.height);
      final length = 18 + 46 * next();
      final turn = (next() - 0.5) * 0.12;
      broad
        ..add(a)
        ..add(a + Offset(math.cos(turn), math.sin(turn)) * length);
    }
    canvas.drawPoints(
        ui.PointMode.lines,
        broad,
        Paint()
          ..color = _fibre.withValues(alpha: 0.025)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round);
    const alphas = [0.035, 0.055, 0.085];
    for (var k = 0; k < 3; k++) {
      canvas.drawPoints(
          ui.PointMode.lines,
          fine[k],
          Paint()
            ..color = _fibre.withValues(alpha: alphas[k])
            ..strokeWidth = 0.55
            ..strokeCap = StrokeCap.round);
    }
    final dark = <Offset>[], light = <Offset>[];
    for (var i = 0; i < area / 90; i++) {
      (i.isEven ? dark : light)
          .add(Offset(next() * size.width, next() * size.height));
    }
    canvas.drawPoints(
        ui.PointMode.points,
        dark,
        Paint()
          ..color = _fibre.withValues(alpha: 0.09)
          ..strokeWidth = 0.8
          ..strokeCap = StrokeCap.round);
    canvas.drawPoints(
        ui.PointMode.points,
        light,
        Paint()
          ..color = const Color(0x66FFFFFF)
          ..strokeWidth = 0.9
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(HankoPaperGrainPainter oldDelegate) => false;
}
