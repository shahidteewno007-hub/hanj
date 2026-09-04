import 'dart:math' as math;

import 'cadre_fighter.dart';
import 'cadre_pool.dart';

/// How a squad match ended.
enum CadreSquadOutcome { playerWins, opponentWins, tie }

enum CadreSquadPhase {
  /// A card is face up and waiting to be placed or passed.
  placing,

  /// Both squads are full. Scores on the table.
  done,
}

/// Squad: draft five, assign roles, best total takes it.
///
/// Cards arrive one at a time, blind. Each one is either placed in an open
/// slot **immediately and permanently**, or passed and gone for good. The
/// whole game is the question "do I lock this 88 into Captain now, or hold
/// the slot open hoping for a 95" — so nothing is ever re-arranged later.
///
/// [drawsPerSide] is deliberately larger than the number of slots. With five
/// draws for five slots every card gets placed, which means the total is
/// decided by the deal and the player only chooses the weighting: perfect
/// play beat careless play just 59% of the time, and a weaker hand overcame a
/// stronger one 18% of the time. At eight draws those become 87% and 73%.
/// The three spare cards are what turn an assignment puzzle into a game.
class CadreSquadMatch {
  /// Cards dealt to each side. Three more than there are slots.
  static const int drawsPerSide = 8;

  /// Smallest pool that can deal both sides a full run of draws.
  static const int minRosterSize = drawsPerSide * 2;

  /// What each slot is worth. Captain carries a squad; Support pads it.
  static const Map<String, double> weights = <String, double>{
    CadreSlots.captain: 1.3,
    CadreSlots.vice: 1.15,
    CadreSlots.tank: 1.0,
    CadreSlots.healer: 0.9,
    CadreSlots.support: 0.8,
  };

  final String rosterTitle;
  final List<CadreFighter> playerDeck;
  final List<CadreFighter> opponentDeck;

  final Map<String, CadreFighter> playerSquad = <String, CadreFighter>{};
  final Map<String, CadreFighter> opponentSquad = <String, CadreFighter>{};

  /// Cards passed over, kept only so the end screen can show what you let go.
  final List<CadreFighter> playerPassed = <CadreFighter>[];
  final List<CadreFighter> opponentPassed = <CadreFighter>[];

  int playerDrawn = 0;
  int opponentDrawn = 0;

  CadreSquadPhase phase = CadreSquadPhase.placing;

  CadreSquadMatch._({
    required this.rosterTitle,
    required this.playerDeck,
    required this.opponentDeck,
  });

  factory CadreSquadMatch.deal(CadrePool pool, {math.Random? random}) {
    if (pool.length < minRosterSize) {
      throw ArgumentError(
        '${pool.title} only has ${pool.length} usable characters. '
        'Squad needs at least $minRosterSize. Add another anime to the pool.',
      );
    }

    final rng = random ?? math.Random();
    final shuffled = List<CadreFighter>.of(pool.fighters)..shuffle(rng);

    final player = <CadreFighter>[];
    final opponent = <CadreFighter>[];
    for (var i = 0; i < drawsPerSide * 2; i++) {
      (i.isEven ? player : opponent).add(shuffled[i]);
    }

    return CadreSquadMatch._(
      rosterTitle: pool.title,
      playerDeck: player,
      opponentDeck: opponent,
    );
  }

  /// The card currently face up, or null once the squad is settled.
  CadreFighter? get playerCard =>
      playerDrawn < playerDeck.length ? playerDeck[playerDrawn] : null;

  List<String> get openSlots =>
      CadreSlots.all.where((s) => !playerSquad.containsKey(s)).toList();

  int get drawsLeft => playerDeck.length - playerDrawn;

  /// True when passing is no longer allowed: every remaining draw is needed
  /// to fill a slot, so the current card has to go somewhere.
  bool get mustPlace => drawsLeft <= openSlots.length;

  bool get canPass => !mustPlace && openSlots.isNotEmpty;

  /// Places the face-up card. The assignment is final.
  void place(String slot) {
    if (phase != CadreSquadPhase.placing) return;
    final card = playerCard;
    if (card == null || playerSquad.containsKey(slot)) return;
    playerSquad[slot] = card;
    playerDrawn++;
    _settleIfDone();
  }

  /// Lets the face-up card go. It does not come back.
  void pass() {
    if (phase != CadreSquadPhase.placing || !canPass) return;
    playerPassed.add(playerDeck[playerDrawn]);
    playerDrawn++;
    _settleIfDone();
  }

  void _settleIfDone() {
    if (playerSquad.length < CadreSlots.all.length) return;
    _runOpponent();
    phase = CadreSquadPhase.done;
  }

