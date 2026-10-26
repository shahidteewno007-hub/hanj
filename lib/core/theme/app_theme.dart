import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Warm Dark Palette ──────────────────────────────────────
  static const Color background    = Color(0xFF0A0A0A); // near-black
  static const Color surface       = Color(0xFF141414); // dark surface
  static const Color surfaceLight  = Color(0xFF1E1E1E); // lifted surface
  static const Color surfaceMid    = Color(0xFF272727); // cards, sheets
  static const Color border        = Color(0xFF333333); // subtle border
  static const Color cardBorder    = Color(0xFF272727); // card borders

  // ── Brand ──────────────────────────────────────────────────
  static const Color primary       = Color(0xFFE8624A); // Stride red-coral
  static const Color primaryDim    = Color(0xFF8B3A2A); // muted coral
  static const Color accent        = Color(0xFFD4A96A); // warm gold accent

  // ── Status Colors ──────────────────────────────────────────
  static const Color watching      = Color(0xFFE8624A); // coral = watching
  static const Color completed     = Color(0xFF4A9B6F); // forest green
  static const Color planToWatch   = Color(0xFF4A7FB5); // steel blue
  static const Color dropped       = Color(0xFF8B6A5A); // muted brown
  static const Color secondary     = Color(0xFF9B6B4A); // warm secondary
  static const Color success       = Color(0xFF4A9B6F);
  static const Color warning       = Color(0xFFD4A96A);
  static const Color error         = Color(0xFFCF6679);

  // ── Typography Colors ──────────────────────────────────────
  static const Color textPrimary   = Color(0xFFF3EEE7); // warm ivory — headings
  static const Color textSecondary = Color(0xFFEAE7E1); // soft white — body
  static const Color textMuted     = Color(0xFF9A938B); // muted gray — metadata
  static const Color textInverse   = Color(0xFF0A0A0A); // for light surfaces

  // ── Semantic aliases ───────────────────────────────────────
  static const Color primaryLight  = Color(0xFFED8070);

  // ── Typography Helpers ─────────────────────────────────────
  static TextStyle serif({
    double fontSize = 16,
    FontWeight weight = FontWeight.w400,
    Color color = textPrimary,
    double? height,
    double letterSpacing = 0,
    FontStyle style = FontStyle.normal,
  }) =>
      GoogleFonts.playfairDisplay(
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        fontStyle: style,
      );

  static TextStyle mono({
    double fontSize = 12,
    FontWeight weight = FontWeight.w400,
    Color color = textMuted,
    double letterSpacing = 0.5,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  static TextStyle sans({
    double fontSize = 14,
    FontWeight weight = FontWeight.w400,
    Color color = textPrimary,
    double? height,
  }) =>
      GoogleFonts.dmSans(
        fontSize: fontSize,
        fontWeight: weight,
        color: color,
        height: height,
      );

  // ── Hanko: palette ─────────────────────────────────────────
  // The Hanko look (design/mockups/looks/hanko.html, the spec card),
  // added beside today's tokens; no current screen reads these yet.
  // One meaning per colour: the seal is yours, ai is the crowd,
  // sumi and washi are everything else.
  static const Color hankoSumi      = Color(0xFF121110); // 墨 background
  static const Color hankoSumi2     = Color(0xFF1B1917); // sheets, fields, nav
  static const Color hankoSumi3     = Color(0xFF24211E); // tiles (+1), chips
  static const Color hankoWashi     = Color(0xFFEEE7DA); // 和紙 text; the main action's fill
  static const Color hankoStone     = Color(0xFFA39C90); // secondary text on sumi
  static const Color hankoStoneHi   = Color(0xFFC9C2B6); // secondary text on a cover tint
  static const Color hankoAsh       = Color(0xFF8F887D); // tertiary text, placeholders
  static const Color hankoCoral     = primary;           // your seal (default); sumi text on it, never washi
  static const Color hankoShu       = Color(0xFFAF4120); // 朱 your seal, shu option; washi text on it
  static const Color hankoAi        = Color(0xFF8A99BE); // 藍 the crowd's numbers
  static const Color hankoAiDeep    = Color(0xFF5E6F9A); // the crowd's chart marks
  static const Color hankoEdge      = Color(0xFF7A7368); // borders, outlines, other people's seals
  static const Color hankoHairline  = Color(0xFF2C2824); // the one rule a screen may have
  static const Color hankoPressWash = Color(0x14EEE7DA); // washi at 8%: press, no ripple

  // Detail's cover tint: coverImage.color at 20% over sumi behind the
  // print, fading out by the title. Neutral sumi (null) when the cover's
  // hue is within 25° of the seal's, so the seal never sinks into it.
  static const double hankoTintOpacity  = 0.20;
  static const double hankoTintHueGuard = 25;

  static Color? hankoCoverTint(Color? cover, {Color seal = hankoCoral}) {
    if (cover == null) return null;
    final d = (HSVColor.fromColor(cover).hue - HSVColor.fromColor(seal).hue).abs();
    if ((d > 180 ? 360 - d : d) <= hankoTintHueGuard) return null;
    return cover.withValues(alpha: hankoTintOpacity);
  }

  // ── Hanko: type ────────────────────────────────────────────
  // The spec card's scale. Mincho (hankoSerif) for headlines and titles,
  // Jost (hankoSans) for everything you operate or scan.
  static const double hankoDisplaySize    = 24; // Detail title; past two lines, splits at its first colon into a body-size subtitle
  static const double hankoLedeSize       = 22; // Home's journal sentence
  static const double hankoFeaturedSize   = 19; // featured title
  static const double hankoNativeSize     = 17; // Detail's slip only, in the phone's Japanese font
  static const double hankoSectionSize    = 16; // section heads
  static const double hankoListTitleSize  = 15; // list titles, up to two lines
  static const double hankoBodySize       = 14; // synopsis, notes
  static const double hankoMetaSize       = 13; // facts, captions
  static const double hankoNativeLongSize = 13; // the slip once a title wraps into columns
  static const double hankoLabelSize      = 12; // labels, nav
  static const double hankoDataSmallSize  = 11; // data runs 11–14 in Jost 500: episodes, dates, the crowd

  // Shippori Mincho, 600 only: hierarchy comes from size and colour.
  // The bundled Latin-only Shippori cut replaces this once its download is approved.
  static TextStyle hankoSerif({
    double fontSize = hankoSectionSize,
    Color color = hankoWashi,
    double? height,
    double letterSpacing = 0,
  }) =>
      GoogleFonts.shipporiMincho(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  // Jost 400, 500 and 600 only. tabular: true for columns of numbers;
  // standalone numbers keep proportional figures.
  static TextStyle hankoSans({
    double fontSize = hankoBodySize,
    FontWeight weight = FontWeight.w400,
    Color color = hankoWashi,
    double? height,
    double letterSpacing = 0,
    bool tabular = false,
  }) {
    assert(
      weight == FontWeight.w400 ||
          weight == FontWeight.w500 ||
          weight == FontWeight.w600,
      'Hanko ships Jost 400, 500 and 600 only',
    );
    return GoogleFonts.jost(
      fontSize: fontSize,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  // Native titles: the phone's own Japanese font (no family, 0 bytes),
  // never Shippori. Locale ja picks Japanese glyph forms on Android;
  // on web the browser language decides.
  static TextStyle hankoNative({
    double fontSize = hankoNativeSize,
    Color color = hankoSumi,
    double? height,
    double letterSpacing = 0,
    List<FontFeature>? fontFeatures,
  }) =>
      TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        locale: const Locale('ja'),
        fontFeatures: fontFeatures,
      );

  // ── Hanko: shape, space, motion ────────────────────────────
  static const double hankoRadius      = 2;  // every object: posters, tiles, chips, buttons, seals
  static const double hankoSheetRadius = 6;  // sheets, top corners only
  static const double hankoKeyline     = 2;  // sumi ring that keeps a seal clear of art and tints
  static const double hankoGutter      = 20; // side gutter on a phone
  static const double hankoTouch       = 48; // smallest touch target
  static const double hankoChipHeight  = 36; // drawn height; touched at hankoTouch

  static const double   hankoSealPressScale = 1.06; // rating presses the seal in, 1.06 → 1.0
  static const Duration hankoSealPress      = Duration(milliseconds: 120);
  static const Duration hankoSheetRise      = Duration(milliseconds: 240);
  static const Curve    hankoSheetCurve     = Curves.decelerate;

  // ── Theme ──────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary:     primary,
        secondary:   secondary,
        surface:     surface,
        error:       error,
        onPrimary:   textPrimary,
        onSecondary: textPrimary,
        onSurface:   textPrimary,
      ),
      textTheme: TextTheme(
        // Serif display
        displayLarge:  GoogleFonts.playfairDisplay(
            color: textPrimary, fontSize: 48, fontWeight: FontWeight.w700),
        displayMedium: GoogleFonts.playfairDisplay(
            color: textPrimary, fontSize: 36, fontWeight: FontWeight.w600),
        displaySmall:  GoogleFonts.playfairDisplay(
            color: textPrimary, fontSize: 28, fontWeight: FontWeight.w600),
        headlineLarge: GoogleFonts.playfairDisplay(
            color: textPrimary, fontSize: 32, fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.playfairDisplay(
            color: textPrimary, fontSize: 24, fontWeight: FontWeight.w600),
        headlineSmall:  GoogleFonts.playfairDisplay(
            color: textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        // Sans body
        titleLarge:  GoogleFonts.dmSans(
            color: textPrimary,   fontSize: 17, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.dmSans(
            color: textPrimary,   fontSize: 15, fontWeight: FontWeight.w500),
        titleSmall:  GoogleFonts.dmSans(
            color: textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
        bodyLarge:   GoogleFonts.dmSans(
            color: textPrimary,   fontSize: 16, height: 1.6),
        bodyMedium:  GoogleFonts.dmSans(
            color: textSecondary, fontSize: 14, height: 1.5),
        bodySmall:   GoogleFonts.dmSans(
            color: textMuted,     fontSize: 12, height: 1.4),
        // Mono labels
        labelLarge:  GoogleFonts.spaceGrotesk(
            color: textSecondary, fontSize: 12,
            fontWeight: FontWeight.w500, letterSpacing: 0.8),
        labelMedium: GoogleFonts.spaceGrotesk(
            color: textMuted,     fontSize: 11,
            fontWeight: FontWeight.w400, letterSpacing: 0.6),
        labelSmall:  GoogleFonts.spaceGrotesk(
            color: textMuted,     fontSize: 10,
            fontWeight: FontWeight.w400, letterSpacing: 1.0),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.playfairDisplay(
          color: textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.spaceGrotesk(
              color: primary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            );
          }
          return GoogleFonts.spaceGrotesk(
            color: textMuted,
            fontSize: 10,
            letterSpacing: 0.5,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 22);
          }
          return const IconThemeData(color: textMuted, size: 22);
        }),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: cardBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: GoogleFonts.dmSans(color: textMuted, fontSize: 14),
        labelStyle: GoogleFonts.dmSans(color: textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: textPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30)),
          textStyle: GoogleFonts.dmSans(
              fontSize: 15, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30)),
          textStyle: GoogleFonts.dmSans(
              fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.dmSans(
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLight,
        selectedColor: primary,
        labelStyle: GoogleFonts.dmSans(color: textSecondary, fontSize: 13),
        side: const BorderSide(color: border),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceMid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.playfairDisplay(
            color: textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        contentTextStyle:
            GoogleFonts.dmSans(color: textSecondary, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceMid,
        contentTextStyle: GoogleFonts.dmSans(color: textPrimary, fontSize: 14),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Light Theme ────────────────────────────────────────────
  static ThemeData get lightTheme {
    const lightBg      = Color(0xFFF5F0E8);
    const lightSurface = Color(0xFFFFFFFF);
    const lightSurfaceLight = Color(0xFFF0EBE3);
    const lightBorder  = Color(0xFFD8D0C8);
    const lightText    = Color(0xFF1A1612);
    const lightTextSec = Color(0xFF4A4540);
    const lightTextMut = Color(0xFF8B8580);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      colorScheme: const ColorScheme.light(
        primary:     primary,
        secondary:   secondary,
        surface:     lightSurface,
        error:       error,
        onPrimary:   Colors.white,
        onSecondary: Colors.white,
        onSurface:   lightText,
      ),
      textTheme: TextTheme(
        displayLarge:  GoogleFonts.playfairDisplay(color: lightText, fontSize: 48, fontWeight: FontWeight.w700),
        displayMedium: GoogleFonts.playfairDisplay(color: lightText, fontSize: 36, fontWeight: FontWeight.w600),
        displaySmall:  GoogleFonts.playfairDisplay(color: lightText, fontSize: 28, fontWeight: FontWeight.w600),
        headlineLarge: GoogleFonts.playfairDisplay(color: lightText, fontSize: 32, fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.playfairDisplay(color: lightText, fontSize: 24, fontWeight: FontWeight.w600),
        headlineSmall:  GoogleFonts.playfairDisplay(color: lightText, fontSize: 20, fontWeight: FontWeight.w600),
        titleLarge:  GoogleFonts.dmSans(color: lightText,    fontSize: 17, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.dmSans(color: lightText,    fontSize: 15, fontWeight: FontWeight.w500),
        titleSmall:  GoogleFonts.dmSans(color: lightTextSec, fontSize: 13, fontWeight: FontWeight.w500),
        bodyLarge:   GoogleFonts.dmSans(color: lightText,    fontSize: 16, height: 1.6),
        bodyMedium:  GoogleFonts.dmSans(color: lightTextSec, fontSize: 14, height: 1.5),
        bodySmall:   GoogleFonts.dmSans(color: lightTextMut, fontSize: 12, height: 1.4),
        labelLarge:  GoogleFonts.spaceGrotesk(color: lightTextSec, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.8),
        labelMedium: GoogleFonts.spaceGrotesk(color: lightTextMut, fontSize: 11, letterSpacing: 0.6),
        labelSmall:  GoogleFonts.spaceGrotesk(color: lightTextMut, fontSize: 10, letterSpacing: 1.0),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.playfairDisplay(
          color: lightText, fontSize: 22, fontWeight: FontWeight.w700),
        iconTheme: const IconThemeData(color: lightText),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: lightSurface,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.spaceGrotesk(
                color: primary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5);
          }
          return GoogleFonts.spaceGrotesk(
              color: lightTextMut, fontSize: 10, letterSpacing: 0.5);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 22);
          }
          return const IconThemeData(color: lightTextMut, size: 22);
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: lightSurface,
        selectedItemColor: primary,
        unselectedItemColor: lightTextMut,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error),
        ),
        hintStyle: GoogleFonts.dmSans(color: lightTextMut, fontSize: 14),
        labelStyle: GoogleFonts.dmSans(color: lightTextSec),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightText,
          side: const BorderSide(color: lightBorder),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          textStyle: GoogleFonts.dmSans(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightSurfaceLight,
        selectedColor: primary.withValues(alpha: 0.15),
        labelStyle: GoogleFonts.dmSans(color: lightTextSec, fontSize: 13),
        side: const BorderSide(color: lightBorder),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.playfairDisplay(
            color: lightText, fontSize: 20, fontWeight: FontWeight.w600),
        contentTextStyle: GoogleFonts.dmSans(color: lightTextSec, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lightText,
        contentTextStyle: GoogleFonts.dmSans(color: lightBg, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
