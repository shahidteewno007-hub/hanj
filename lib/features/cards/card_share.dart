// card_share.dart
//
// Shareable card feature for Hanj.
// Renders a card onto a branded, story-format (9:16) canvas, lets the user
// preview it, then share to any app (IG / Snap / Twitter / WhatsApp) or save
// to the gallery.
//
// ── SETUP ─────────────────────────────────────────────────────────────────
// Add to pubspec.yaml dependencies (gal you already have):
//   share_plus: ^10.0.0
//   path_provider: ^2.1.0
// Then: flutter pub get
//
// This file lives in the SAME folder as hanj_card.dart, so the import below
// works as-is.
import 'hanj_card.dart' as hc;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';

// ── Brand constants ─────────────────────────────────────────────────────────
const _kBg     = Color(0xFF0A0A0A);
const _kIvory  = Color(0xFFF3EEE7);
const _kCoral  = Color(0xFFF97316);
const _kCoral2 = Color(0xFFE8624A);
const _kMuted  = Color(0xFF6B6B6B);

// ════════════════════════════════════════════════════════════════════════════
//  PUBLIC ENTRY — call this from the card detail sheet's "Share" button.
//  accentColor + rarityLabel come straight from the caller (e.g. rarity.color
//  and rarity.label), so this file never has to know about the rarity enum.
// ════════════════════════════════════════════════════════════════════════════
void openCardShare(
  BuildContext context, {
  required hc.HanjCardData card,
  required Color accentColor,
  required String rarityLabel,
  String? collectorHandle, // e.g. "@shahid" — optional, shown small if provided
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CardSharePreviewScreen(
        card: card,
        accentColor: accentColor,
        rarityLabel: rarityLabel,
        collectorHandle: collectorHandle,
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  PREVIEW SCREEN
// ════════════════════════════════════════════════════════════════════════════
class CardSharePreviewScreen extends StatefulWidget {
  final hc.HanjCardData card;
  final Color accentColor;
  final String rarityLabel;
  final String? collectorHandle;
  const CardSharePreviewScreen({
    super.key,
    required this.card,
    required this.accentColor,
    required this.rarityLabel,
    this.collectorHandle,
  });

  @override
  State<CardSharePreviewScreen> createState() => _CardSharePreviewScreenState();
}

class _CardSharePreviewScreenState extends State<CardSharePreviewScreen> {
  final GlobalKey _boundaryKey = GlobalKey();
  bool _busy = false;

  // ── Capture the canvas to PNG bytes ──────────────────────────────────────
  Future<Uint8List> _capture() async {
    // The canvas is already on screen in the preview, so its Google Fonts are
    // loaded by the time the user taps a button. A short delay just makes sure
    // layout is fully settled before we rasterise.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final boundary = _boundaryKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    // 3.2x → a 340×604 canvas becomes ~1088×1933, ideal for stories.
    final image = await boundary.toImage(pixelRatio: 3.2);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      final dir = await getTemporaryDirectory();
      final file = await File('${dir.path}/hanj_${widget.card.id}.png')
          .writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Pulled "${widget.card.name}" on Hanj ⚡',
      );
    } catch (e) {
      _toast('Could not share — try again');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/hanj_${widget.card.id}.png';
      await File(path).writeAsBytes(bytes);
      await Gal.putImage(path, album: 'Hanj');
      _toast('Saved to gallery');
    } on GalException catch (_) {
      _toast('Gallery permission needed');
    } catch (e) {
      _toast('Could not save — try again');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.dmSans(color: _kIvory)),
        backgroundColor: const Color(0xFF1A1A18),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: _kIvory),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    'SHARE CARD',
                    style: GoogleFonts.spaceGrotesk(
                      color: _kMuted,
                      fontSize: 12,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Preview (the exact thing that gets captured)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: _ShareCanvas(
                        card: widget.card,
                        accentColor: widget.accentColor,
                        rarityLabel: widget.rarityLabel,
                        collectorHandle: widget.collectorHandle,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Save',
                      icon: Icons.download_rounded,
                      filled: false,
                      onTap: _save,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: _ActionButton(
                      label: 'Share',
                      icon: Icons.ios_share_rounded,
                      filled: true,
                      onTap: _share,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  THE BRANDED CANVAS — fixed 340×604 (9:16). This is what gets rasterised.
// ════════════════════════════════════════════════════════════════════════════
class _ShareCanvas extends StatelessWidget {
  final hc.HanjCardData card;
  final Color accentColor;
  final String rarityLabel;
  final String? collectorHandle;
  const _ShareCanvas({
    required this.card,
    required this.accentColor,
    required this.rarityLabel,
    this.collectorHandle,
  });

  @override
  Widget build(BuildContext context) {
    final glow = accentColor;

    return Container(
      width: 340,
      height: 604,
      decoration: const BoxDecoration(color: _kBg),
      child: Stack(
        children: [
          // Rarity-tinted radial glow behind the card
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 0.9,
                  colors: [glow.withOpacity(0.16), Colors.transparent],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),
          ),
          // Faint grid texture
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Eyebrow
              Text(
                rarityLabel,
                style: GoogleFonts.spaceGrotesk(
                  color: glow,
                  fontSize: 11,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),

              // The hero — card scaled up 1.15x via the OverflowBox pattern
              // (passing a small width/height straight to HanjCard breaks its
              // internal sizing, so we let it lay out at natural size and scale
              // the rendered output instead).
              SizedBox(
                width: hc.HanjCard.kWidth * 1.15,
                height: hc.HanjCard.kHeight * 1.15,
                child: OverflowBox(
                  minWidth: hc.HanjCard.kWidth,
                  maxWidth: hc.HanjCard.kWidth,
                  minHeight: hc.HanjCard.kHeight,
                  maxHeight: hc.HanjCard.kHeight,
                  child: Transform.scale(
                    scale: 1.15,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: glow.withOpacity(0.20),
                            blurRadius: 30,
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      child: hc.HanjCard(card: card, isUnlocked: true),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              // Card name — fixed height so 1-line and 2-line names sit at the
              // same vertical position across every card.
              SizedBox(
                height: 62,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        card.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(
                          color: _kIvory,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          fontStyle: FontStyle.italic,
                          height: 1.15,
                        ),
                      ),
                      if (collectorHandle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${collectorHandle!}\u2019s collection',
                          style: GoogleFonts.dmSans(color: _kMuted, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 26),
              // Divider
              Container(
                width: 40,
                height: 1,
                color: _kIvory.withOpacity(0.12),
              ),
              const SizedBox(height: 16),

              // Hanj wordmark — the viral hook
              RichText(
                text: TextSpan(
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  children: const [
                    TextSpan(text: 'Han', style: TextStyle(color: _kIvory)),
                    TextSpan(text: 'j', style: TextStyle(color: _kCoral)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'collect yours',
                style: GoogleFonts.spaceGrotesk(
                  color: _kMuted,
                  fontSize: 9.5,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 26),
            ],
          ),
        ],
      ),
    );
  }
}

// Subtle background grid, faint throughout.
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kIvory.withOpacity(0.03)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Action button ────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          gradient: filled
              ? const LinearGradient(colors: [_kCoral, _kCoral2])
              : null,
          color: filled ? null : const Color(0xFF161514),
          borderRadius: BorderRadius.circular(14),
          border: filled
              ? null
              : Border.all(color: _kIvory.withOpacity(0.12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: filled ? _kBg : _kIvory),
            const SizedBox(width: 9),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                color: filled ? _kBg : _kIvory,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
