import 'package:flutter/material.dart';

class Responsive {
  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < 600;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= 600 &&
      MediaQuery.of(context).size.width < 1024;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1024;

  static double getWidth(BuildContext context) =>
      MediaQuery.of(context).size.width;

  static double getHeight(BuildContext context) =>
      MediaQuery.of(context).size.height;

  // Grid columns based on screen size
  static int getGridColumns(BuildContext context) {
    if (isMobile(context)) return 2;
    if (isTablet(context)) return 3;
    return 3; // Desktop
  }

  // Horizontal list card width
  static double getCardWidth(BuildContext context) {
    if (isMobile(context)) return 140;
    if (isTablet(context)) return 160;
    return 160; // Desktop
  }

  // Padding values
  static double getHorizontalPadding(BuildContext context) {
    if (isMobile(context)) return 12;
    if (isTablet(context)) return 16;
    return 16; // Desktop
  }

  static double getVerticalPadding(BuildContext context) {
    if (isMobile(context)) return 12;
    if (isTablet(context)) return 16;
    return 20; // Desktop
  }

  // Font size scaling
  static double scaleFontSize(BuildContext context, double baseSize) {
    if (isMobile(context)) return baseSize * 0.9;
    return baseSize;
  }

  // Avatar size
  static double getAvatarSize(BuildContext context) {
    if (isMobile(context)) return 80;
    if (isTablet(context)) return 90;
    return 100; // Desktop
  }

  // Bottom nav bar height
  static double getBottomNavHeight(BuildContext context) {
    if (isMobile(context)) return 60;
    return 70; // Desktop/Tablet
  }
  // ── Desktop layout system (WEB.md §9.3) ─────────────────────────────────
  // Derived from the width the design is proven at — 360–390 logical px on the
  // CPH2573 — not from a framework's defaults. A wide viewport repeats that
  // column rather than stretching it:
  //
  //   pageMaxWidth = 3 × 437 + 2 × 24 gutter + 2 × 20 padding = 1400
  //
  // Both caps are inert below their own value, so a phone reaches neither:
  // 360 px portrait, 792 px landscape. That 792 is why structural decisions
  // hang off 1024 and never off 600 — see WEB.md §9.2.
  static const double pageMaxWidth = 1400;

  // One column's worth of prose: ~67 characters of DM Sans at 14 px, the
  // middle of the 66–75 readable measure. Measured rather than assumed —
  // DM Sans averages 6.55 px per character at 14 px (0.468 em), which is
  // narrower than the Inter figure this was first derived from. Long-form
  // text never exceeds a single column.
  static const double proseMaxWidth = 440;

  static const double _columnMin = 350;
  static const double _gutter = 24;
  static const double _outerPadding = 20;

  /// The width at which multi-column layout begins. Same threshold as
  /// [isDesktop], and deliberately not 600 — a CPH2573 in landscape is 792
  /// logical px wide, so 600 would put a phone into desktop layout.
  static const double desktopMin = 1024;

  /// Columns at [width], from the same rule that produced [pageMaxWidth].
  /// 390 → 1, 768 → 1, 1024 → 2, 1440 → 3, 1920 → 3.
  ///
  /// **Domain: desktop widths only.** This is content-width arithmetic derived
  /// from the 1400 cap; it was never a rule about phones. Below [desktopMin]
  /// it returns 1 by construction rather than by arithmetic — the unfloored
  /// formula yields 2 at 792, which would put a phone in landscape into a
  /// two-column layout and contradict the very finding that makes 1024 the
  /// safe structural breakpoint (WEB.md §9.2, §9.3).
  static int columnsFor(double width) {
    if (width < desktopMin) return 1;
    final capped = width > pageMaxWidth ? pageMaxWidth : width;
    final usable = capped - (2 * _outerPadding) + _gutter;
    final n = usable ~/ (_columnMin + _gutter);
    if (n < 1) return 1;
    if (n > 3) return 3;
    return n;
  }
}

/// Centres [child] and caps its width, so a desktop viewport shows a content
/// column instead of a stretched phone layout.
///
/// Inert on Android: [Responsive.pageMaxWidth] is 1400, above both the
/// CPH2573's 360 px portrait width and its 792 px landscape width, so the
/// phone takes the layout it always did in either orientation.
///
/// Applied to the shell in `MainScreen`, which reaches the five tab roots
/// only. Pushed routes — anime detail, card collection, search — are not
/// covered and adopt this widget one at a time as each gets its responsive
/// pass. A `MaterialApp.builder` would have caught them all in one line but
/// also wraps dialogs, bottom sheets and the full-bleed login backdrop, so it
/// was rejected (WEB.md §9.7).
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child, this.maxWidth});

  final Widget child;

  /// Defaults to [Responsive.pageMaxWidth]. Pass [Responsive.proseMaxWidth]
  /// for long-form text.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? Responsive.pageMaxWidth,
        ),
        child: child,
      ),
    );
  }
}
