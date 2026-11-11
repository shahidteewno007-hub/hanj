import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'hanko_badge_emblems.dart';

/// Whether a [HankoBadge] is yours yet. There are no progress states
/// (decision a): a badge that filled as you went would be a meter, and the
/// record shows the fact, not the meter. Counts are said in words instead.
enum HankoBadgeState {
  /// Pressed in ink, carved for its tier.
  earned,

  /// Not yet earned: the outline dashed, as on the seal's "not rated yet",
  /// with the emblem in edge on the badge's own opaque face.
  notYet,
}

/// An achievement's badge: one of Hanj's leisure seals (r9, "Leisure seals").
///
/// In East Asian art a painting carries the artist's name seal, and beside
/// it smaller "leisure seals", carved in many shapes, that say something
/// about the artist. Your coral monogram is the name seal; badges are the
/// leisure seals. So a badge is a seal pressed in one ink, never coral:
/// coral means your own verdicts, and a badge records something you did.
///
/// Three things vary, one meaning each, so the badge reads without colour:
/// - the outline is the family ([HankoBadgeFamily]);
/// - the emblem is the achievement ([id], from `hanko_badge_emblems.dart`);
/// - the carving is the [tier], by the effort it took: I an outline (a
///   first), II a double rule (a habit; at 24 dp and under, where two rules
///   1 dp apart blur into one, a single heavy rim), III a solid face with the
///   emblem cut out of it (a feat), IV the same with a line cut through the
///   solid (the end of a long ladder).
///
/// The ink is washi on sumi, or sumi on washi paper ([onPaper]); [ink]
/// overrides it (Profile's row icon is in the rows' stone). Every badge has
/// an opaque face in the page's colour, so covers never show through it and
/// a knockout is painted rather than cut. A badge is a graphic: it doesn't
/// grow with the text-size setting.
///
/// Two optical cuts: at 24 dp and under the small cut (a 16-unit grid), above
/// it the large one (32 units). Both put every edge on whole device pixels
/// at 20, 24, 32 and 48 dp on the CPH2573 (DPR 4).
///
/// A badge is never a button. Where one gets a tap of its own, its 48 dp
/// target and `button: true` go on the node a screen reader lands on, with
/// this badge inside it under [ExcludeSemantics] (CLAUDE.md).
class HankoBadge extends StatelessWidget {
  const HankoBadge({
    super.key,
    required this.id,
    this.tier = 1,
    this.size = 48,
    this.state = HankoBadgeState.earned,
    this.onPaper = false,
    this.ink,
    this.keyline = false,
    this.number,
    required this.semanticLabel,
  }) : assert(tier >= 1 && tier <= 4);

  /// The achievement's catalogue id, such as "finished" or "top9".
  final String id;

  /// The carving, 1 to 4 (I to IV). The catalogue sets it per step.
  final int tier;

  /// The badge's side. 24 and under draws the small cut.
  final double size;

  final HankoBadgeState state;

  /// Sumi ink on washi, for printed things (Print Room rule 3): the stamp
  /// book's day-one card, the unlock slip, share prints.
  final bool onPaper;

  /// Overrides the ink of an earned badge.
  final Color? ink;

  /// A 2 dp ring in the page's colour (sumi, or the paper's washi) painted
  /// outside the badge, as the seal's is, to keep it clear of art: on coral
  /// a washi face would melt in at 2.72:1. Outside the box, so it changes
  /// no layout.
  final bool keyline;

  /// Founder's edition number, "1" of the first fifty.
  final int? number;

  /// What a screen reader says, such as "Badge: 100 finished, step 4 of 6"
  /// or "Badge, not yet: Every genre". It names the state in words.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final emblem = hankoBadgeEmblems[id];
    assert(emblem != null, 'No badge emblem for "$id"');
    return Semantics(
      container: true,
      image: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: emblem == null
              ? null
              : CustomPaint(
                  painter: _BadgePainter(
                    id: id,
                    emblem: emblem,
                    tier: tier,
                    state: state,
                    onPaper: onPaper,
                    ink: ink,
                    keyline: keyline,
                    number: number,
                  ),
                ),
        ),
      ),
    );
  }
}

