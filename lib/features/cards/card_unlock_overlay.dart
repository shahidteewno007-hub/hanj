import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'hanj_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Card Unlock Overlay
// Call showCardUnlockOverlay() when a card is earned.
// cardId must match a card in HanjCardCatalogue.all — the overlay looks it up
// and renders the actual HanjCard widget with flip animation.
// Falls back to a generic card if cardId is not found.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showCardUnlockOverlay(
  BuildContext context, {
  required String cardId,
  // Fallback fields used only if cardId isn't in the catalogue
  String cardName        = '',
  String cardDescription = '',
  String rarity          = 'common',
}) {
  // Look up in catalogue
  HanjCardData? found;
  try {
    found = HanjCardCatalogue.all.firstWhere((c) => c.id == cardId);
  } catch (_) {
    found = null;
  }

  // Build a fallback if not found
  final card = found ?? HanjCardData(
    id:          cardId,
    name:        cardName.isNotEmpty ? cardName : cardId,
    description: cardDescription,
    rarity:      CardRarity.values.firstWhere(
      (r) => r.name == rarity,
      orElse:    () => CardRarity.common,
    ),
    category:    'HANJ',
    kanji:       '道',
    cardNumber:  0,
  );

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.9),
    transitionDuration: const Duration(milliseconds: 400),
    transitionBuilder: (_, anim, __, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween(begin: 0.88, end: 1.0).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
        ),
        child: child,
      ),
    ),
    pageBuilder: (ctx, _, __) => _CardUnlockPage(card: card),
  );
}

// ─────────────────────────────────────────────────────────────────────────────

class _CardUnlockPage extends StatefulWidget {
  final HanjCardData card;
  const _CardUnlockPage({required this.card});

  @override
  State<_CardUnlockPage> createState() => _CardUnlockPageState();
}

class _CardUnlockPageState extends State<_CardUnlockPage>
    with TickerProviderStateMixin {

  late final AnimationController _flipCtrl;
  late final AnimationController _particleCtrl;
  late final AnimationController _contentCtrl;

  late final Animation<double> _flipAnim;
  late final Animation<double> _glowAnim;
  late final Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();

    _flipCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

    _particleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2500))
      ..repeat();

    _contentCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));

    _flipAnim = CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutCubic);

    _glowAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _particleCtrl, curve: Curves.easeInOut));

    _contentFade = CurvedAnimation(parent: _contentCtrl, curve: Curves.easeOut);

    // Sequence: pause → flip → show text
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _flipCtrl.forward().then((_) {
        if (mounted) _contentCtrl.forward();
      });
    });
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    _particleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Color get _color => widget.card.rarityColor;

  String get _rarityEmoji {
    switch (widget.card.rarity) {
      case CardRarity.legendary: return '🌟';
      case CardRarity.epic:      return '💜';
      case CardRarity.rare:      return '💙';
      case CardRarity.seasonal:  return '🌸';
      case CardRarity.secret:    return '🔮';
      default:                   return '🃏';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Stack(
          fit: StackFit.expand,
          children: [

            // ── Particle field ───────────────────────────────────────────
            AnimatedBuilder(
              animation: _particleCtrl,
              builder: (_, __) => CustomPaint(
                painter: _ParticlePainter(
                  progress: _particleCtrl.value,
                  color: _color,
                ),
              ),
            ),

            // ── Radial glow behind card ──────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: _glowAnim,
                builder: (_, __) => Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _color.withValues(alpha: 0.18 * _glowAnim.value),
                        blurRadius: 140,
                        spreadRadius: 60,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Main content ─────────────────────────────────────────────
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  // "CARD UNLOCKED" label
                  FadeTransition(
                    opacity: _contentFade,
                    child: Text(
                      'CARD UNLOCKED',
                      style: AppTheme.mono(
                        fontSize: 11,
                        color: _color,
                        letterSpacing: 3.0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Card flip ────────────────────────────────────────
                  AnimatedBuilder(
                    animation: _flipAnim,
                    builder: (_, __) {
                      final angle     = _flipAnim.value * pi;
                      final showFront = angle > pi / 2;
                      final tAngle    = showFront ? angle - pi : angle;

                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(tAngle),
                        child: showFront ? _cardFront() : _cardBack(),
                      );
                    },
                  ),

                  const SizedBox(height: 28),

                  // Rarity badge
                  FadeTransition(
                    opacity: _contentFade,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_rarityEmoji,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                          widget.card.rarity.name.toUpperCase(),
                          style: AppTheme.mono(
                            fontSize: 12,
                            color: _color,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 44),

                  // Dismiss hint
                  FadeTransition(
                    opacity: _contentFade,
                    child: Text(
                      'tap to dismiss',
                      style: AppTheme.mono(
                        fontSize: 9,
                        color: Colors.white.withValues(alpha: 0.25),
                        letterSpacing: 1.5,
                      ),
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

  Widget _cardFront() {
    return HanjCard(
      card: widget.card,
      isUnlocked: true,
      width: HanjCard.kWidth,
      height: HanjCard.kHeight,
    );
  }

  Widget _cardBack() {
    return Container(
      width: HanjCard.kWidth,
      height: HanjCard.kHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0806),
        border: Border.all(
          color: _color.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Image.asset(
          'assets/images/hanj_wing_transparent.png',
          width: 56,
          height: 56,
          color: _color.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Particle painter
// ─────────────────────────────────────────────────────────────────────────────

class _ParticlePainter extends CustomPainter {
  final double progress;
  final Color  color;

  _ParticlePainter({required this.progress, required this.color});

  static final _rand = Random(42);
  static final _pts  = List.generate(35, (_) => (
    x:      _rand.nextDouble(),
    y:      _rand.nextDouble(),
    size:   _rand.nextDouble() * 2.5 + 1.0,
    speed:  _rand.nextDouble() * 0.25 + 0.08,
    offset: _rand.nextDouble(),
  ));

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in _pts) {
      final t     = ((progress * p.speed + p.offset) % 1.0);
      final alpha = (1.0 - t) * 0.55;
      paint.color = color.withValues(alpha: alpha * 0.45);
      canvas.drawCircle(
        Offset(p.x * size.width, size.height * (1.0 - t)),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}
