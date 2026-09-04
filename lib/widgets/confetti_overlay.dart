import 'dart:math';
import 'package:flutter/material.dart';

class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key});

  @override
  State<ConfettiOverlay> createState() => ConfettiOverlayState();
}

class ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ConfettiPiece> _pieces = [];
  bool _active = false;
  final _rng = Random();

  static const _colors = [
    Color(0xFFE8624A),
    Color(0xFFCA2868),
    Color(0xFFFFD700),
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..addListener(() {
        if (mounted) setState(() => _updatePieces());
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void launch() {
    _pieces.clear();
    // Spawn 120 pieces from the top
    for (int i = 0; i < 120; i++) {
      _pieces.add(_ConfettiPiece(
        x: _rng.nextDouble(),
        y: -0.05 - _rng.nextDouble() * 0.2,
        vx: (_rng.nextDouble() - 0.5) * 0.008,
        vy: 0.003 + _rng.nextDouble() * 0.007,
        rotation: _rng.nextDouble() * pi * 2,
        rotationSpeed: (_rng.nextDouble() - 0.5) * 0.15,
        color: _colors[_rng.nextInt(_colors.length)],
        size: 6 + _rng.nextDouble() * 8,
        shape: _rng.nextInt(3), // 0=rect, 1=circle, 2=triangle
        wobble: _rng.nextDouble() * pi * 2,
        wobbleSpeed: 0.05 + _rng.nextDouble() * 0.05,
      ));
    }
    setState(() => _active = true);
    _controller.forward(from: 0);
  }

  void _updatePieces() {
    for (final p in _pieces) {
      p.x += p.vx + sin(p.wobble) * 0.002;
      p.y += p.vy;
      p.rotation += p.rotationSpeed;
      p.wobble += p.wobbleSpeed;
      p.vy += 0.00008; // gravity
    }
    _pieces.removeWhere((p) => p.y > 1.1);
    if (_pieces.isEmpty) {
      _active = false;
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        painter: _ConfettiPainter(_pieces),
        size: Size.infinite,
      ),
    );
  }
}

class _ConfettiPiece {
  double x, y, vx, vy, rotation, rotationSpeed, size, wobble, wobbleSpeed;
  final Color color;
  final int shape;

  _ConfettiPiece({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.rotation,
    required this.rotationSpeed,
    required this.color,
    required this.size,
    required this.shape,
    required this.wobble,
    required this.wobbleSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;

  _ConfettiPainter(this.pieces);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in pieces) {
      final paint = Paint()..color = p.color;
      final cx = p.x * size.width;
      final cy = p.y * size.height;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(p.rotation);

      switch (p.shape) {
        case 0: // Rectangle
          canvas.drawRect(
            Rect.fromCenter(
                center: Offset.zero, width: p.size, height: p.size * 0.5),
            paint,
          );
          break;
        case 1: // Circle
          canvas.drawCircle(Offset.zero, p.size * 0.4, paint);
          break;
        case 2: // Triangle
          final path = Path()
            ..moveTo(0, -p.size * 0.5)
            ..lineTo(p.size * 0.5, p.size * 0.5)
            ..lineTo(-p.size * 0.5, p.size * 0.5)
            ..close();
          canvas.drawPath(path, paint);
          break;
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}