/// A badge pressed across a picture's lower-right corner: the corner form
/// of Profile's monogram (decision c).
///
/// 24 dp in the small cut, 6 dp past both edges, with the keyline on.
/// Bottom-right is where Print Room presses your seal on a print; the top
/// corners read as notification counts. At 6 dp past, the stamp covers 8% of
/// a 64 dp picture, a corner of clothes or background rather than a face,
/// and leaves 8 dp to a name beside it. The badge is painted outside
/// [child]'s box, so this takes exactly [child]'s size.
///
/// Founder never goes here (decision f): a number on an avatar's corner is
/// the unread-count badge.
class HankoBadgeCorner extends StatelessWidget {
  const HankoBadgeCorner({
    super.key,
    required this.id,
    required this.tier,
    required this.semanticLabel,
    required this.child,
  });

  static const double size = 24;
  static const double overhang = 6;

  /// The badge's catalogue id, tier and screen-reader label, as on
  /// [HankoBadge].
  final String id;
  final int tier;
  final String semanticLabel;

  /// The picture: Profile's 64 dp monogram.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -overhang,
          bottom: -overhang,
          child: HankoBadge(
            id: id,
            tier: tier,
            size: size,
            keyline: true,
            semanticLabel: semanticLabel,
          ),
        ),
      ],
    );
  }
}

// The small cut is drawn at 24 dp and under; above it, the large cut. At
// 24 the large cut's thin parts close up and its double rule turns grey; at
// 32 the small cut looks coarse.
const double _smallCutMax = 24;

// The carving, in grid units, for each cut: rim widths, the double rule's
// gap and inner rule, where IV's line is cut and how wide, and the not-yet
// dashes.
class _Cut {
  const _Cut({
    required this.grid,
    required this.rim,
    required this.rimII,
    required this.gap,
    required this.inner,
    required this.cutAt,
  });

  final double grid;
  final double rim;

  /// The small cut's single heavy rim for II; the large cut draws two rules.
  final double? rimII;
  final double gap;
  final double inner;
  final double cutAt;

  static const double cutWidth = 0.75;

  static const small =
      _Cut(grid: 16, rim: 1.25, rimII: 2.1, gap: 0, inner: 0, cutAt: 1.6);
  static const large =
      _Cut(grid: 32, rim: 1.5, rimII: null, gap: 1.25, inner: 0.75, cutAt: 2.25);
}

class _BadgePainter extends CustomPainter {
  _BadgePainter({
    required this.id,
    required this.emblem,
    required this.tier,
    required this.state,
    required this.onPaper,
    required this.ink,
    required this.keyline,
    required this.number,
  }) : super(
          // Founder's figures are text: repaint when a font arrives (Jost
          // comes through google_fonts after the first frame).
          repaint: emblem.large.any((s) => s is HankoLabel)
              ? PaintingBinding.instance.systemFonts
              : null,
        );

  final String id;
  final HankoEmblem emblem;
  final int tier;
  final HankoBadgeState state;
  final bool onPaper;
  final Color? ink;
  final bool keyline;
  final int? number;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final geometry = _Geometry.of(id, emblem, side, tier, state);
    final scale = side / geometry.grid;
    final k = 1 / scale; // one dp in grid units
    final ground = onPaper ? AppTheme.hankoWashi : AppTheme.hankoSumi;
    final inked = ink ?? (onPaper ? AppTheme.hankoSumi : AppTheme.hankoWashi);

