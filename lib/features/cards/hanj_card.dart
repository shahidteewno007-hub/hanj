import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HANJ CARD WIDGET
// Matches the 5 reference designs exactly:
//   Common    — dot-grid, near-black, grey border, no glow
//   Rare      — blue outer glow, large kanji watermark, blue border
//   Epic      — purple glow, diagonal line texture, ornate brackets
//   Legendary — split layout: red burst top + black panel bottom, gold border
//   Seasonal  — dark bg, green glow, dashed border, floating petals
//   Secret    — shown as locked ??? card until unlocked
//
// Usage:
//   HanjCard(card: myCard, isUnlocked: true)
//   HanjCard(card: myCard, isUnlocked: false)  // shows locked state
// ─────────────────────────────────────────────────────────────────────────────

// ── Data model ───────────────────────────────────────────────────────────────

enum CardRarity { common, rare, epic, legendary, seasonal, secret }

class HanjCardData {
  final String id;
  final String name;
  final String description;
  final CardRarity rarity;
  final String category;     // e.g. "ÆTHER", "LINEAGE", "DEVOTION", "MANGA CUT"
  final String kanji;        // watermark character
  final int cardNumber;      // for № display
  final int? totalCount;     // for seasonal: "1 OF 2400"; null = ∞
  final DateTime? unlockedAt;

  const HanjCardData({
    required this.id,
    required this.name,
    required this.description,
    required this.rarity,
    required this.category,
    required this.kanji,
    required this.cardNumber,
    this.totalCount,
    this.unlockedAt,
  });

  // Rarity colour
  Color get rarityColor {
    switch (rarity) {
      case CardRarity.common:   return const Color(0xFF9E9E9E);
      case CardRarity.rare:     return const Color(0xFF5B8DEF);
      case CardRarity.epic:     return const Color(0xFFB06EE8);
      case CardRarity.legendary:return const Color(0xFFD4A96A);
      case CardRarity.seasonal: return const Color(0xFF4CAF7D);
      case CardRarity.secret:   return const Color(0xFF9E9E9E);
    }
  }

  String get rarityLabel {
    switch (rarity) {
      case CardRarity.common:   return 'COMMON';
      case CardRarity.rare:     return 'RARE';
      case CardRarity.epic:     return 'EPIC';
      case CardRarity.legendary:return 'LEGENDARY';
      case CardRarity.seasonal: return 'SEASONAL';
      case CardRarity.secret:   return 'SECRET';
    }
  }

  String get cardNumberFormatted {
    final s = cardNumber.toString().padLeft(4, '0');
    if (totalCount != null) return '№ $s / $totalCount';
    if (rarity == CardRarity.legendary) return '№ $s / ∞';
    return '№ $s';
  }
}

// ── Main widget ──────────────────────────────────────────────────────────────

class HanjCard extends StatelessWidget {
  final HanjCardData card;
  final bool isUnlocked;
  final double width;
  final double height;

  // Default card size (2:3 ratio)
  static const double kWidth  = 200.0;
  static const double kHeight = 300.0;

