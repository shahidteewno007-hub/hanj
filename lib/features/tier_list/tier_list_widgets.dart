// Tier lists: the pieces every tier-list screen is drawn with.
//
//  - TierPigment: the tier colours. Muted printing inks that sit on sumi,
//    none within 25° of the seal's coral (AppTheme.hankoCoverTint's guard),
//    so a tier never reads as your seal. Each carries the ink its label is
//    printed in, sumi or washi, whichever clears 4.5:1 (checked in
//    test/tier_list_model_test.dart).
//  - CharacterPortrait: a sharp 2:3 print of the character, with a 2 px foot
//    in their anime's cover colour, so a list that mixes shows says which
//    show each face came from.
//  - TierPlate: a tier's name plate.
//  - TierPressable: the one way these screens make something tappable, so
//    tap, keyboard focus and the screen-reader node are the same node
//    (CLAUDE.md's pattern), with a visible focus ring.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/theme/app_theme.dart';
import 'tier_list_model.dart';

/// A tier colour.
class TierPigment {
  const TierPigment(this.name, this.color, {this.ink = AppTheme.hankoSumi});

  /// What the colour picker calls it.
  final String name;
  final Color color;

  /// The label's colour on [color].
  final Color ink;

  static const gold = TierPigment('Gold', Color(0xFFD4A96A));
  static const peony = TierPigment('Peony', Color(0xFFC96E9E));
  static const wisteria = TierPigment('Wisteria', Color(0xFF9D86C8));
  static const sky = TierPigment('Sky', Color(0xFF6A97C2));
  static const teal = TierPigment('Teal', Color(0xFF55A6A6));
  static const bamboo = TierPigment('Bamboo', Color(0xFF74AB7C));
  static const moss = TierPigment('Moss', Color(0xFFAAB662));
  static const ash = TierPigment('Ash', AppTheme.hankoAsh);
  static const sumiInk = TierPigment('Ink', Color(0xFF3A3631), ink: AppTheme.hankoWashi);

  /// Saved lists store an index into this list, so only ever add to its end.
  static const all = <TierPigment>[gold, peony, wisteria, sky, teal, bamboo, moss, ash, sumiInk];

  static TierPigment at(int i) => all[i.clamp(0, all.length - 1)];

  static int indexOf(TierPigment p) => all.indexOf(p);

  /// A top-to-bottom run of [n] pigments: gold first, cooling through the
  /// palette, ash last.
  static List<int> ramp(int n) {
    const order = [0, 1, 2, 3, 4, 5, 6, 7];
    if (n <= 1) return const [0];
    if (n == 2) return const [0, 7];
    if (n == 3) return const [0, 3, 7];
    if (n == 4) return const [0, 1, 3, 7];
    if (n == 5) return const [0, 1, 2, 3, 7];
    if (n == 6) return const [0, 1, 2, 3, 4, 7];
    if (n == 7) return const [0, 1, 2, 3, 4, 5, 7];
    if (n == 8) return order;
    return [for (var i = 0; i < n; i++) i < 8 ? order[i] : 8];
  }
}

/// Up to two initials, for a portrait with no picture.
String tierInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  if (parts.length == 1) return first.toUpperCase();
  return (first + parts.last.characters.first).toUpperCase();
}

/// A character's sharp 2:3 print, with an optional name under it.
///
/// [width] sets the picture; the caption takes the height it needs. On the
/// exported poster pass [exportMode]: no fade-in, so a capture never catches
/// a half-faded face.
class CharacterPortrait extends StatelessWidget {
  const CharacterPortrait({
    super.key,
    required this.character,
    required this.width,
    this.showName = true,
    this.nameLines = 1,
    this.nameSize = 11,
    this.exportMode = false,
  });

  final TierCharacter character;
  final double width;
  final bool showName;
  final int nameLines;
  final double nameSize;
  final bool exportMode;

