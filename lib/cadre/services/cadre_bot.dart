import 'dart:math' as math;

/// Decides when the bot burns a Push token.
///
/// The bot only ever sees its own card, same as the player. Its edge is
/// discipline, not information: it saves tokens for cards where +15 actually
/// swings the result, and refuses to waste them on a card that already wins or
/// one that loses regardless.
class CadreBot {
  final math.Random _rng;

  CadreBot({math.Random? random}) : _rng = random ?? math.Random();

  bool shouldPush({
    required int ownPower,
    required int pushesLeft,
    required int roundsLeft,
    required int cardDeficit,
  }) {
    if (pushesLeft <= 0) return false;

    // Tokens expire worthless. Spend them rather than lose them.
    if (roundsLeft <= pushesLeft) return true;

    // A strong card rarely needs help; a weak one is usually beyond saving.
    final inSwingRange = ownPower >= 58 && ownPower <= 86;
    if (!inSwingRange) return _rng.nextDouble() < 0.05;

    var chance = 0.35;

    // Behind on cards, push harder.
    if (cardDeficit >= 4) {
      chance += 0.25;
    } else if (cardDeficit >= 2) {
      chance += 0.12;
    }

    // Late in the match every round matters more.
    if (roundsLeft <= 3) chance += 0.15;

    return _rng.nextDouble() < chance.clamp(0.0, 0.9);
  }

  /// Burns its skip on a card weak enough to be worth throwing away.
  ///
  /// A skipped card is gone for good now, so there is no reason to hoard the
  /// token for later — the only question is whether this card is bad enough.
  bool shouldSkip({
    required int ownPower,
    required int skipsLeft,
  }) {
    if (skipsLeft <= 0) return false;
    if (ownPower >= 58) return false;
    return ownPower <= 48 || _rng.nextDouble() < 0.5;
  }
}