  /// The bot drafts its own squad under the same rules.
  ///
  /// Its cutoffs come from the pool it is actually drafting from rather than
  /// from fixed numbers: a cast whose strongest character is 80 should still
  /// field a Captain, and a fixed threshold of 88 would leave the slot empty
  /// until the must-place rule dumped something into it.
  void _runOpponent() {
    final sample = List<int>.of(opponentDeck.map((f) => f.power))..sort();
    int at(double q) => sample[(q * (sample.length - 1)).round()];

    final cuts = <String, int>{
      CadreSlots.captain: at(0.85),
      CadreSlots.vice: at(0.65),
      CadreSlots.tank: at(0.45),
      CadreSlots.healer: at(0.25),
      CadreSlots.support: 0,
    };

    var drawn = 0;
    final open = List<String>.of(CadreSlots.all);
    while (drawn < opponentDeck.length && open.isNotEmpty) {
      final card = opponentDeck[drawn];
      final left = opponentDeck.length - drawn - 1;
      final forced = left < open.length;

      String? target;
      var best = double.negativeInfinity;
      for (final slot in open) {
        if (card.power < (cuts[slot] ?? 0)) continue;
        // Among the slots this card is good enough for, take the one it is
        // actually worth the most in. With no affinity data that is always
        // the highest-weight slot it qualifies for, which is exactly what the
        // old first-match-wins loop picked — so an untyped cast drafts
        // bit-for-bit as before. With affinity, the bot drafts for fit rather
        // than handing the medic the captaincy.
        final value = contribution(card, slot);
        if (value > best) {
          best = value;
          target = slot;
        }
      }
      // The forced fallback stays the lowest-value open slot rather than the
      // best-fitting one. A card that qualified for nothing is being dumped,
      // and dumping it into Captain would spend the squad's most valuable
      // seat on its worst card. This is the line that guarantees no slot is
      // ever left empty, so it is deliberately untouched.
      target ??= forced ? open.last : null;

      if (target == null) {
        opponentPassed.add(card);
      } else {
        opponentSquad[target] = card;
        open.remove(target);
      }
      drawn++;
    }
    opponentDrawn = drawn;
  }

  /// What one character contributes in one slot.
  ///
  /// [CadreFighter.roleAffinity] is uniform until the rankings carry real
  /// affinity values, so folding it in beforehand would scale every squad by
  /// the same constant and do nothing but shrink the numbers. It switches on
  /// per character, the moment that character has real data behind it.
  static double contribution(CadreFighter fighter, String slot) {
    return fighter.power * affinityOf(fighter, slot) * (weights[slot] ?? 1.0);
  }

  /// The per-slot multiplier, or 1.0 while a character has no real affinity.
  ///
  /// This used to key off [CadreFighter.enriched], which was wrong. `enriched`
  /// means "found in the rankings table", and that table carries power values
  /// only — `withRankedPower` sets the flag through `copyWith` and leaves
  /// `roleAffinity` sitting at the uniform 0.75 default. So every ranked
  /// character paid a 0.75 multiplier that unranked characters never paid: a
  /// ranked 98 contributed 96 as Captain while an unranked 90 contributed 117.
  /// The table exists to get the strongest characters right and Squad was
  /// docking exactly those characters a quarter of their strength.
  ///
  /// Keying off the affinity data itself restores what the doc above always
  /// claimed: uniform affinity is skipped, and real per-slot values switch on
  /// per character the moment they exist. Nothing else has to change when the
  /// rankings start carrying them.
  static double affinityOf(CadreFighter fighter, String slot) {
    if (hasRealAffinity(fighter)) return fighter.roleAffinity[slot] ?? 0.75;
    return 1.0;
  }

  /// True once a character carries per-slot values that aren't the flat
  /// default. Compared by content rather than identity, so an affinity map
  /// rebuilt from JSON still reads as default when its values are default.
  static bool hasRealAffinity(CadreFighter fighter) {
    final affinity = fighter.roleAffinity;
    for (final slot in CadreSlots.all) {
      if (affinity[slot] != CadreFighter.defaultAffinity[slot]) return true;
    }
    return false;
  }

  static int scoreOf(Map<String, CadreFighter> squad) {
    var total = 0.0;
    squad.forEach((slot, fighter) => total += contribution(fighter, slot));
    return total.round();
  }

  int get playerScore => scoreOf(playerSquad);
  int get opponentScore => scoreOf(opponentSquad);

  CadreSquadOutcome get outcome {
    if (playerScore > opponentScore) return CadreSquadOutcome.playerWins;
    if (opponentScore > playerScore) return CadreSquadOutcome.opponentWins;
    return CadreSquadOutcome.tie;
  }
}