  const HanjCard({
    super.key,
    required this.card,
    this.isUnlocked = true,
    this.width  = kWidth,
    this.height = kHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (!isUnlocked) return _LockedCard(card: card, width: width, height: height);

    Widget card0;
    switch (card.rarity) {
      case CardRarity.common:    card0 = _CommonCard(card: card, w: width, h: height); break;
      case CardRarity.rare:      card0 = _RareCard(card: card, w: width, h: height); break;
      case CardRarity.epic:      card0 = _EpicCard(card: card, w: width, h: height); break;
      case CardRarity.legendary: card0 = _LegendaryCard(card: card, w: width, h: height); break;
      case CardRarity.seasonal:  card0 = _SeasonalCard(card: card, w: width, h: height); break;
      case CardRarity.secret:    card0 = _LockedCard(card: card, isSecret: true, width: width, height: height); break;
    }
    return SizedBox(
      width: width, height: height,
      child: ClipRect(child: card0),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMON CARD
// Near-black bg, dot-grid texture, grey border (no glow), Gothic "H" watermark
// ─────────────────────────────────────────────────────────────────────────────

class _CommonCard extends StatelessWidget {
  final HanjCardData card;
  final double w, h;
  const _CommonCard({required this.card, this.w = HanjCard.kWidth, this.h = HanjCard.kHeight});

  @override
  Widget build(BuildContext context) {
    const bg        = Color(0xFF0F0C09);
    const borderCol = Color(0xFF3A3A3A);
    const grey      = Color(0xFF9E9E9E);

    return _CardShell(
      width: w,
      height: h,
      borderColor: borderCol,
      borderWidth: 1.0,
      glowColor: Colors.transparent,
      glowSpread: 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Container(color: bg),
          // Dot grid texture
          CustomPaint(painter: _DotGridPainter(dotColor: const Color(0xFF2A2A2A)), size: Size(w, h)),
          // Large watermark — Gothic "H" style using the kanji field or a custom painter
          Positioned.fill(
            child: Center(
              child: Text(
                card.kanji,
                style: GoogleFonts.playfairDisplay(
                  fontSize: w * 0.65,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF2A2725),
                  letterSpacing: -4,
                ),
              ),
            ),
          ),
          // Divider line above text area
          Positioned(
            left: 16, right: 16,
            bottom: h * 0.33,
            child: Container(height: 0.5, color: const Color(0xFF3A3A3A)),
          ),
          // Rarity pill — top left
          Positioned(
            top: 14, left: 14,
            child: _RarityPill(label: 'COMMON', color: grey, filled: false),
          ),
          // Hanj feather — top right
          const Positioned(top: 14, right: 14, child: _HanjFeather()),
          // Corner brackets
          ..._cornerBrackets(const Color(0xFF3A3A3A)),
          // Bottom text area — fixed height, no overflow
          Positioned(
            left: w * 0.07, right: w * 0.07, bottom: h * 0.047,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        card.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: w * 0.09,
                          fontStyle: FontStyle.italic,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: w * 0.045, color: Color(0xFFAAAAAA), height: 1.3),
                      ),
                    ],
                  ),
                    _Footer(card: card, color: const Color(0xFF555555)),
                ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RARE CARD
// Blue outer glow, large kanji watermark (dark navy on black), blue border
// ─────────────────────────────────────────────────────────────────────────────

class _RareCard extends StatelessWidget {
  final HanjCardData card;
  final double w, h;
  const _RareCard({required this.card, this.w = HanjCard.kWidth, this.h = HanjCard.kHeight});

  @override
  Widget build(BuildContext context) {
    const bg       = Color(0xFF080D18);
    const blue     = Color(0xFF5B8DEF);
    const darkBlue = Color(0xFF1A2540);

    return _CardShell(
      width: w,
      height: h,
      borderColor: blue,
      borderWidth: 1.5,
      glowColor: blue.withOpacity(0.55),
      glowSpread: 12,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: bg),
          // Kanji watermark — large, dark navy
          Positioned.fill(
            child: Center(
              child: Text(
                card.kanji,
                style: TextStyle(
                  fontSize: w * 0.8,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E2D50),
                  height: 1,
                ),
              ),
            ),
          ),
          // Divider
          Positioned(
            left: 16, right: 16,
            bottom: h * 0.33,
            child: Container(height: 0.5, color: blue.withOpacity(0.3)),
          ),
          // Rarity pill
          Positioned(
            top: 14, left: 14,
            child: _RarityPill(label: 'RARE', color: blue, filled: false),
          ),
          const Positioned(top: 14, right: 14, child: _HanjFeather()),
          ..._cornerBrackets(blue.withOpacity(0.6)),
          // Bottom text — fixed height, no overflow
          Positioned(
            left: w * 0.07, right: w * 0.07, bottom: h * 0.047,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(card.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(fontSize: w * 0.09, fontStyle: FontStyle.italic, color: Colors.white, fontWeight: FontWeight.w600, height: 1.15)),
                      const SizedBox(height: 4),
                      Text(card.description,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: w * 0.045, color: Color(0xFF8899CC), height: 1.3)),
                    ],
                  ),
                    _Footer(card: card, color: blue.withOpacity(0.5)),
                ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EPIC CARD
// Purple glow, diagonal line bg texture, large kanji 心, ornate corner brackets
// ─────────────────────────────────────────────────────────────────────────────

class _EpicCard extends StatelessWidget {
  final HanjCardData card;
  final double w, h;
  const _EpicCard({required this.card, this.w = HanjCard.kWidth, this.h = HanjCard.kHeight});

  @override
  Widget build(BuildContext context) {
    const purple     = Color(0xFFB06EE8);
    const darkPurple = Color(0xFF1A0D2E);
    const bg         = Color(0xFF100820);

    return _CardShell(
      width: w,
      height: h,
      borderColor: purple,
      borderWidth: 1.5,
      glowColor: purple.withOpacity(0.6),
      glowSpread: 14,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF180D2A), Color(0xFF0D0814)],
              ),
            ),
          ),
          // Diagonal line texture
          CustomPaint(painter: _DiagonalLinePainter(color: const Color(0xFF2A1545)), size: Size(w, h)),
          // Kanji watermark
          Positioned.fill(
            top: -10,
            child: Center(
              child: Text(
                card.kanji,
                style: TextStyle(fontSize: w * 0.75, fontWeight: FontWeight.w900, color: const Color(0xFF2E1650), height: 1),
              ),
            ),
          ),
          // Divider
          Positioned(
            left: 16, right: 16,
            bottom: h * 0.33,
            child: Container(height: 0.5, color: purple.withOpacity(0.35)),
          ),
          // Rarity pill — filled purple
          Positioned(
            top: 14, left: 14,
            child: _RarityPill(label: 'EPIC', color: purple, filled: true),
          ),
          const Positioned(top: 14, right: 14, child: _HanjFeather()),
          // Ornate corner brackets (thicker, double-line style)
          ..._ornateCornerBrackets(purple.withOpacity(0.7)),
          // Bottom text — fixed height, no overflow
          Positioned(
            left: w * 0.07, right: w * 0.07, bottom: h * 0.047,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(card.name,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(fontSize: w * 0.09, fontStyle: FontStyle.italic, color: Colors.white, fontWeight: FontWeight.w600, height: 1.15)),
                      const SizedBox(height: 4),
                      Text(card.description,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: w * 0.045, color: Color(0xFFAA88CC), height: 1.3)),
                    ],
                  ),
                    _Footer(card: card, color: purple.withOpacity(0.5)),
                ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEGENDARY CARD
