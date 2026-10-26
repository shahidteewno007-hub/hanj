import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import 'hanko_seal.dart';

/// Hanko's rating control: a ruler (物差し, monosashi) from 1 to 10 in half
/// steps, with a small seal as its thumb.
///
/// Values come from the `.ruler` rules and the Rating control entry of the
/// spec card in `design/mockups/looks/hanko.html`, on Hanj's stored scale, 1
/// to 10 (`anime_detail_screen.dart:401`; the mockup draws 0.5 to 10). Whole
/// numbers carry the taller ticks and the figures; when the ruler is too
/// narrow for every figure (the log sheet's), only the even ones show. The
/// thumb is a 16 px seal with its 2 px sumi keyline, coral or shu. A 2 px
/// washi line fills the track up to it. An unrated show gets an empty track
/// and "Not rated" beside the label.
///
/// Drag or tap anywhere in its 48 px height to rate. It snaps to half steps
/// with one haptic tick per step, as the spec card says. Arrow keys, Page Up
/// and Down, Home and End work once it has focus, and screen readers get a
/// slider whose value is in words ("8.5 out of 10", "not rated").
///
/// It only reports. [onChanged] fires on each half step while you drag, so a
/// screen can update just its large seal; [onChangeEnd] fires once when the
/// drag, tap or key press settles, which is the moment to save. It writes
/// nothing itself. While a drag is under way it shows the value under your
/// finger and repaints only itself; afterwards it shows [value] again, so keep
/// [value] in step from [onChanged] or [onChangeEnd].
class HankoRatingRuler extends StatefulWidget {
  const HankoRatingRuler({
    super.key,
    required this.value,
    this.onChanged,
    this.onChangeEnd,
    this.label = 'Your rating',
    this.tone = HankoSealTone.coral,
  });

  /// The rating, or null for not rated. A value off the scale (an imported
  /// rating, D20) is shown clamped to 1–10 and rounded to the nearest half
  /// step; the stored number is the caller's to keep.
  final double? value;

  /// Called on every half step while dragging, and once for a tap or a key.
  final ValueChanged<double>? onChanged;

  /// Called once when a drag, tap or key press settles.
  final ValueChanged<double>? onChangeEnd;

  /// The words above the track, also the slider's name for screen readers.
  /// Null leaves the row empty.
  final String? label;

  /// The thumb's red.
  final HankoSealTone tone;

  /// The ruler's height, which is also its touch height.
  static const double height = 48;

  @override
  State<HankoRatingRuler> createState() => _HankoRatingRulerState();
}

class _HankoRatingRulerState extends State<HankoRatingRuler> {
  final _focus = FocusNode(debugLabel: 'HankoRatingRuler');
  double? _dragging;
  bool _focused = false;

  bool get _enabled => widget.onChanged != null || widget.onChangeEnd != null;

  double? get _shown {
    final v = _dragging ?? widget.value;
    return v == null ? null : ((v * 2).round() / 2).clamp(1.0, 10.0);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  double _valueAt(double dx, double width) {
    const inset = _RulerPainter.inset;
    final t = ((dx - inset) / math.max(1, width - 2 * inset)).clamp(0.0, 1.0);
    return 1 + (t * 18).round() / 2;
  }

  void _step(double v) {
    if (v == _shown) return;
    HapticFeedback.selectionClick();
    setState(() => _dragging = v);
    widget.onChanged?.call(v);
  }

  void _settle(double v) {
    if (v != _shown) {
      HapticFeedback.selectionClick();
      widget.onChanged?.call(v);
    }
    setState(() => _dragging = null);
    widget.onChangeEnd?.call(v);
  }

  void _endDrag() {
    final v = _dragging ?? _shown;
    if (v != null) _settle(v);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_enabled || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final v = _shown;
    final key = event.logicalKey;
    double? next;
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.arrowUp) {
      next = v == null ? 1 : v + 0.5;
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowDown) {
      next = v == null ? null : v - 0.5;
    } else if (key == LogicalKeyboardKey.pageUp) {
      next = v == null ? 1 : v + 1;
    } else if (key == LogicalKeyboardKey.pageDown) {
      next = v == null ? null : v - 1;
    } else if (key == LogicalKeyboardKey.home) {
      next = 1;
    } else if (key == LogicalKeyboardKey.end) {
      next = 10;
    } else {
      return KeyEventResult.ignored;
    }
    if (next != null) _settle(next.clamp(1.0, 10.0));
    return KeyEventResult.handled;
  }

  static String _words(double v) =>
      '${v == v.roundToDouble() ? v.toInt() : v.toStringAsFixed(1)} out of 10';

