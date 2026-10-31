import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/theme/app_theme.dart';

/// The vertical native-title slip from Hanko's Detail hero: the 題簽 (daisen),
/// the title slip pasted on a Japanese book cover. The title runs top to
/// bottom in columns that step right to left.
///
/// Values come from the `.slip` rules in `design/mockups/looks/hanko.html`,
/// in the font route Shahid chose: native text in the phone's own Japanese
/// font with `locale: Locale('ja')`, never Shippori. A title that fits one
/// column at 17 px is set at 17 px with 0.1 em tracking. A longer one steps
/// down to 13 px and wraps into 19.5 px columns no taller than [maxHeight]
/// (the spec's 41-character case) and never wider than [maxWidth], so the
/// slip stays on the print. Anything still left over ends in a vertical
/// ellipsis.
///
/// Flutter has no vertical text layout, so each glyph is placed by hand:
/// - Kanji and kana stand upright in a 1 em cell, with the OpenType `vert`
///   feature on, which gives small kana their vertical forms where the font
///   has them.
/// - 、。，：；！？…, the ellipses and the dashes use their Unicode vertical
///   presentation forms, which Japanese system fonts carry.
/// - ー, 〜 and brackets turn 90°, as a browser draws them when a font has no
///   vertical form.
/// - Latin words lie on their side, as CSS `text-orientation: mixed` sets
///   them. One or two digits, or "!!", stand upright side by side instead
///   (tate-chu-yoko), as in 第3期.
///
/// Renders nothing when the title is null, empty or has no Japanese (or other
/// CJK) letters: a Latin-only native title such as PERFECT BLUE gets no slip.
class HankoTitleSlip extends StatelessWidget {
  const HankoTitleSlip({
    super.key,
    required this.nativeTitle,
    this.maxHeight = 268,
    this.maxWidth = 188,
  });

  /// AniList's `title.native`.
  final String? nativeTitle;

  /// The tallest the slip may be. 268 fits the spec's 208 by 293 print with
  /// the slip 10 px from its top.
  final double maxHeight;

  /// The widest the slip may be. 188 keeps it 10 px inside that print.
  final double maxWidth;

  /// Whether [nativeTitle] gets a slip at all: it needs at least one
  /// Japanese or other CJK letter.
  static bool shows(String? nativeTitle) =>
      nativeTitle != null && nativeTitle.runes.any(_isCjkLetter);

  @override
  Widget build(BuildContext context) {
    final title = nativeTitle?.trim() ?? '';
    if (!shows(title)) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Native title: $title',
      child: ExcludeSemantics(
        child: _VerticalTitle(
          title: title,
          // The slip lives on a fixed-size print, so large text grows it only
          // so far; past that, long titles wrap and end in an ellipsis.
          scaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.5),
          maxHeight: maxHeight,
          maxWidth: maxWidth,
        ),
      ),
    );
  }
}

class _VerticalTitle extends LeafRenderObjectWidget {
  const _VerticalTitle({
    required this.title,
    required this.scaler,
    required this.maxHeight,
    required this.maxWidth,
  });

  final String title;
  final TextScaler scaler;
  final double maxHeight;
  final double maxWidth;

  @override
  _RenderVerticalTitle createRenderObject(BuildContext context) =>
      _RenderVerticalTitle(title, scaler, maxHeight, maxWidth);

  @override
  void updateRenderObject(BuildContext context, _RenderVerticalTitle renderObject) {
    renderObject
      ..title = title
      ..scaler = scaler
      ..maxHeight = maxHeight
      ..maxWidth = maxWidth;
  }
}

class _RenderVerticalTitle extends RenderBox with RelayoutWhenSystemFontsChangeMixin {
  _RenderVerticalTitle(this._title, this._scaler, this._maxHeight, this._maxWidth);

  String _title;
  set title(String v) {
    if (v == _title) return;
    _title = v;
    markNeedsLayout();
  }

  TextScaler _scaler;
  set scaler(TextScaler v) {
    if (v == _scaler) return;
    _scaler = v;
    markNeedsLayout();
  }

  double _maxHeight;
  set maxHeight(double v) {
    if (v == _maxHeight) return;
    _maxHeight = v;
    markNeedsLayout();
  }

  double _maxWidth;
  set maxWidth(double v) {
    if (v == _maxWidth) return;
    _maxWidth = v;
    markNeedsLayout();
  }