    canvas.save();
    canvas.scale(scale);
    if (keyline) {
      // Stroked 4 dp on the outline, half of it under the face: 2 dp out.
      canvas.drawPath(
        geometry.face,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * k
          ..strokeJoin = StrokeJoin.round
          ..color = ground,
      );
    }
    // What the emblem's own shapes are painted in, and what its knockouts
    // are: in relief the emblem takes ink; cut out of a solid face (III and
    // IV) it shows the face's colour, and its knockouts take the ink back.
    final Color shapes;
    final Color erased;
    switch (state) {
      case HankoBadgeState.earned when tier <= 2:
        canvas.drawPath(geometry.face, Paint()..color = ground);
        canvas.drawPath(geometry.rules!, Paint()..color = inked);
        shapes = inked;
        erased = ground;
      case HankoBadgeState.earned:
        canvas.drawPath(geometry.face, Paint()..color = inked);
        final cut = geometry.cut;
        if (cut != null) canvas.drawPath(cut, Paint()..color = ground);
        shapes = ground;
        erased = inked;
      case HankoBadgeState.notYet:
        canvas.drawPath(geometry.face, Paint()..color = ground);
        canvas.drawPath(
          geometry.dashes!,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = k
            ..strokeCap = geometry.dashCap
            ..color = onPaper ? AppTheme.hankoPaperInk : AppTheme.hankoStoneHi,
        );
        shapes = AppTheme.hankoEdge;
        erased = ground;
    }
    for (final (path, erase) in geometry.runs) {
      canvas.drawPath(path, Paint()..color = erase ? erased : shapes);
    }
    canvas.restore();

    // Text in dp, not scaled, so it's set at its real size.
    for (final label in geometry.labels) {
      final text = label.text ?? number?.toString();
      if (text == null) continue;
      final painter = _Labels.of(text,
          serif: label.text == null, fontSize: label.size * scale, color: shapes);
      final baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      painter.paint(
          canvas, Offset(label.x * scale - painter.width / 2, label.y * scale - baseline));
    }
  }

  @override
  bool shouldRepaint(_BadgePainter old) =>
      id != old.id ||
      tier != old.tier ||
      state != old.state ||
      onPaper != old.onPaper ||
      ink != old.ink ||
      keyline != old.keyline ||
      number != old.number;
}

/// A badge's paths, in grid units, built the first time a badge of that
/// emblem, size, tier and state is painted and kept: painting is then a
/// scale and a handful of drawPath calls (the face, its rules or cut, and one
/// path per run of the emblem's shapes, since knockouts must paint in order).
/// Nothing needs a layer, a mask or Path.combine.
class _Geometry {
  _Geometry({
    required this.grid,
    required this.face,
    required this.rules,
    required this.cut,
    required this.dashes,
    required this.dashCap,
    required this.runs,
    required this.labels,
  });

  final double grid;
  final Path face;
  final Path? rules;
  final Path? cut;
  final Path? dashes;
  final StrokeCap dashCap;
  final List<(Path, bool)> runs;
  final List<HankoLabel> labels;

  static final Map<String, _Geometry> _cache = {};

  static _Geometry of(
      String id, HankoEmblem emblem, double side, int tier, HankoBadgeState state) {
    final carving = state == HankoBadgeState.earned ? tier : 0;
    return _cache['$id $side $carving'] ??= _build(emblem, side, carving);
  }

  static _Geometry _build(HankoEmblem emblem, double side, int tier) {
    final small = side <= _smallCutMax;
    final c = small ? _Cut.small : _Cut.large;
    final grid = c.grid;
    final k = grid / side; // one dp in grid units
    final radius = 2 * k; // Hanko's 2 dp corners
    final family = emblem.family;
    Path outline(double inset) =>
        _rounded(_outline(family, grid, inset), math.max(0, radius - inset));

    final face = outline(0);
    Path? rules;
    Path? cut;
    Path? dashes;
    var dashCap = StrokeCap.butt;
    switch (tier) {
      case 0:
        (dashes, dashCap) = _dashes(_outline(family, grid, 0.5 * k), 3 * k);
      case 1:
        rules = _evenOdd([face, outline(c.rim)]);
      case 2:
        final rimII = c.rimII;
        rules = rimII != null
            ? _evenOdd([face, outline(rimII)])
            : _evenOdd([
                face,
                outline(c.rim),
                outline(c.rim + c.gap),
                outline(c.rim + c.gap + c.inner),
              ]);
      case 4:
        cut = _evenOdd([outline(c.cutAt), outline(c.cutAt + _Cut.cutWidth)]);
    }

    final runs = <(Path, bool)>[];
    final labels = <HankoLabel>[];
    for (final shape in small ? emblem.small : emblem.large) {
      if (shape is HankoLabel) {
        labels.add(shape);
        continue;
      }
      if (runs.isEmpty || runs.last.$2 != shape.erase) runs.add((Path(), shape.erase));
      _addShape(runs.last.$1, shape);
    }
    return _Geometry(
      grid: grid,
      face: face,
      rules: rules,
      cut: cut,
      dashes: dashes,
      dashCap: dashCap,
      runs: runs,
      labels: labels,
    );
  }
}

