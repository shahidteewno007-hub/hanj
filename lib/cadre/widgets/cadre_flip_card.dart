import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Flips [back] over to [front] as [t] runs 0 to 1.
///
/// Same Y-axis rotation the card unlock overlay already uses, pulled into its
/// own widget so the Clash reveal and any future reveal share one behaviour.
/// The front face is counter-rotated past the halfway point so it doesn't
/// render mirrored.
class CadreFlipCard extends StatelessWidget {
  final double t;
  final Widget front;
  final Widget back;

  const CadreFlipCard({
    super.key,
    required this.t,
    required this.front,
    required this.back,
  });

  @override
  Widget build(BuildContext context) {
    final angle = t.clamp(0.0, 1.0) * math.pi;
    final showFront = angle > math.pi / 2;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(angle),
      child: showFront
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(math.pi),
              child: front,
            )
          : back,
    );
  }
}