  _SlipLayout? _layout;

  _SlipLayout _compute(BoxConstraints c) => _SlipLayout.compute(
        _title,
        _scaler,
        math.min(_maxHeight, c.maxHeight),
        math.min(_maxWidth, c.maxWidth),
      );

  Size _measure(BoxConstraints c) {
    final layout = _compute(c);
    final size = c.constrain(layout.size);
    layout.dispose();
    return size;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _measure(constraints);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _measure(BoxConstraints(maxHeight: height)).width;

  @override
  double computeMaxIntrinsicWidth(double height) => computeMinIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _measure(BoxConstraints(maxWidth: width)).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  void performLayout() {
    _layout?.dispose();
    final layout = _layout = _compute(constraints);
    size = constraints.constrain(layout.size);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final layout = _layout;
    if (layout == null) return;
    final canvas = context.canvas;
    final box = offset & size;
    // A 1 px ring of 25% sumi keeps the washi slip off light art.
    canvas.drawRRect(
      RRect.fromRectAndRadius(box.inflate(1), const Radius.circular(2)),
      Paint()..color = AppTheme.hankoSumi.withValues(alpha: 0.25),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(1)),
      Paint()..color = AppTheme.hankoWashi,
    );
    // The inner rule, 3 to 4 px inside the edge.
    canvas.drawRect(
      box.deflate(3.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppTheme.hankoSumi.withValues(alpha: 0.42),
    );
    for (var c = 0; c < layout.columns.length; c++) {
      final cx = box.right - layout.pad.right - (c + 0.5) * layout.columnWidth;
      var y = box.top + layout.pad.top;
      for (final cell in layout.columns[c]) {
        cell.paint(canvas, cx, y, layout.em);
        y += cell.advance;
      }
    }
  }

  @override
  void dispose() {
    _layout?.dispose();
    _layout = null;
    super.dispose();
  }
}

enum _Kind { upright, turned, side, combined, space }

class _Cell {
  _Cell(this.kind, this.source, this.painter, this.advance, {this.joined = false});

  final _Kind kind;

  /// The first code point as written, before any vertical-form swap.
  final int source;

  final TextPainter? painter;

  /// Length along the column, tracking included.
  final double advance;

  /// Continues a Latin word that was too long for one column.
  final bool joined;

  void paint(Canvas canvas, double cx, double top, double em) {
    final p = painter;
    if (p == null) return;
    final base = p.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    // A Japanese face draws each glyph in an em box from 0.88 em above the
    // baseline to 0.12 em below it, so its centre is 0.38 em up. Latin text
    // centres on the CSS central baseline, about 0.34 em up.
    switch (kind) {
      case _Kind.upright:
        p.paint(canvas, Offset(cx - p.width / 2, top + em / 2 - (base - 0.38 * em)));
      case _Kind.turned:
        canvas
          ..save()
          ..translate(cx, top + em / 2)
          ..rotate(math.pi / 2);
        p.paint(canvas, Offset(-p.width / 2, -(base - 0.38 * em)));
        canvas.restore();
      case _Kind.combined:
        canvas
          ..save()
          ..translate(cx, top + em / 2);
        if (p.width > em) canvas.scale(em / p.width, 1);
        p.paint(canvas, Offset(-p.width / 2, -(base - 0.36 * em)));
        canvas.restore();
      case _Kind.side:
        canvas
          ..save()
          ..translate(cx, top)
          ..rotate(math.pi / 2);
        p.paint(canvas, Offset(0, -(base - 0.34 * em)));
        canvas.restore();
      case _Kind.space:
        break;
    }
  }
}

class _SlipLayout {
  _SlipLayout(this.size, this.columns, this.columnWidth, this.em, this.pad, this.painters);

  final Size size;
  final List<List<_Cell>> columns;
  final double columnWidth;
  final double em;
  final EdgeInsets pad;
  final List<TextPainter> painters;

  void dispose() {
    for (final p in painters) {
      p.dispose();
    }
  }

  static const _onePad = EdgeInsets.fromLTRB(8, 12, 8, 10);
  static const _longPad = EdgeInsets.fromLTRB(7, 11, 7, 9);