// ── The outlines (badge-builder.js `sil`) ────────────────────────────────

const double _notch = 0.17; // the ticket's notch radius, of the side
const double _bevel = 0.12; // the plate's bevel: larger reads as a stop sign

/// The family's outline on a [grid], moved [inset] units in. Clockwise.
List<Offset> _outline(HankoBadgeFamily family, double grid, double inset) {
  final g = grid, d = inset, q = g / 8;
  switch (family) {
    case HankoBadgeFamily.milestones:
      return _rect(d, d, g - 2 * d, g - 2 * d);
    case HankoBadgeFamily.taste:
      return _rect(d, q + d, g - 2 * d, g - 2 * q - 2 * d);
    case HankoBadgeFamily.range:
      final c = g / 2, h = g / 2 - d * math.sqrt2;
      return [Offset(c, c - h), Offset(c + h, c), Offset(c, c + h), Offset(c - h, c)];
    case HankoBadgeFamily.stayingWithIt:
      return _notched(d, d, g - d, g - d, g, g * _notch + d);
    case HankoBadgeFamily.yourPicks:
      return d == 0 ? _registered(g) : _inset(_registered(g), d);
    case HankoBadgeFamily.founder:
      final c = g * _bevel - d * (2 - math.sqrt2), a = d, b = g - d;
      return [
        Offset(a + c, a), Offset(b - c, a), Offset(b, a + c), Offset(b, b - c),
        Offset(b - c, b), Offset(a + c, b), Offset(a, b - c), Offset(a, a + c),
      ];
  }
}

List<Offset> _rect(double x, double y, double w, double h) =>
    [Offset(x, y), Offset(x + w, y), Offset(x + w, y + h), Offset(x, y + h)];

/// The registered seal: a V cut into the middle of each side.
List<Offset> _registered(double g) {
  final w = g * 0.24, n = g * 0.085, a = g / 2 - w / 2, b = g / 2 + w / 2, m = g / 2;
  return [
    Offset.zero, Offset(a, 0), Offset(m, n), Offset(b, 0),
    Offset(g, 0), Offset(g, a), Offset(g - n, m), Offset(g, b),
    Offset(g, g), Offset(b, g), Offset(m, g - n), Offset(a, g),
    Offset(0, g), Offset(0, b), Offset(n, m), Offset(0, a),
  ];
}

/// The ticket: the box from (x0, y0) to (x1, y1) with concave notches of
/// [radius] centred on the corners of the [grid] square, six steps an arc.
List<Offset> _notched(
    double x0, double y0, double x1, double y1, double grid, double radius) {
  const steps = 6;
  final out = <Offset>[];
  double h(double d) => math.sqrt(math.max(0, radius * radius - d * d));
  void arc(double cx, double cy, Offset from, Offset to) {
    final a0 = math.atan2(from.dy - cy, from.dx - cx);
    var da = math.atan2(to.dy - cy, to.dx - cx) - a0;
    while (da > math.pi) {
      da -= 2 * math.pi;
    }
    while (da < -math.pi) {
      da += 2 * math.pi;
    }
    for (var i = 0; i <= steps; i++) {
      final a = a0 + da * i / steps;
      out.add(Offset(cx + radius * math.cos(a), cy + radius * math.sin(a)));
    }
  }

  final g = grid;
  arc(0, 0, Offset(x0, h(x0)), Offset(h(y0), y0));
  arc(g, 0, Offset(g - h(y0), y0), Offset(x1, h(g - x1)));
  arc(g, g, Offset(x1, g - h(g - x1)), Offset(g - h(g - y1), y1));
  arc(0, g, Offset(h(g - y1), y1), Offset(x0, g - h(x0)));
  return out;
}