  @override
  Widget build(BuildContext context) {
    final h = width * 1.5;
    final tint = character.mediaColor == null ? null : Color(character.mediaColor!);
    final url = character.imageUrl;
    final placeholder = Container(
      color: AppTheme.hankoSumi3,
      alignment: Alignment.center,
      child: Text(
        tierInitials(character.name),
        style: AppTheme.hankoSerif(fontSize: width * 0.3, color: AppTheme.hankoStone),
      ),
    );
    final picture = SizedBox(
      width: width,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url == null)
            placeholder
          else
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              fadeInDuration: exportMode ? Duration.zero : const Duration(milliseconds: 180),
              fadeOutDuration: Duration.zero,
              placeholder: (_, _) => placeholder,
              errorWidget: (_, _, _) => placeholder,
            ),
          // The anime's colour as a 2 px foot (sumi edge when it has none).
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2,
            child: ColoredBox(color: tint ?? AppTheme.hankoEdge),
          ),
        ],
      ),
    );
    if (!showName) return picture;
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          picture,
          const SizedBox(height: 4),
          Text(
            character.name,
            maxLines: nameLines,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppTheme.hankoSans(
              fontSize: nameSize,
              weight: FontWeight.w500,
              color: AppTheme.hankoWashi,
              height: 1.15,
            ),
          ),
        ],
      ),
    );
  }
}

/// A tier's name plate: the pigment, with the name printed in its ink.
/// An unnamed tier shows [placeholder] in a fainter ink.
class TierPlate extends StatelessWidget {
  const TierPlate({
    super.key,
    required this.label,
    required this.pigment,
    required this.width,
    this.minHeight = 0,
    this.fontSize = 17,
    this.placeholder = '',
  });

  final String label;
  final TierPigment pigment;
  final double width;
  final double minHeight;
  final double fontSize;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final blank = label.trim().isEmpty;
    final text = blank ? placeholder : label;
    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: minHeight),
      color: pigment.color,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: Alignment.center,
      child: text.isEmpty
          ? null
          : Text(
              text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.hankoSerif(
                fontSize: tierLabelSize(text, fontSize),
                color: blank ? pigment.ink.withValues(alpha: 0.6) : pigment.ink,
                height: 1.1,
              ),
            ),
    );
  }
}

/// Short names print big, as tier lists do ("S", "GOD"); long ones step down
/// so "Multiversal" still fits a phone's plate on one line.
double tierLabelSize(String label, double base) {
  final n = label.trim().length;
  if (n <= 2) return base * 1.45;
  if (n <= 4) return base * 1.15;
  if (n <= 8) return base;
  if (n <= 12) return base * 0.86;
  return base * 0.76;
}