  static _SlipLayout compute(String title, TextScaler scaler, double maxHeight, double maxWidth) {
    // One column at 17 px with 0.1 em tracking, when it fits.
    final painters = <TextPainter>[];
    final em1 = scaler.scale(AppTheme.hankoNativeSize);
    final one = _cells(title, em1, 0.1, double.infinity, painters);
    final oneLength = _length(one);
    if (oneLength <= maxHeight - _onePad.vertical) {
      return _SlipLayout(
        Size(_onePad.horizontal + em1, _onePad.vertical + oneLength),
        [one],
        em1,
        em1,
        _onePad,
        painters,
      );
    }

    // Otherwise 13 px with 0.04 em tracking, in 1.5 em columns.
    final em = scaler.scale(AppTheme.hankoNativeLongSize);
    final columnWidth = em * 1.5;
    final columnLength = maxHeight - _longPad.vertical;
    final cells = _cells(title, em, 0.04, columnLength, painters);
    var columns = _wrap(cells, columnLength);
    final most = math.max(1, ((maxWidth - _longPad.horizontal) / columnWidth).floor());
    if (columns.length > most) {
      columns = columns.sublist(0, most);
      final ellipsis = _cells('…', em, 0.04, columnLength, painters).single;
      final last = columns.last;
      var used = _length(last);
      while (last.isNotEmpty && used + ellipsis.advance > columnLength + 0.01) {
        used -= last.removeLast().advance;
      }
      last.add(ellipsis);
    }
    final height = columns.length > 1
        ? maxHeight
        : _longPad.vertical + _length(columns.isEmpty ? const [] : columns.single);
    return _SlipLayout(
      Size(_longPad.horizontal + columns.length * columnWidth, height),
      columns,
      columnWidth,
      em,
      _longPad,
      painters,
    );
  }

  static double _length(List<_Cell> cells) => cells.fold(0.0, (sum, c) => sum + c.advance);