/// Moves every edge of a clockwise polygon [d] inward (outward if
/// negative), mitring the corners.
List<Offset> _inset(List<Offset> pts, double d) {
  final n = pts.length;
  Offset normal(Offset p, Offset q) {
    final e = q - p;
    return Offset(-e.dy, e.dx) / e.distance;
  }

  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final a = pts[(i - 1 + n) % n], b = pts[i], c = pts[(i + 1) % n];
    final n1 = normal(a, b), n2 = normal(b, c);
    final p1 = a + n1 * d, e1 = b - a;
    final p2 = b + n2 * d, e2 = c - b;
    final den = e1.dx * e2.dy - e1.dy * e2.dx;
    if (den.abs() < 1e-9) {
      out.add(b + n1 * d);
      continue;
    }
    final t = ((p2.dx - p1.dx) * e2.dy - (p2.dy - p1.dy) * e2.dx) / den;
    out.add(p1 + e1 * t);
  }
  return out;
}

/// A clockwise outline with its convex corners rounded to [radius]; concave
/// ones (the ticket's notches, the V cuts) stay sharp.
Path _rounded(List<Offset> pts, double radius) {
  final path = Path();
  if (radius <= 0.01) return path..addPolygon(pts, true);
  final n = pts.length;
  final into = <Offset>[], out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final v = pts[i], a = pts[(i - 1 + n) % n] - v, b = pts[(i + 1) % n] - v;
    final la = a.distance, lb = b.distance;
    // A clockwise outline turns right at a convex corner.
    if (la < 1e-6 || lb < 1e-6 || a.dx * b.dy - a.dy * b.dx > 0) {
      into.add(v);
      out.add(v);
      continue;
    }
    final cos = ((a.dx * b.dx + a.dy * b.dy) / (la * lb)).clamp(-1.0, 1.0);
    final t = math.min(radius / math.tan(math.acos(cos) / 2), math.min(la / 2, lb / 2));
    into.add(v + a * (t / la));
    out.add(v + b * (t / lb));
  }
  path.moveTo(out[n - 1].dx, out[n - 1].dy);
  for (var i = 0; i < n; i++) {
    path.lineTo(into[i].dx, into[i].dy);
    if (into[i] != out[i]) {
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, out[i].dx, out[i].dy);
    }
  }
  return path..close();
}

Path _evenOdd(List<Path> contours) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final c in contours) {
    path.addPath(c, Offset.zero);
  }
  return path;
}

/// The not-yet outline: 3 dp dashes with a dash in every corner, as on the
/// seal's "not rated yet". The ticket's curved outline is walked instead,
/// in even steps.
(Path, StrokeCap) _dashes(List<Offset> pts, double dash) {
  final path = Path();
  final n = pts.length;
  var crowded = false;
  for (var i = 1; i < n; i++) {
    if ((pts[i] - pts[i - 1]).distance < dash * 0.6) crowded = true;
  }
  if (n <= 20 && !(crowded && n > 12)) {
    for (var i = 0; i < n; i++) {
      final a = pts[i], b = pts[(i + 1) % n], length = (b - a).distance;
      if (length < dash * 1.2) {
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
        continue;
      }
      final count = math.max(2, ((length + dash) / (2 * dash)).round());
      final gap = (length - count * dash) / (count - 1);
      final u = (b - a) / length;
      for (var j = 0; j < count; j++) {
        final s = j * (dash + gap), e = math.min(length, s + dash);
        final p = a + u * s, q = a + u * e;
        path
          ..moveTo(p.dx, p.dy)
          ..lineTo(q.dx, q.dy);
      }
    }
    return (path, StrokeCap.square);
  }
  final starts = <double>[];
  var total = 0.0;
  for (var i = 0; i < n; i++) {
    starts.add(total);
    total += (pts[(i + 1) % n] - pts[i]).distance;
  }
  Offset at(double s) {
    for (var i = 0; i < n; i++) {
      final a = pts[i], b = pts[(i + 1) % n], l = (b - a).distance;
      if (s <= starts[i] + l) return Offset.lerp(a, b, l > 0 ? (s - starts[i]) / l : 0)!;
    }
    return pts[0];
  }

  final count = math.max(4, (total / (2 * dash)).round());
  final step = total / count;
  for (var j = 0; j < count; j++) {
    final s0 = j * step;
    final p = at(s0);
    path.moveTo(p.dx, p.dy);
    for (var i = 1; i <= 4; i++) {
      final q = at(s0 + dash * i / 4);
      path.lineTo(q.dx, q.dy);
    }
  }
  return (path, StrokeCap.butt);
}