  @override
  Widget build(BuildContext context) {
    final v = _shown;
    final up = v == null ? 1.0 : (v < 10 ? v + 0.5 : null);
    final down = v == null ? null : (v > 1 ? v - 0.5 : null);
    return Semantics(
      slider: true,
      enabled: _enabled,
      focused: _focused,
      label: widget.label ?? 'Rating',
      value: v == null ? 'not rated' : _words(v),
      increasedValue: up == null ? null : _words(up),
      decreasedValue: down == null ? null : _words(down),
      onIncrease: _enabled && up != null ? () => _settle(up) : null,
      onDecrease: _enabled && down != null ? () => _settle(down) : null,
      child: ExcludeSemantics(
        child: Focus(
          focusNode: _focus,
          canRequestFocus: _enabled,
          onFocusChange: (f) => setState(() => _focused = f),
          onKeyEvent: _onKey,
          child: MouseRegion(
            cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.hasBoundedWidth ? constraints.maxWidth : 320.0;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: _enabled ? (_) => _focus.requestFocus() : null,
                  onTapUp: _enabled ? (d) => _settle(_valueAt(d.localPosition.dx, width)) : null,
                  onHorizontalDragStart:
                      _enabled ? (d) => _step(_valueAt(d.localPosition.dx, width)) : null,
                  onHorizontalDragUpdate:
                      _enabled ? (d) => _step(_valueAt(d.localPosition.dx, width)) : null,
                  onHorizontalDragEnd: _enabled ? (_) => _endDrag() : null,
                  onHorizontalDragCancel: _enabled ? _endDrag : null,
                  child: CustomPaint(
                    size: Size(width, HankoRatingRuler.height),
                    painter: _RulerPainter(
                      value: v,
                      label: widget.label,
                      tone: widget.tone,
                      // The ring is for keyboards; a finger that taps the
                      // ruler gives it focus but shouldn't draw one.
                      focused: _focused &&
                          FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.value,
    required this.label,
    required this.tone,
    required this.focused,
  }) : super(repaint: PaintingBinding.instance.systemFonts);

  /// Track ends sit this far in, so the thumb and its keyline stay inside.
  static const double inset = 10;

  /// Where the rail starts: the label row sits above it.
  static const double railTop = 20;

  final double? value;
  final String? label;
  final HankoSealTone tone;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    const x0 = inset;
    final x1 = size.width - inset;
    double xOf(double v) => x0 + (v - 1) / 9 * (x1 - x0);

    final labelStyle = AppTheme.hankoSans(
      fontSize: AppTheme.hankoLabelSize,
      color: AppTheme.hankoStone,
      height: 1,
    ).copyWith(leadingDistribution: TextLeadingDistribution.even);
    final label = this.label;
    if (label != null) _text(canvas, label, labelStyle, 0, 0, size.width);
    final v = value;
    if (v == null) _text(canvas, 'Not rated', labelStyle, size.width, 0, size.width, alignEnd: true);

    // Ticks: whole numbers 7 px in stone, half steps 4 px in edge.
    for (var i = 0; i <= 18; i++) {
      final whole = i.isEven;
      canvas.drawRect(
        Rect.fromLTWH(xOf(1 + i / 2) - 0.5, railTop + (whole ? 0 : 3), 1, whole ? 7 : 4),
        Paint()..color = whole ? AppTheme.hankoStone : AppTheme.hankoEdge,
      );
    }

    // The track, filled in washi up to the value.
    canvas.drawRect(
      Rect.fromLTRB(x0, railTop + 7, x1, railTop + 9),
      Paint()..color = AppTheme.hankoSumi3,
    );
    if (v != null) {
      canvas.drawRect(
        Rect.fromLTRB(x0, railTop + 7, xOf(v), railTop + 9),
        Paint()..color = AppTheme.hankoWashi,
      );
    }

    // Figures under the whole ticks; only the even ones when they'd crowd.
    final every = (x1 - x0) / 9 >= 28;
    final figureStyle = AppTheme.hankoSans(
      fontSize: AppTheme.hankoDataSmallSize,
      weight: FontWeight.w500,
      color: AppTheme.hankoAsh,
      height: 1,
      tabular: true,
    ).copyWith(leadingDistribution: TextLeadingDistribution.even);
    for (var k = 1; k <= 10; k++) {
      if (every || k.isEven) {
        _text(canvas, '$k', figureStyle, xOf(k.toDouble()), railTop + 15, size.width, centre: true);
      }
    }

    // The thumb: a 16 px seal with its sumi keyline.
    if (v != null) {
      final thumb = Rect.fromCenter(center: Offset(xOf(v), railTop + 8), width: 16, height: 16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          thumb.inflate(AppTheme.hankoKeyline),
          const Radius.circular(AppTheme.hankoRadius + AppTheme.hankoKeyline),
        ),
        Paint()..color = AppTheme.hankoSumi,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(thumb, const Radius.circular(AppTheme.hankoRadius)),
        Paint()..color = tone == HankoSealTone.shu ? AppTheme.hankoShu : AppTheme.hankoCoral,
      );
    }

    // Keyboard focus: a washi ring around the thumb, or around the track.
    if (focused) {
      final ring = v != null
          ? Rect.fromCenter(center: Offset(xOf(v), railTop + 8), width: 16, height: 16).inflate(4.5)
          : Rect.fromLTRB(x0 - 4.5, railTop - 3.5, x1 + 4.5, railTop + 12.5);
      canvas.drawRRect(
        RRect.fromRectAndRadius(ring, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppTheme.hankoWashi,
      );
    }
  }

  void _text(Canvas canvas, String text, TextStyle style, double x, double top, double width,
      {bool centre = false, bool alignEnd = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    var left = centre ? x - tp.width / 2 : (alignEnd ? x - tp.width : x);
    left = left.clamp(0.0, math.max(0.0, width - tp.width));
    tp.paint(canvas, Offset(left, top));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      value != old.value || label != old.label || tone != old.tone || focused != old.focused;
}