  /// Splits [title] into cells at [em] with [tracking] (in em). Latin words
  /// longer than [maxRun] are split letter by letter.
  static List<_Cell> _cells(
    String title,
    double em,
    double tracking,
    double maxRun,
    List<TextPainter> painters,
  ) {
    final ls = em * tracking;
    TextPainter tp(String s, {bool vert = false, bool tracked = false}) {
      final p = TextPainter(
        text: TextSpan(
          text: s,
          style: AppTheme.hankoNative(
            fontSize: em,
            letterSpacing: tracked ? ls : 0,
            fontFeatures: vert ? const [FontFeature.enable('vert')] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      painters.add(p);
      return p;
    }

    // 1. Classify each code point. Combining marks ride on the glyph before.
    final glyphs = <(String, int, _Kind)>[];
    for (final c in title.runes) {
      final ch = String.fromCharCode(c);
      if (glyphs.isNotEmpty && (_isCombining(c) || glyphs.last.$1.endsWith('‍'))) {
        final (text, source, kind) = glyphs.removeLast();
        glyphs.add((text + ch, source, kind));
      } else if (_isSpace(c)) {
        glyphs.add((' ', c, _Kind.space));
      } else if (_verticalForms[c] case final v?) {
        glyphs.add((String.fromCharCode(v), c, _Kind.upright));
      } else if (_turned.contains(c)) {
        glyphs.add((ch, c, _Kind.turned));
      } else {
        glyphs.add((ch, c, _isUpright(c) ? _Kind.upright : _Kind.side));
      }
    }

    // 2. Cells: one per upright or turned glyph, one per Latin word or run
    // of spaces, and one upright pair for short numbers and "!!".
    final cells = <_Cell>[];
    var i = 0;
    while (i < glyphs.length) {
      final (text, source, kind) = glyphs[i];
      switch (kind) {
        case _Kind.upright:
          cells.add(_Cell(kind, source, tp(text, vert: true), em + ls));
          i++;
        case _Kind.turned:
          cells.add(_Cell(kind, source, tp(text), em + ls));
          i++;
        case _Kind.space:
          var j = i;
          while (j < glyphs.length && glyphs[j].$3 == _Kind.space) {
            j++;
          }
          cells.add(_Cell(kind, source, null, tp(' ' * (j - i), tracked: true).width));
          i = j;
        case _Kind.side || _Kind.combined:
          var j = i;
          final word = StringBuffer();
          while (j < glyphs.length && glyphs[j].$3 == _Kind.side) {
            word.write(glyphs[j].$1);
            j++;
          }
          final w = word.toString();
          if (_combinable.hasMatch(w)) {
            cells.add(_Cell(_Kind.combined, source, tp(w), em + ls));
          } else {
            final whole = tp(w, tracked: true);
            if (whole.width <= maxRun) {
              cells.add(_Cell(_Kind.side, source, whole, whole.width));
            } else {
              for (var k = i; k < j; k++) {
                final letter = tp(glyphs[k].$1, tracked: true);
                cells.add(_Cell(_Kind.side, glyphs[k].$2, letter, letter.width, joined: k > i));
              }
            }
          }
          i = j;
      }
    }
    return cells;
  }

  /// Greedy column filling with Japanese line-break rules (strict): no column
  /// starts with closing punctuation, small kana or ー, none ends with an
  /// opening bracket, and Latin words stay whole.
  static List<List<_Cell>> _wrap(List<_Cell> cells, double columnLength) {
    final columns = <List<_Cell>>[];
    var start = 0;
    while (start < cells.length) {
      while (start < cells.length && cells[start].kind == _Kind.space) {
        start++;
      }
      if (start >= cells.length) break;
      var used = 0.0;
      var end = start;
      while (end < cells.length && used + cells[end].advance <= columnLength + 0.01) {
        used += cells[end].advance;
        end++;
      }
      if (end == start) {
        end = start + 1; // taller than a column on its own: give it one
      } else if (end < cells.length) {
        var b = end;
        while (b > start + 1 && !_canBreakBefore(cells, b)) {
          b--;
        }
        if (_canBreakBefore(cells, b)) end = b;
      }
      columns.add(cells.sublist(start, end));
      start = end;
    }
    return columns;
  }

  static bool _canBreakBefore(List<_Cell> cells, int i) {
    final next = cells[i];
    final prev = cells[i - 1];
    if (next.kind == _Kind.space || prev.kind == _Kind.space) return true;
    if (next.joined) return false;
    if (_noStart.contains(next.source) || (next.source >= 0x31F0 && next.source <= 0x31FF)) {
      return false;
    }
    return !_noEnd.contains(prev.source);
  }
}

// One or two digits, or ! and ?, set upright side by side (tate-chu-yoko).
final _combinable = RegExp(r'^[0-9!?]{1,2}$');

// Punctuation with a Unicode vertical presentation form.
const _verticalForms = <int, int>{
  0x3001: 0xFE11, // 、
  0x3002: 0xFE12, // 。
  0xFF0C: 0xFE10, // ，
  0xFF1A: 0xFE13, // ：
  0xFF1B: 0xFE14, // ；
  0xFF01: 0xFE15, // ！
  0xFF1F: 0xFE16, // ？
  0x2026: 0xFE19, // …
  0x2025: 0xFE30, // ‥
  0x2014: 0xFE31, // —
  0x2015: 0xFE31, // ―
  0x2013: 0xFE32, // –
};

// Turned 90° in vertical text: the long vowel mark, waves, dashes, brackets.
const _turned = <int>{
  0x30FC, 0xFF70, 0x301C, 0xFF5E, 0xFF0D, 0x2010, 0x2011, // ー ｰ 〜 ～ － ‐ ‑
  0xFF1D, 0xFF1C, 0xFF1E, 0xFF5C, // ＝ ＜ ＞ ｜
  0x3008, 0x3009, 0x300A, 0x300B, 0x300C, 0x300D, 0x300E, 0x300F, // 〈〉《》「」『』
  0x3010, 0x3011, 0x3014, 0x3015, 0x3016, 0x3017, // 【】〔〕〖〗
  0x3018, 0x3019, 0x301A, 0x301B, // 〘〙〚〛
  0xFF08, 0xFF09, 0xFF3B, 0xFF3D, 0xFF5B, 0xFF5D, // （）［］｛｝
};

// May not start a column (strict line breaking).
const _noStart = <int>{
  0x3001, 0x3002, 0xFF0C, 0xFF0E, 0xFF1A, 0xFF1B, 0xFF01, 0xFF1F, // 、。，．：；！？
  0x2026, 0x2025, 0x2014, 0x2015, // … ‥ — ―
  0x3009, 0x300B, 0x300D, 0x300F, 0x3011, 0x3015, 0x3017, 0x3019, 0x301B, // 〉》」』】〕〗〙〛
  0xFF09, 0xFF3D, 0xFF5D, 0x301F, 0x2019, 0x201D, // ）］｝〟’”
  0x30FC, 0xFF70, 0x301C, 0xFF5E, 0x30FB, 0xFF65, // ー ｰ 〜 ～ ・ ･
  0x3005, 0x303B, 0x309D, 0x309E, 0x30FD, 0x30FE, // 々 〻 ゝ ゞ ヽ ヾ
  0x3041, 0x3043, 0x3045, 0x3047, 0x3049, 0x3063, // ぁぃぅぇぉっ
  0x3083, 0x3085, 0x3087, 0x308E, 0x3095, 0x3096, // ゃゅょゎゕゖ
  0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30C3, // ァィゥェォッ
  0x30E3, 0x30E5, 0x30E7, 0x30EE, 0x30F5, 0x30F6, // ャュョヮヵヶ
  0x21, 0x3F, 0x29, 0x5D, 0x7D, 0x2C, 0x2E, 0x3A, 0x3B, // ! ? ) ] } , . : ;
};

// May not end a column.
const _noEnd = <int>{
  0x3008, 0x300A, 0x300C, 0x300E, 0x3010, 0x3014, 0x3016, 0x3018, 0x301A, // 〈《「『【〔〖〘〚
  0xFF08, 0xFF3B, 0xFF5B, 0x301D, 0x2018, 0x201C, // （［｛〝‘“
  0x28, 0x5B, 0x7B, // ( [ {
};

bool _isCjkLetter(int c) =>
    (c >= 0x3040 && c <= 0x30FF) || // hiragana, katakana
    (c >= 0x31F0 && c <= 0x31FF) ||
    (c >= 0x3400 && c <= 0x4DBF) ||
    (c >= 0x4E00 && c <= 0x9FFF) ||
    (c >= 0xF900 && c <= 0xFAFF) ||
    (c >= 0xFF66 && c <= 0xFF9F) || // halfwidth katakana
    (c >= 0xAC00 && c <= 0xD7AF) || // hangul
    (c >= 0x1100 && c <= 0x11FF) ||
    (c >= 0x3130 && c <= 0x318F) ||
    (c >= 0x20000 && c <= 0x3FFFF) ||
    c == 0x3005 ||
    c == 0x3007; // 々 〇

bool _isUpright(int c) =>
    _isCjkLetter(c) ||
    (c >= 0x2460 && c <= 0x24FF) || // ① enclosed alphanumerics
    (c >= 0x25A0 && c <= 0x27BF) || // ○ ☆ ♪: shapes, symbols, dingbats
    (c >= 0x2E80 && c <= 0x2FDF) || // CJK radicals
    (c >= 0x3000 && c <= 0x303F) || // CJK symbols and punctuation
    (c >= 0x3100 && c <= 0x312F) ||
    (c >= 0x3190 && c <= 0x33FF) ||
    (c >= 0xFE10 && c <= 0xFE1F) || // vertical forms
    (c >= 0xFE30 && c <= 0xFE4F) || // CJK compatibility forms
    (c >= 0xFF01 && c <= 0xFF60) || // fullwidth forms
    (c >= 0xFFE0 && c <= 0xFFE6) ||
    (c >= 0x1F000 && c <= 0x1FAFF); // emoji

bool _isSpace(int c) =>
    c == 0x20 || c == 0xA0 || c == 0x09 || c == 0x0A || (c >= 0x2000 && c <= 0x200A) || c == 0x202F;

bool _isCombining(int c) =>
    (c >= 0x0300 && c <= 0x036F) ||
    (c >= 0x1AB0 && c <= 0x1AFF) ||
    (c >= 0x1DC0 && c <= 0x1DFF) ||
    (c >= 0x20D0 && c <= 0x20FF) ||
    (c >= 0x3099 && c <= 0x309A) || // combining dakuten, handakuten
    (c >= 0xFE00 && c <= 0xFE0F) || // variation selectors
    (c >= 0xFE20 && c <= 0xFE2F) ||
    (c >= 0x1F3FB && c <= 0x1F3FF) ||
    (c >= 0xE0100 && c <= 0xE01EF) ||
    c == 0x200D;