// ── The emblem's shapes ─────────────────────────────────────────────────

/// Adds [shape] to [path], which fills non-zero: every shape goes in
/// clockwise and every ring's hole counter-clockwise, so shapes in one run
/// join and holes stay open.
void _addShape(Path path, HankoEmblemShape shape) {
  switch (shape) {
    case HankoRect(:final x, :final y, :final w, :final h, :final turn):
      _addPolygon(path, _turned(_rect(x, y, w, h), x + w / 2, y + h / 2, turn));
    case HankoRectRing(:final x, :final y, :final w, :final h, :final t, :final turn):
      final cx = x + w / 2, cy = y + h / 2;
      _addPolygon(path, _turned(_rect(x, y, w, h), cx, cy, turn));
      _addPolygon(path, _turned(_rect(x + t, y + t, w - 2 * t, h - 2 * t), cx, cy, turn),
          hole: true);
    case HankoPolygon(:final points, :final grow):
      final pts = [
        for (var i = 0; i + 1 < points.length; i += 2) Offset(points[i], points[i + 1]),
      ];
      _addPolygon(path, grow == 0 ? pts : _inset(pts, -grow));
    case HankoBar(:final x1, :final y1, :final x2, :final y2, :final w):
      final along = Offset(x2 - x1, y2 - y1);
      final side = Offset(-along.dy, along.dx) / along.distance * (w / 2);
      final a = Offset(x1, y1), b = Offset(x2, y2);
      _addPolygon(path, [a + side, b + side, b - side, a - side]);
    case HankoLozenge(:final cx, :final cy, :final h):
      _addPolygon(path, _lozenge(cx, cy, h));
    case HankoLozengeRing(:final cx, :final cy, :final h, :final t):
      _addPolygon(path, _lozenge(cx, cy, h));
      _addPolygon(path, _lozenge(cx, cy, h - t * math.sqrt2), hole: true);
    case HankoCircle(:final cx, :final cy, :final r):
      // addOval winds clockwise, as the polygons do.
      path.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    case HankoLabel():
      break; // painted as text
  }
}

List<Offset> _lozenge(double cx, double cy, double h) =>
    [Offset(cx, cy - h), Offset(cx + h, cy), Offset(cx, cy + h), Offset(cx - h, cy)];

List<Offset> _turned(List<Offset> pts, double cx, double cy, double degrees) {
  if (degrees == 0) return pts;
  final r = degrees * math.pi / 180, c = math.cos(r), s = math.sin(r);
  return [
    for (final p in pts)
      Offset(cx + (p.dx - cx) * c - (p.dy - cy) * s, cy + (p.dx - cx) * s + (p.dy - cy) * c),
  ];
}

void _addPolygon(Path path, List<Offset> pts, {bool hole = false}) {
  var area = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i], b = pts[(i + 1) % pts.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  // Positive is clockwise on screen (y down).
  path.addPolygon((area > 0) != hole ? pts : pts.reversed.toList(), true);
}

/// Founder's figures, laid out once per text, size and colour. They're
/// dropped when the system's fonts change, so a figure first laid out
/// before its font arrived is set again.
class _Labels {
  static final Map<String, TextPainter> _cache = {};
  static bool _watching = false;

  static TextPainter of(String text,
      {required bool serif, required double fontSize, required Color color}) {
    if (!_watching) {
      _watching = true;
      PaintingBinding.instance.systemFonts.addListener(() {
        for (final painter in _cache.values) {
          painter.dispose();
        }
        _cache.clear();
      });
    }
    return _cache.putIfAbsent(
      '$text $serif $fontSize ${color.toARGB32()}',
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: serif
              ? AppTheme.hankoSerif(fontSize: fontSize, color: color)
              : AppTheme.hankoSans(
                  fontSize: fontSize, weight: FontWeight.w500, color: color),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(),
    );
  }
}
