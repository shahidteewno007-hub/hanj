import 'package:flutter/material.dart';

// Declared locally rather than imported from the card, so the frame and the
// card don't import each other. Same values as the Hanj tokens.
const _ember = Color(0xFFF97316);
const _coral = Color(0xFFE8624A);
const _coralDeep = Color(0xFF8A3A2A);
const _coralEdge = Color(0x59E8624A);
const _hairline = Color(0x1AF3EEE7);
const _hairlineDim = Color(0x0DF3EEE7);

/// Card tiers, read off power alone.
///
/// The frame is the only thing that signals tier. No badge, no label \u2014 the
/// power value is already the loud element on the card and a second marker
/// would make both quieter.
enum CadreTier { base, solid, elite, apex }

CadreTier cadreTierFor(int power) {
  if (power >= 90) return CadreTier.apex;
  if (power >= 75) return CadreTier.elite;
  if (power >= 60) return CadreTier.solid;
  return CadreTier.base;
}

/// Draws the tier treatment over a card: an edge, and for the top two tiers,
/// corner brackets set in from it.
class CadreFramePainter extends CustomPainter {
  final CadreTier tier;
  final double radius;
  final bool dimmed;

  const CadreFramePainter({
    required this.tier,
    required this.radius,
    this.dimmed = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = _strokeWidth(w);
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    switch (tier) {
      case CadreTier.apex:
        edge.shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_ember, _coral, _coralDeep],
        ).createShader(rect);
        break;
      case CadreTier.elite:
        edge.color = _coralEdge;
        break;
      case CadreTier.solid:
        edge.color = _hairline;
        break;
      case CadreTier.base:
        edge.color = _hairlineDim;
        break;
    }

    canvas.drawRRect(rrect, edge);

    if (tier == CadreTier.apex || tier == CadreTier.elite) {
      _brackets(canvas, size, w);
    }
  }

  double _strokeWidth(double w) {
    switch (tier) {
      case CadreTier.apex:
        return (w * 0.016).clamp(1.6, 4.0);
      case CadreTier.elite:
        return (w * 0.010).clamp(1.2, 2.6);
      default:
        return (w * 0.006).clamp(0.8, 1.6);
    }
  }

  void _brackets(Canvas canvas, Size size, double w) {
    final inset = w * 0.055;
    final len = w * 0.16;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (w * 0.011).clamp(1.2, 2.8)
      ..color = tier == CadreTier.apex ? _ember : _coralEdge;

    final l = inset;
    final t = inset;
    final r = size.width - inset;
    final b = size.height - inset;

    // Four corner brackets, drawn as open L shapes.
    canvas.drawLine(Offset(l, t + len), Offset(l, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);

    canvas.drawLine(Offset(r - len, t), Offset(r, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);

    canvas.drawLine(Offset(l, b - len), Offset(l, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);

    canvas.drawLine(Offset(r - len, b), Offset(r, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);
  }

  @override
  bool shouldRepaint(CadreFramePainter old) =>
      old.tier != tier || old.radius != radius || old.dimmed != dimmed;
}
