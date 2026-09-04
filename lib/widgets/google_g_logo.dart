import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GoogleGLogo — the official 4-color Google "G" rendered from Google's own
// SVG path data (48×48 viewBox). A tiny built-in path parser turns the path
// strings into Flutter Paths, so it stays crisp at any size with no extra deps.
// ─────────────────────────────────────────────────────────────────────────────

class GoogleGLogo extends StatelessWidget {
  final double size;
  const GoogleGLogo({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  // Official Google "G" geometry (48×48 viewBox), one path per colour.
  static const _blue =
      'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z';
  static const _green =
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z';
  static const _yellow =
      'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z';
  static const _red =
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z';

  static const _blueColor = Color(0xFF4285F4);
  static const _greenColor = Color(0xFF34A853);
  static const _yellowColor = Color(0xFFFBBC05);
  static const _redColor = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 48.0;
    canvas.save();
    canvas.scale(scale);

    void draw(String d, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;
      canvas.drawPath(_SvgPath.parse(d), paint);
    }

    draw(_blue, _blueColor);
    draw(_green, _greenColor);
    draw(_yellow, _yellowColor);
    draw(_red, _redColor);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleGPainter old) => false;
}

// ── Minimal SVG path parser ──────────────────────────────────────────────────
// Supports the commands used by the Google G: M m L l H h V v C c S s Z z.
class _SvgPath {
  static final _token = RegExp(
      r'([MmLlHhVvCcSsZz])|(-?\d*\.?\d+(?:[eE][-+]?\d+)?)');

  static Path parse(String d) {
    final path = Path();
    final tokens = <Object>[];
    for (final m in _token.allMatches(d)) {
      if (m.group(1) != null) {
        tokens.add(m.group(1)!);
      } else {
        tokens.add(double.parse(m.group(2)!));
      }
    }

    double cx = 0, cy = 0; // current point
    double sx = 0, sy = 0; // subpath start
    double c2x = 0, c2y = 0; // previous cubic control point (for S/s)
    String? last;
    int i = 0;

    double n() => tokens[i++] as double;
    bool isCubic(String? c) =>
        c == 'C' || c == 'c' || c == 'S' || c == 's';

    while (i < tokens.length) {
      String cmd;
      final t = tokens[i];
      if (t is String) {
        cmd = t;
        i++;
      } else {
        // Implicit repeat of the previous command.
        cmd = last == 'M' ? 'L' : (last == 'm' ? 'l' : last!);
      }

      switch (cmd) {
        case 'M':
          cx = n();
          cy = n();
          path.moveTo(cx, cy);
          sx = cx;
          sy = cy;
          break;
        case 'm':
          cx += n();
          cy += n();
          path.moveTo(cx, cy);
          sx = cx;
          sy = cy;
          break;
        case 'L':
          cx = n();
          cy = n();
          path.lineTo(cx, cy);
          break;
        case 'l':
          cx += n();
          cy += n();
          path.lineTo(cx, cy);
          break;
        case 'H':
          cx = n();
          path.lineTo(cx, cy);
          break;
        case 'h':
          cx += n();
          path.lineTo(cx, cy);
          break;
        case 'V':
          cy = n();
          path.lineTo(cx, cy);
          break;
        case 'v':
          cy += n();
          path.lineTo(cx, cy);
          break;
        case 'C':
          {
            final x1 = n(), y1 = n(), x2 = n(), y2 = n(), x = n(), y = n();
            path.cubicTo(x1, y1, x2, y2, x, y);
            c2x = x2;
            c2y = y2;
            cx = x;
            cy = y;
          }
          break;
        case 'c':
          {
            final x1 = cx + n(), y1 = cy + n();
            final x2 = cx + n(), y2 = cy + n();
            final x = cx + n(), y = cy + n();
            path.cubicTo(x1, y1, x2, y2, x, y);
            c2x = x2;
            c2y = y2;
            cx = x;
            cy = y;
          }
          break;
        case 'S':
          {
            final x1 = isCubic(last) ? 2 * cx - c2x : cx;
            final y1 = isCubic(last) ? 2 * cy - c2y : cy;
            final x2 = n(), y2 = n(), x = n(), y = n();
            path.cubicTo(x1, y1, x2, y2, x, y);
            c2x = x2;
            c2y = y2;
            cx = x;
            cy = y;
          }
          break;
        case 's':
          {
            final x1 = isCubic(last) ? 2 * cx - c2x : cx;
            final y1 = isCubic(last) ? 2 * cy - c2y : cy;
            final x2 = cx + n(), y2 = cy + n();
            final x = cx + n(), y = cy + n();
            path.cubicTo(x1, y1, x2, y2, x, y);
            c2x = x2;
            c2y = y2;
            cx = x;
            cy = y;
          }
          break;
        case 'Z':
        case 'z':
          path.close();
          cx = sx;
          cy = sy;
          break;
      }
      last = cmd;
    }
    return path;
  }
}