/// The plate's width for these labels at this text size: wide enough for the
/// longest single word, within [min]..[max].
double tierPlateWidth(BuildContext context, Iterable<String> labels,
    {double base = 17, double min = 64, double max = 112}) {
  final scaler = MediaQuery.textScalerOf(context);
  var widest = 0.0;
  for (final l in labels) {
    final size = tierLabelSize(l, base);
    for (final word in l.trim().split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(text: word, style: AppTheme.hankoSerif(fontSize: size)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (tp.width > widest) widest = tp.width;
      tp.dispose();
    }
  }
  return (widest + 14).clamp(min, max);
}

/// Something tappable on these screens: one node for tap, keyboard focus
/// and the screen reader, with a washi ring while it has keyboard focus.
class TierPressable extends StatefulWidget {
  const TierPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.label,
    this.hint,
    this.selected,
    this.focusNode,
    this.customActions,
    this.onLongPress,
    this.ringInset = 0,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? label;
  final String? hint;
  final bool? selected;
  final FocusNode? focusNode;
  final Map<CustomSemanticsAction, VoidCallback>? customActions;

  /// How far inside the child's edge the focus ring sits.
  final double ringInset;

  @override
  State<TierPressable> createState() => _TierPressableState();
}

class _TierPressableState extends State<TierPressable> {
  bool _focused = false;

  // The ring is for keyboard users, as InkWell's own focus highlight is:
  // after a touch, or when a closing sheet hands focus back, it stays off.
  bool get _keyboardMode => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_modeChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_modeChanged);
    super.dispose();
  }

  void _modeChanged(FocusHighlightMode _) {
    if (_focused && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      enabled: widget.onTap != null,
      selected: widget.selected,
      label: widget.label,
      hint: widget.hint,
      customSemanticsActions: widget.customActions,
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onFocusChange: (f) => setState(() => _focused = f),
        splashFactory: NoSplash.splashFactory,
        highlightColor: AppTheme.hankoPressWash,
        hoverColor: AppTheme.hankoPressWash,
        focusColor: Colors.transparent,
        child: ExcludeSemantics(
          excluding: widget.label != null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (_focused && _keyboardMode)
                Positioned.fill(
                  left: widget.ringInset,
                  top: widget.ringInset,
                  right: widget.ringInset,
                  bottom: widget.ringInset,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.hankoWashi, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hanko's main action: washi fill, sumi words.
class TierMainButton extends StatelessWidget {
  const TierMainButton({super.key, required this.label, required this.onTap, this.icon, this.busy = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !busy;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: enabled ? AppTheme.hankoWashi : AppTheme.hankoSumi3,
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoSumi.withValues(alpha: 0.08),
          hoverColor: AppTheme.hankoSumi.withValues(alpha: 0.05),
          focusColor: AppTheme.hankoSumi.withValues(alpha: 0.12),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch, minWidth: AppTheme.hankoTouch),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (busy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.hankoStone),
                      )
                    else if (icon != null)
                      Icon(icon, size: 18, color: enabled ? AppTheme.hankoSumi : AppTheme.hankoAsh),
                    if (busy || icon != null) const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppTheme.hankoSans(
                          fontSize: 15,
                          weight: FontWeight.w600,
                          color: enabled ? AppTheme.hankoSumi : AppTheme.hankoAsh,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A secondary action: an edge outline, washi words.
class TierGhostButton extends StatelessWidget {
  const TierGhostButton({super.key, required this.label, required this.onTap, this.icon, this.dense = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = enabled ? AppTheme.hankoWashi : AppTheme.hankoAsh;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          side: BorderSide(color: enabled ? AppTheme.hankoEdge : AppTheme.hankoHairline),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppTheme.hankoPressWash,
          hoverColor: AppTheme.hankoPressWash,
          focusColor: AppTheme.hankoWashi.withValues(alpha: 0.14),
          child: ExcludeSemantics(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: AppTheme.hankoTouch, minWidth: AppTheme.hankoTouch),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: c),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: AppTheme.hankoSans(fontSize: 14, weight: FontWeight.w500, color: c),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A faint washi dot grid, the texture under the poster and the headers.
class TierDotGrid extends CustomPainter {
  const TierDotGrid({this.step = 14, this.alpha = 0.045});
  final double step;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppTheme.hankoWashi.withValues(alpha: alpha);
    final pts = <Offset>[];
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        pts.add(Offset(x, y));
      }
    }
    // One draw call for the whole grid (the round-six card faces' lesson).
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList([for (final p in pts) ...[p.dx, p.dy]]),
      paint
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(TierDotGrid old) => old.step != step || old.alpha != alpha;
}

/// A small uppercase label, letter-spaced, in Jost with tabular figures.
class TierEyebrow extends StatelessWidget {
  const TierEyebrow(this.text, {super.key, this.color = AppTheme.hankoStone});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: AppTheme.hankoSans(
          fontSize: AppTheme.hankoDataSmallSize,
          weight: FontWeight.w500,
          color: color,
          letterSpacing: 1.6,
          tabular: true,
        ),
      );
}

/// A sheet's drag handle and title, as Hanko's sheets draw them, with an
/// optional action (such as Done) beside the title.
class TierSheetHeader extends StatelessWidget {
  const TierSheetHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: AppTheme.hankoSerif(fontSize: 20)),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AppTheme.hankoSans(fontSize: 13, color: AppTheme.hankoStone)),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.hankoEdge,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (trailing == null)
            heading
          else
            Row(
              children: [
                Expanded(child: heading),
                const SizedBox(width: 12),
                trailing!,
              ],
            ),
        ],
      ),
    );
  }
}

/// Opens a Hanko sheet: sumi 2, top corners at the sheet radius.
Future<T?> showTierSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.hankoSumi2,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.hankoSheetRadius)),
    ),
    builder: (context) => TierTextSelection(child: builder(context)),
  );
}

/// Text selection in washi: the theme's own is coral, and coral is the
/// user's verdicts only.
class TierTextSelection extends StatelessWidget {
  const TierTextSelection({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => TextSelectionTheme(
        data: TextSelectionThemeData(
          cursorColor: AppTheme.hankoWashi,
          selectionColor: AppTheme.hankoWashi.withValues(alpha: 0.28),
          selectionHandleColor: AppTheme.hankoWashi,
        ),
        child: child,
      );
}

/// A short floating message in Hanko's colours.
void tierToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: AppTheme.hankoSans(fontSize: 14)),
      backgroundColor: AppTheme.hankoSumi3,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.hankoRadius)),
      duration: const Duration(seconds: 3),
    ));
}
