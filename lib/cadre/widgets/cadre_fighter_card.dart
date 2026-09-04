import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cadre_fighter.dart';
import 'cadre_frame.dart';

/// Hanj tokens, restated locally so Cadre never imports from the card
/// collection widgets. Alpha is baked into the hex values on purpose — no
/// withOpacity calls, so this file stays clean across Flutter versions.
class CadreColors {
  static const bg = Color(0xFF0A0A0A);
  static const coral = Color(0xFFE8624A);
  static const ember = Color(0xFFF97316);
  static const ivory = Color(0xFFF3EEE7);

  static const ivoryDim = Color(0xB3F3EEE7);
  static const ivoryFaint = Color(0x66F3EEE7);
  static const hairline = Color(0x1AF3EEE7);
  static const coralEdge = Color(0x59E8624A);
  static const scrimTop = Color(0x00000000);
  static const scrimMid = Color(0x99000000);
  static const scrimLow = Color(0xF00A0A0A);
  static const surface = Color(0xFF141210);
}

/// A single drafted character.
///
/// Every dimension is derived from the width the parent hands down, so this
/// card cannot overflow the way a fixed-pixel layout does. Drop it in a grid,
/// a row, or a full-bleed reveal and it just resolves.
class CadreFighterCard extends StatelessWidget {
  final CadreFighter fighter;

  /// Hides the identity for Clash reveals.
  final bool faceDown;

  /// Set false to hide the power value during a blind draw.
  final bool showPower;

  /// Displayed instead of the real power while a reveal counts it up. The
  /// frame still reads the true value, so the tier never flickers.
  final int? powerOverride;

  final bool highlighted;
  final VoidCallback? onTap;

  const CadreFighterCard({
    super.key,
    required this.fighter,
    this.faceDown = false,
    this.showPower = true,
    this.powerOverride,
    this.highlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final radius = w * 0.075;
          final pad = w * 0.065;

          final tier = faceDown
              ? CadreTier.base
              : cadreTierFor(fighter.power);

          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: CadreColors.surface,
                borderRadius: BorderRadius.circular(radius),
                boxShadow: highlighted
                    ? const [
                        BoxShadow(
                          color: Color(0x59E8624A),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                      ]
                    : (tier == CadreTier.apex
                        ? const [
                            BoxShadow(
                              color: Color(0x33F97316),
                              blurRadius: 18,
                            ),
                          ]
                        : null),
              ),
              child: CustomPaint(
                // The frame always tells the truth about power. A push shows
                // through the glow and the +25 label, never by borrowing a
                // tier the character hasn't earned.
                foregroundPainter: CadreFramePainter(
                  tier: tier,
                  radius: radius,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: faceDown
                      ? _FaceDown(width: w)
                      : _FaceUp(
                          fighter: fighter,
                          width: w,
                          pad: pad,
                          showPower: showPower,
                          powerOverride: powerOverride,
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FaceUp extends StatelessWidget {
  final CadreFighter fighter;
  final double width;
  final double pad;
  final bool showPower;
  final int? powerOverride;

  const _FaceUp({
    required this.fighter,
    required this.width,
    required this.pad,
    required this.showPower,
    this.powerOverride,
  });

  @override
  Widget build(BuildContext context) {
    final nameSize = (width * 0.095).clamp(11.0, 21.0);
    final metaSize = (width * 0.062).clamp(8.0, 13.0);
    final powerSize = (width * 0.155).clamp(16.0, 38.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: fighter.imageUrl,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          fadeInDuration: const Duration(milliseconds: 180),
          placeholder: (_, __) => const ColoredBox(color: CadreColors.surface),
          errorWidget: (_, __, ___) => ColoredBox(
            color: CadreColors.surface,
            child: Center(
              child: Icon(
                Icons.person_outline,
                color: CadreColors.ivoryFaint,
                size: width * 0.28,
              ),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0.35, 0.68, 1.0],
              colors: [
                CadreColors.scrimTop,
                CadreColors.scrimMid,
                CadreColors.scrimLow,
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        if (showPower)
          Positioned(
            top: pad,
            right: pad,
            child: _PowerBadge(
              value: powerOverride ?? fighter.power,
              size: powerSize,
              width: width,
            ),
          ),
        Positioned(
          left: pad,
          right: pad,
          bottom: pad,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fighter.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.playfairDisplay(
                  color: CadreColors.ivory,
                  fontSize: nameSize,
                  height: 1.12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: width * 0.028),
              Text(
                fighter.role == CadreRole.main
                    ? 'Lead'
                    : (fighter.role == CadreRole.supporting
                        ? 'Supporting'
                        : 'Background'),
                style: GoogleFonts.dmSans(
                  color: fighter.role == CadreRole.main
                      ? CadreColors.coral
                      : CadreColors.ivoryDim,
                  fontSize: metaSize,
                  letterSpacing: width * 0.006,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The power value is the one loud thing on the card. Everything else stays
/// quiet so this reads first during a reveal.
class _PowerBadge extends StatelessWidget {
  final int value;
  final double size;
  final double width;

  const _PowerBadge({
    required this.value,
    required this.size,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: GoogleFonts.spaceGrotesk(
            color: CadreColors.ivory,
            fontSize: size,
            height: 1.0,
            fontWeight: FontWeight.w700,
            shadows: const [
              Shadow(color: Color(0xCC000000), blurRadius: 12),
            ],
          ),
        ),
        SizedBox(height: width * 0.018),
        Container(
          width: size * 0.9,
          height: (width * 0.012).clamp(1.5, 3.5),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [CadreColors.ember, CadreColors.coral],
            ),
          ),
        ),
      ],
    );
  }
}

class _FaceDown extends StatelessWidget {
  final double width;
  const _FaceDown({required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF151210), Color(0xFF0A0A0A)],
        ),
      ),
      child: Center(
        child: Text(
          '\u72D0',
          style: TextStyle(
            color: CadreColors.coralEdge,
            fontSize: width * 0.34,
          ),
        ),
      ),
    );
  }
}