// Split layout: red burst art top half + black info panel bottom half
// Gold border, "ISSUE 100 · FOIL VARIANT" label, kanji top-right of panel
// ─────────────────────────────────────────────────────────────────────────────

class _LegendaryCard extends StatelessWidget {
  final HanjCardData card;
  final double w, h;
  const _LegendaryCard({required this.card, this.w = HanjCard.kWidth, this.h = HanjCard.kHeight});

  @override
  Widget build(BuildContext context) {
    const gold    = Color(0xFFD4A96A);
    const darkBg  = Color(0xFF0A0805);

    return _CardShell(
      width: w,
      height: h,
      borderColor: gold,
      borderWidth: 1.5,
      glowColor: gold.withOpacity(0.25),
      glowSpread: 8,
      child: Column(
        children: [
          // ── Top art half: red gradient + radial burst ──
          Expanded(
            flex: 52,
            child: Stack(
              children: [
                // Deep red gradient bg
                Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.2, 0.4),
                      radius: 1.0,
                      colors: [Color(0xFF8B1A1A), Color(0xFF5C0A0A), Color(0xFF2A0505)],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
                // Radial burst lines
                CustomPaint(
                  painter: _RadialBurstPainter(color: const Color(0xFFFFFFFF).withOpacity(0.08)),
                  size: Size(w, h * 0.52),
                ),
                // "ONE HUNDRED!" bold display text
                Positioned(
                  left: w * 0.07, bottom: h * 0.08, right: w * 0.07,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      'ONE\nHUNDRED!',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: w * 0.15,
                        fontWeight: FontWeight.w900,
                        color: gold,
                        height: 0.95,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ),
                // Rarity pill — top left
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8D4A0),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF8B6A30))),
                        const SizedBox(width: 5),
                        Text('LEGENDARY', style: GoogleFonts.spaceMono(fontSize: w * 0.035, fontWeight: FontWeight.w700, color: Color(0xFF3A2A10), letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ),
                const Positioned(top: 12, right: 12, child: _HanjFeather()),
              ],
            ),
          ),
          // ── Bottom info panel: black ──
          Expanded(
            flex: 48,
            child: Container(
              color: darkBg,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: w * 0.13),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "ISSUE 100 · FOIL VARIANT" label
                      Row(
                        children: [
                          Text(
                            'ISSUE 100  ·  FOIL VARIANT',
                            style: GoogleFonts.spaceMono(fontSize: w * 0.035, color: gold.withOpacity(0.7), letterSpacing: 0.8),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Card name
                      Text(
                        card.name,
                        style: GoogleFonts.playfairDisplay(fontSize: w * 0.10, fontStyle: FontStyle.italic, color: gold, fontWeight: FontWeight.w700, height: 1.1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(card.description, style: TextStyle(fontSize: w * 0.045, color: const Color(0xFFCCBB99).withOpacity(0.8), height: 1.45), maxLines: 3, overflow: TextOverflow.ellipsis),
                      const Spacer(),
                      // Divider
                      Container(height: 0.5, color: gold.withOpacity(0.25)),
                      const SizedBox(height: 6),
                      _Footer(card: card, color: gold.withOpacity(0.45)),
                    ],
                  ),
                  ),
                  // Kanji 百 top-right of panel
                  Positioned(
                    top: 0, right: 0,
                    child: Text(card.kanji, style: TextStyle(fontSize: w * 0.11, color: gold.withOpacity(0.4), fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEASONAL CARD
// Dark bg, green glow, dashed border, large kanji 季, floating petals,
// rotated stamp, roman numeral date footer
// ─────────────────────────────────────────────────────────────────────────────

class _SeasonalCard extends StatelessWidget {
  final HanjCardData card;
  final double w, h;
  const _SeasonalCard({required this.card, this.w = HanjCard.kWidth, this.h = HanjCard.kHeight});

  @override
  Widget build(BuildContext context) {
    const green   = Color(0xFF4CAF7D);
    const darkBg  = Color(0xFF060E0A);
    const panelBg = Color(0xFF07120A);

    return _CardShell(
      width: w,
      height: h,
      borderColor: green,
      borderWidth: 1.5,
      glowColor: green.withOpacity(0.25),
      glowSpread: 8,
      isDashed: false,
      child: Column(
        children: [
          // ── Top art panel ──────────────────────────────
          Expanded(
            flex: 52,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // Dark green gradient bg
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0.0, 0.3),
                        radius: 1.1,
                        colors: [Color(0xFF0F2A1A), Color(0xFF071410), Color(0xFF040C08)],
                        stops: [0.0, 0.6, 1.0],
                      ),
                    ),
                  ),
                ),
                // Kanji watermark — centred, toned down
                Positioned.fill(
                  child: Center(
                    child: Text(
                      card.kanji,
                      style: TextStyle(
                        fontSize: w * 0.82,
                        fontWeight: FontWeight.w900,
                        color: green.withOpacity(0.13),
                        height: 1,
                      ),
                    ),
                  ),
                ),
                // Subtle radial glow behind kanji
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 0.7,
                        colors: [green.withOpacity(0.07), Colors.transparent],
                      ),
                    ),
                  ),
                ),
                // Floating leaf marks (top-left, bottom-right)
                Positioned(top: h * 0.12, left: w * 0.08,
                  child: Transform.rotate(angle: -0.6,
                    child: Text('✦', style: TextStyle(fontSize: w * 0.04, color: green.withOpacity(0.25))))),
                Positioned(top: h * 0.22, right: w * 0.18,
                  child: Transform.rotate(angle: 0.9,
                    child: Text('✦', style: TextStyle(fontSize: w * 0.025, color: green.withOpacity(0.18))))),
                Positioned(bottom: h * 0.06, left: w * 0.22,
                  child: Transform.rotate(angle: 1.2,
                    child: Text('✦', style: TextStyle(fontSize: w * 0.03, color: green.withOpacity(0.2))))),
                // Rarity pill — top left
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: green.withOpacity(0.5), width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 5, height: 5,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: green.withOpacity(0.9))),
                        const SizedBox(width: 5),
                        Text('SEASONAL',
                          style: GoogleFonts.spaceMono(
                            fontSize: w * 0.035, fontWeight: FontWeight.w700,
                            color: green, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                ),
                const Positioned(top: 12, right: 12, child: _HanjFeather()),
                // Rotated stamp — lower right of top panel
                Positioned(
                  bottom: h * 0.04, right: w * 0.05,
                  child: Transform.rotate(
                    angle: -0.18,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: green.withOpacity(0.7), width: 1),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        card.totalCount != null
                            ? '1 OF ${card.totalCount}'
                            : 'LIMITED EDITION',
                        style: GoogleFonts.spaceMono(
                          fontSize: w * 0.036, color: green.withOpacity(0.85), letterSpacing: 0.8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Bottom info panel ──────────────────────────
          Expanded(
            flex: 48,
            child: Container(
              color: panelBg,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: w * 0.13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Season label row
                        Text(
                          card.category.isNotEmpty
                              ? '${card.category}  ·  LIMITED'
                              : 'SEASONAL  ·  LIMITED',
                          style: GoogleFonts.spaceMono(
                            fontSize: w * 0.035,
                            color: green.withOpacity(0.7),
                            letterSpacing: 0.8),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Card name
                        Text(
                          card.name,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: w * 0.10,
                            fontStyle: FontStyle.italic,
                            color: const Color(0xFFCCEEDD),
                            fontWeight: FontWeight.w700,
                            height: 1.1),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          card.description,
                          style: TextStyle(
                            fontSize: w * 0.045,
                            color: const Color(0xFF88AA99).withOpacity(0.85),
                            height: 1.45),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        Container(height: 0.5, color: green.withOpacity(0.25)),
                        const SizedBox(height: 6),
                        _Footer(card: card, color: green.withOpacity(0.45)),
                      ],
                    ),
                  ),
                  // Kanji top-right of panel
                  Positioned(
                    top: 0, right: 0,
                    child: Text(
                      card.kanji,
                      style: TextStyle(
                        fontSize: w * 0.11,
                        color: green.withOpacity(0.35),
                        fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCKED CARD
// Dark silhouette, ??? in rarity colour, lock icon
// ─────────────────────────────────────────────────────────────────────────────

class _LockedCard extends StatelessWidget {
  final HanjCardData card;
  final bool isSecret;
  final double width, height;
  const _LockedCard({required this.card, this.isSecret = false, this.width = HanjCard.kWidth, this.height = HanjCard.kHeight});

  @override
  Widget build(BuildContext context) {
    final col = card.rarityColor;
    return _CardShell(
      width: width,
      height: height,
      borderColor: col.withOpacity(0.2),
      borderWidth: 1.0,
      glowColor: Colors.transparent,
      glowSpread: 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0xFF0A0A0A)),
          CustomPaint(painter: _DotGridPainter(dotColor: const Color(0xFF1A1A1A)), size: Size(width, height)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, color: col.withOpacity(0.4), size: 28),
                const SizedBox(height: 10),
                Text(
                  '???',
                  style: GoogleFonts.playfairDisplay(fontSize: 28, fontStyle: FontStyle.italic, color: col.withOpacity(0.5), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  card.rarityLabel,
                  style: GoogleFonts.spaceMono(fontSize: 8, color: col.withOpacity(0.3), letterSpacing: 1.5),
                ),
              ],
            ),
          ),
          Positioned(
            top: 14, left: 14,
            child: _RarityPill(label: card.rarityLabel, color: col.withOpacity(0.3), filled: false),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED COMPONENTS
// ─────────────────────────────────────────────────────────────────────────────

/// Outer shell: border + optional glow. All cards share this shape.
class _CardShell extends StatelessWidget {
  final double width, height;
  final Color borderColor, glowColor;
  final double borderWidth, glowSpread;
  final bool isDashed;
  final Widget child;

  const _CardShell({
    required this.width, required this.height,
    required this.borderColor, required this.borderWidth,
    required this.glowColor, required this.glowSpread,
    required this.child, this.isDashed = false,
  });

  @override
  Widget build(BuildContext context) {
    // Square corners. Glow is painted INSIDE the card via CustomPaint so it
    // never escapes the widget bounds — no boxShadow bleeding issues.
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Card content ──────────────────────────────────────────────────
          isDashed
              ? CustomPaint(
                  painter: _DashedBorderPainter(
                      color: borderColor, strokeWidth: borderWidth),
                  child: child,
                )
              : child,

          // ── Glowing border painted on top (stays inside bounds) ───────────
          CustomPaint(
            painter: _GlowBorderPainter(
              color: borderColor,
              glowColor: glowColor,
              glowSpread: glowSpread,
              isDashed: isDashed,
            ),
          ),

          // ── Top-right shimmer reflection ───────────────────────────────────
          Positioned(
            top: 0,
            right: 0,
            child: CustomPaint(
              size: Size(width * 0.6, height * 0.4),
              painter: _ShimmerReflectionPainter(color: borderColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBorderPainter extends CustomPainter {
  final Color color, glowColor;
  final double glowSpread;
  final bool isDashed;

  const _GlowBorderPainter({
    required this.color,
    required this.glowColor,
    required this.glowSpread,
    required this.isDashed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isDashed) return; // dashed painter handles its own border

    // Clip canvas so nothing escapes the card bounds
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Glow rects are inset so the blurred stroke stays fully inside
    final inset = glowSpread > 0 ? (glowSpread * 0.4).clamp(4.0, 12.0) : 1.0;
    final glowRect = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);

    if (glowSpread > 0) {
      // Soft wide glow
      canvas.drawRect(glowRect, Paint()
        ..color = glowColor.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = inset * 2
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, inset));

      // Tight bright glow on border
      final borderRect = Rect.fromLTWH(1, 1, size.width - 2, size.height - 2);
      canvas.drawRect(borderRect, Paint()
        ..color = glowColor.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }

    // Sharp border line
    final borderRect = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    canvas.drawRect(borderRect, Paint()
      ..color = color.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0);

    // Inner inset line
    canvas.drawRect(
      Rect.fromLTWH(3, 3, size.width - 6, size.height - 6),
      Paint()
        ..color = color.withOpacity(0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  @override
  bool shouldRepaint(_GlowBorderPainter old) => false;
}

class _ShimmerReflectionPainter extends CustomPainter {
  final Color color;
  const _ShimmerReflectionPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.topRight,
        radius: 1.0,
        colors: [
          color.withOpacity(0.18),
          color.withOpacity(0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(_ShimmerReflectionPainter old) => false;
}

/// Rarity pill — top-left badge
class _RarityPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  const _RarityPill({required this.label, required this.color, required this.filled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5, height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: filled ? Colors.black.withOpacity(0.5) : color),
          ),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.spaceMono(fontSize: 7.5, fontWeight: FontWeight.w700, color: filled ? Colors.black : color, letterSpacing: 0.8)),
        ],
      ),
    );
  }
}

/// Hanj feather icon — top right of every card
class _HanjFeather extends StatelessWidget {
  const _HanjFeather();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/hanj_wing_transparent.png',
      width: 22,
      height: 22,
      fit: BoxFit.contain,
    );
  }
}

/// Footer row — № XXXX left, RARITY · CATEGORY right
class _Footer extends StatelessWidget {
  final HanjCardData card;
  final Color color;
  final String? rightText;
  const _Footer({required this.card, required this.color, this.rightText});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            card.cardNumberFormatted,
            style: GoogleFonts.spaceMono(fontSize: 7.5, color: color, letterSpacing: 0.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            rightText ?? '${card.rarityLabel}  ·  ${card.category}',
            style: GoogleFonts.spaceMono(fontSize: 7.5, color: color, letterSpacing: 0.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Corner bracket decoration — thin L-shapes at each corner
List<Widget> _cornerBrackets(Color color, {double size = 10, double thickness = 1}) {
  return [
    _Corner(alignment: Alignment.topLeft,     color: color, size: size, thickness: thickness, flipX: false, flipY: false),
    _Corner(alignment: Alignment.topRight,    color: color, size: size, thickness: thickness, flipX: true,  flipY: false),
    _Corner(alignment: Alignment.bottomLeft,  color: color, size: size, thickness: thickness, flipX: false, flipY: true),
    _Corner(alignment: Alignment.bottomRight, color: color, size: size, thickness: thickness, flipX: true,  flipY: true),
  ];
}

/// Ornate corner brackets for Epic cards — slightly larger, with inner tick
List<Widget> _ornateCornerBrackets(Color color) {
  return _cornerBrackets(color, size: 14, thickness: 1.2);
}

class _Corner extends StatelessWidget {
  final Alignment alignment;
  final Color color;
  final double size, thickness;
  final bool flipX, flipY;
  const _Corner({required this.alignment, required this.color, required this.size, required this.thickness, required this.flipX, required this.flipY});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top:    alignment == Alignment.topLeft    || alignment == Alignment.topRight    ? 8  : null,
      bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight ? 8  : null,
      left:   alignment == Alignment.topLeft    || alignment == Alignment.bottomLeft  ? 8  : null,
      right:  alignment == Alignment.topRight   || alignment == Alignment.bottomRight ? 8  : null,
      child: CustomPaint(painter: _CornerPainter(color: color, size: size, thickness: thickness, flipX: flipX, flipY: flipY), size: Size(size, size)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM PAINTERS
// ─────────────────────────────────────────────────────────────────────────────

class _DotGridPainter extends CustomPainter {
  final Color dotColor;
  const _DotGridPainter({required this.dotColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = dotColor..style = PaintingStyle.fill;
    const spacing = 12.0;
    const radius  = 0.8;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override bool shouldRepaint(_DotGridPainter old) => false;
}

class _DiagonalLinePainter extends CustomPainter {
  final Color color;
  const _DiagonalLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 0.5;
    const spacing = 8.0;
    for (double i = -size.height; i < size.width + size.height; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + size.height, size.height), paint);
    }
  }

  @override bool shouldRepaint(_DiagonalLinePainter old) => false;
}

class _RadialBurstPainter extends CustomPainter {
  final Color color;
  const _RadialBurstPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 0.8;
    final center = Offset(size.width * 0.6, size.height * 0.55);
    for (int i = 0; i < 20; i++) {
      final angle = (i / 20) * math.pi * 2;
      final end = Offset(center.dx + math.cos(angle) * size.width, center.dy + math.sin(angle) * size.width);
      canvas.drawLine(center, end, paint);
    }
  }

  @override bool shouldRepaint(_RadialBurstPainter old) => false;
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double size, thickness;
  final bool flipX, flipY;
  const _CornerPainter({required this.color, required this.size, required this.thickness, required this.flipX, required this.flipY});

  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()..color = color..strokeWidth = thickness..style = PaintingStyle.stroke;
    final x = flipX ? s.width : 0.0;
    final y = flipY ? s.height : 0.0;
    final dx = flipX ? -size : size;
    final dy = flipY ? -size : size;
    final path = Path()
      ..moveTo(x + dx, y)
      ..lineTo(x, y)
      ..lineTo(x, y + dy);
    canvas.drawPath(path, paint);
  }

  @override bool shouldRepaint(_CornerPainter old) => false;
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const _DashedBorderPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    const dashLen = 5.0;
    const gapLen  = 4.0;

    // Draw dashed rectangle (square corners)
    final path = Path()..addRect(Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1));
    final metric = path.computeMetrics().first;
    final total  = metric.length;
    double d = 0;
    while (d < total) {
      canvas.drawPath(metric.extractPath(d, math.min(d + dashLen, total)), paint);
      d += dashLen + gapLen;
    }

    // Glow on dashed border
    final glowPaint = Paint()
      ..color = color.withOpacity(0.4)
      ..strokeWidth = strokeWidth + 2
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawRect(Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1), glowPaint);
  }

  @override bool shouldRepaint(_DashedBorderPainter old) => false;
}

/// Floating petal particles for Seasonal card
class _PetalParticles extends StatelessWidget {
  const _PetalParticles();

  static const _petals = [
    (0.15, 0.25), (0.72, 0.18), (0.85, 0.42), (0.08, 0.55),
    (0.6,  0.63), (0.38, 0.72), (0.9,  0.75), (0.25, 0.88),
    (0.55, 0.35), (0.78, 0.55),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: HanjCard.kWidth, height: HanjCard.kHeight,
        child: Stack(
          children: _petals.map((p) {
            return Positioned(
              left: p.$1 * HanjCard.kWidth,
              top:  p.$2 * HanjCard.kHeight,
              child: Transform.rotate(
                angle: p.$1 * 2.5,
                child: Container(
                  width: 8, height: 14,
                  decoration: const BoxDecoration(
                    color: Color(0xFFC4A0AA),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6), topRight: Radius.circular(6),
                      bottomLeft: Radius.circular(2), bottomRight: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARD CATALOGUE — all 30 cards pre-defined
// ─────────────────────────────────────────────────────────────────────────────

class HanjCardCatalogue {
  static const List<HanjCardData> all = [
    // ── Common ──────────────────────────────────────────────────────────────
    HanjCardData(id: 'first_pull',      name: 'First Pull',        description: 'Every collection starts somewhere.',          rarity: CardRarity.common,    category: 'ÆTHER',    kanji: 'ハ', cardNumber: 1),
    HanjCardData(id: 'the_list_begins', name: 'The List Begins',   description: 'Ten worlds queued and waiting.',               rarity: CardRarity.common,    category: 'ÆTHER',    kanji: '十', cardNumber: 2),
    HanjCardData(id: 'rated',           name: 'Rated',             description: 'You have opinions. Share them.',               rarity: CardRarity.common,    category: 'ÆTHER',    kanji: '評', cardNumber: 3),
    HanjCardData(id: 'genre_curious',   name: 'Genre Curious',     description: 'Three genres explored. The surface scratched.', rarity: CardRarity.common,   category: 'ÆTHER',    kanji: '探', cardNumber: 4),

    // ── Rare ─────────────────────────────────────────────────────────────────
    HanjCardData(id: 'decade_hopper',   name: 'Decade Hopper',     description: 'From classic to current — you respect the lineage.', rarity: CardRarity.rare, category: 'LINEAGE', kanji: '流', cardNumber: 214),
    HanjCardData(id: 'the_critic',      name: 'The Critic',        description: 'Ten opinions on record.',                     rarity: CardRarity.rare,      category: 'TASTE',    kanji: '評', cardNumber: 215),
    HanjCardData(id: 'binge_mode',      name: 'Binge Mode',        description: 'Five anime. One month. No regrets.',           rarity: CardRarity.rare,      category: 'WATCHER',  kanji: '速', cardNumber: 216),
    HanjCardData(id: 'loyal',           name: 'Loyal',             description: 'Three months active. The habit is real.',      rarity: CardRarity.rare,      category: 'STREAK',   kanji: '継', cardNumber: 217),
    HanjCardData(id: 'action_purist',   name: 'Action Purist',     description: 'Ten action anime completed.',                  rarity: CardRarity.rare,      category: 'GENRE',    kanji: '闘', cardNumber: 218),
    HanjCardData(id: 'romance_soul',    name: 'Romance Soul',      description: 'Ten romance anime completed.',                 rarity: CardRarity.rare,      category: 'GENRE',    kanji: '愛', cardNumber: 219),
    HanjCardData(id: 'slice_of_life',   name: 'Slice of Life Soul',description: 'Ten slice-of-life completed.',                 rarity: CardRarity.rare,      category: 'GENRE',    kanji: '日', cardNumber: 220),
    HanjCardData(id: 'fantasy_lord',    name: 'Fantasy Lord',      description: 'Ten fantasy anime completed.',                 rarity: CardRarity.rare,      category: 'GENRE',    kanji: '幻', cardNumber: 221),

    // ── Epic ─────────────────────────────────────────────────────────────────
    HanjCardData(id: 'the_50_club',     name: 'The 50 Club',       description: 'Fifty worlds completed. You are not a casual.', rarity: CardRarity.epic,     category: 'DEVOTION', kanji: '心', cardNumber: 50),
    HanjCardData(id: 'genre_lord',      name: 'Genre Lord',        description: 'Twenty anime in a single genre. Mastery.',     rarity: CardRarity.epic,      category: 'GENRE',    kanji: '王', cardNumber: 51),
    HanjCardData(id: 'harsh_critic',    name: 'Harsh Critic',      description: 'Average rating under 6. Standards are high.',  rarity: CardRarity.epic,      category: 'TASTE',    kanji: '厳', cardNumber: 52),
    HanjCardData(id: 'the_optimist',    name: 'The Optimist',      description: 'Average rating over 8.5. Everything is good.', rarity: CardRarity.epic,      category: 'TASTE',    kanji: '楽', cardNumber: 53),
    HanjCardData(id: 'decade_scholar',  name: 'Decade Scholar',    description: 'Anime from five different decades witnessed.', rarity: CardRarity.epic,      category: 'LINEAGE',  kanji: '学', cardNumber: 54),
    HanjCardData(id: 'cant_let_go',     name: "Can't Let Go",      description: 'Dropped and re-added. You already know.',      rarity: CardRarity.epic,      category: 'DEVOTION', kanji: '執', cardNumber: 55),

    // ── Legendary ────────────────────────────────────────────────────────────
    HanjCardData(id: 'the_100_club',    name: 'The Century Mark',  description: 'One hundred worlds witnessed. The mark, earned in fire.', rarity: CardRarity.legendary, category: 'MANGA CUT', kanji: '百', cardNumber: 100),
    HanjCardData(id: 'year_of_anime',   name: 'Year of Anime',     description: 'Active every month for twelve months.',        rarity: CardRarity.legendary,  category: 'STREAK',   kanji: '年', cardNumber: 365),
    HanjCardData(id: 'obsessed',        name: 'Obsessed',          description: 'Ten anime in one month. There is no cure.',    rarity: CardRarity.legendary,  category: 'DEVOTION', kanji: '狂', cardNumber: 999),
    HanjCardData(id: 'all_seasons',     name: 'All Seasons',       description: 'Spring, Summer, Fall, Winter. All witnessed.', rarity: CardRarity.legendary,  category: 'SEASONAL', kanji: '季', cardNumber: 4),

    // ── Seasonal ─────────────────────────────────────────────────────────────
    HanjCardData(id: 'spring_2026',     name: 'Spring 2026 Watcher', description: "You were here for Spring 2026. This card doesn't come back.", rarity: CardRarity.seasonal, category: 'SEASON', kanji: '季', cardNumber: 237, totalCount: 2400),
    HanjCardData(id: 'winter_arc',      name: 'Winter Arc',        description: 'Five anime in December–January.',              rarity: CardRarity.seasonal,   category: 'SEASON',   kanji: '冬', cardNumber: 88,  totalCount: 1200),
    HanjCardData(id: 'golden_week',     name: 'Golden Week Marathon', description: 'Two anime during Golden Week.',             rarity: CardRarity.seasonal,   category: 'SEASON',   kanji: '金', cardNumber: 312, totalCount: 800),

    // ── Secret ───────────────────────────────────────────────────────────────
    HanjCardData(id: 'ghost_past',      name: 'Ghost of Seasons Past', description: 'Completed on the anniversary of its air date.', rarity: CardRarity.secret, category: 'SECRET', kanji: '霊', cardNumber: 0),
    HanjCardData(id: 'the_purist',      name: 'The Purist',        description: 'Original and remake. You honour the source.',   rarity: CardRarity.secret,    category: 'SECRET',   kanji: '純', cardNumber: 0),
    HanjCardData(id: 'time_traveller',  name: 'Time Traveller',    description: 'Anime from five different decades.',            rarity: CardRarity.secret,    category: 'SECRET',   kanji: '時', cardNumber: 0),
    HanjCardData(id: 'dropout',         name: 'Dropout',           description: 'Ten dropped. No shame — taste is selective.',   rarity: CardRarity.secret,    category: 'SECRET',   kanji: '落', cardNumber: 0),
    HanjCardData(id: 'resurrection',    name: 'Resurrection',      description: 'Dropped and completed the same anime.',         rarity: CardRarity.secret,    category: 'SECRET',   kanji: '復', cardNumber: 0),
    HanjCardData(id: 'the_long_game',   name: 'The Long Game',     description: 'Plan to Watch for over a year. Patience rewarded.', rarity: CardRarity.secret, category: 'SECRET', kanji: '待', cardNumber: 0),
    HanjCardData(id: 'cant_let_go_s',   name: "Can't Let Go",      description: 'Dropped and re-added the same anime.',          rarity: CardRarity.secret,    category: 'SECRET',   kanji: '執', cardNumber: 0),
  ];
}
