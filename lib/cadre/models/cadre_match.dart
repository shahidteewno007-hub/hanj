import 'dart:math' as math;

import 'cadre_fighter.dart';
import 'cadre_pool.dart';

enum CadreOutcome { playerWins, opponentWins, tie }

/// Who the second seat belongs to, and on what basis a round is settled.
enum CadreMode {
  /// You against the bot. Power decides. The only recorded mode.
  bot,

  /// Two people, one phone, cards hidden between turns. Power decides.
  local,

  /// Two people, one phone, both cards face up and power hidden entirely.
  ///
  /// Each side names the winner. Agreement settles it; a disagreement goes
  /// to a toss. This exists because AniList favourites measure fame rather
  /// than strength, and two people who know the source settle a matchup
  /// better than that number does.
  honor,
}

enum CadrePhase {
  /// Local play only: screen is covered while the phone changes hands.
  handoff,

  /// The active side is looking at its card and deciding whether to push.
  decision,

  /// Reveal animation is running.
  revealing,

  /// Round is settled, waiting to move on.
  resolved,

  /// Honor only: both cards are face up and the seats are naming a winner.
  voting,

  /// No cards left.
  matchOver,
}

/// One side's committed card for a round.
class CadrePlay {
  final CadreFighter fighter;
  final bool pushed;

  const CadrePlay({required this.fighter, this.pushed = false});

  int get effectivePower =>
      fighter.power + (pushed ? CadreMatch.pushBonus : 0);
}

class CadreRoundResult {
  final CadrePlay player;
  final CadrePlay opponent;
  final CadreOutcome outcome;

  /// Cards moved into the winner's pile this round, pot included.
  final int cardsTaken;

  const CadreRoundResult({
    required this.player,
    required this.opponent,
    required this.outcome,
    required this.cardsTaken,
  });
}

/// Clash match state.
///
/// [resolve] is deliberately a pure static function over two sealed plays: no
/// UI, no state, no randomness. The same call settles a round locally now and
/// inside a Cloud Function when online matches land, so the rules never get
/// written twice.
class CadreMatch {
  static const int pushBonus = 25;
  static const int pushesPerSide = 2;
  static const int skipsPerSide = 1;
  /// Cards dealt to each side. One more than [maxRounds] on purpose: the
  /// spare is what a skip spends.
  static const int maxHandSize = 11;
  static const int minRosterSize = 6;

  /// Seat indexes. 0 is the left side (you, or Player 1).
  static const int sideA = 0;
  static const int sideB = 1;

  /// Cards dealt to each side for a pool of [poolSize].
  ///
  /// Exposed so the pool picker can tell you what a cast buys you *before*
  /// you commit to it. [deal] uses the same call, so the number shown and the
  /// match you get cannot drift apart.
  static int handSizeFor(int poolSize) =>
      math.min(maxHandSize, poolSize ~/ 2);

  /// Rounds a pool of [poolSize] will actually play. Always one fewer than
  /// the hand, because the spare card is what a skip spends.
  static int roundsFor(int poolSize) => handSizeFor(poolSize) - 1;

  /// Smallest pool that still deals a full-length match. Below this the game
  /// runs short: 16 characters is 7 rounds, 12 is 5, and the [minRosterSize]
  /// floor of 6 is only 2.
  static const int fullMatchRosterSize = maxHandSize * 2;

  final String rosterTitle;
  final CadreMode mode;
  final bool crossover;

  /// Rounds this match runs. Always one fewer than the dealt hand, so a side
  /// that skips and a side that doesn't still play the same number of rounds.
  final int rounds;

  final List<CadreFighter> playerDeck;
  final List<CadreFighter> opponentDeck;

  final List<CadreFighter> playerPile = <CadreFighter>[];
  final List<CadreFighter> opponentPile = <CadreFighter>[];
  final List<CadreFighter> pot = <CadreFighter>[];

  int playerPushes = pushesPerSide;
  int opponentPushes = pushesPerSide;

  int playerSkips = skipsPerSide;
  int opponentSkips = skipsPerSide;

  CadreFighter? playerCard;
  CadreFighter? opponentCard;
  bool playerPushedThisRound = false;
  bool opponentPushedThisRound = false;
  bool playerSkippedThisRound = false;
  bool opponentSkippedThisRound = false;

  /// Honor only. Which side each seat named as the round's winner, or null
  /// before that seat has voted. Values are [sideA] / [sideB].
  int? playerVote;
  int? opponentVote;

  /// Honor only. Rounds each seat forced to a toss rather than conceding.
  ///
  /// Uncapped on purpose. Capping would force a seat that is genuinely right
  /// to concede, which is worse than the behaviour it prevents — so the tally
  /// is shown instead and the other player can draw their own conclusions.
  int playerDisputes = 0;
  int opponentDisputes = 0;

  /// True when the round on screen was settled by a toss rather than assent.
  bool lastWasToss = false;

  /// True once the ten rounds finished level and the spare cards are playing
  /// the decider.
  bool inSuddenDeath = false;

  CadrePhase phase = CadrePhase.decision;

  /// Whose turn it is to decide. Always [sideA] in bot matches.
  int activeSide = sideA;

  CadreRoundResult? lastResult;
  int roundNumber = 0;

  /// One entry per settled round, in order. Drives the round track.
  final List<CadreOutcome> history = <CadreOutcome>[];

  CadreMatch._({
    required this.rosterTitle,
    required this.mode,
    required this.crossover,
    required this.rounds,
    required this.playerDeck,
    required this.opponentDeck,
  });

  /// Shuffles a roster and deals two decks.
  ///
  /// Each side gets one card more than the match has rounds. Skip discards a
  /// card outright and draws the spare; a side that never skips just never
  /// sees its last card. Hand size adapts to short casts so a 14-character
  /// anime still plays, over fewer rounds.
  factory CadreMatch.deal(
    CadrePool pool, {
    CadreMode mode = CadreMode.bot,
    math.Random? random,
  }) {
    if (pool.length < minRosterSize) {
      throw ArgumentError(
        '${pool.title} only has ${pool.length} usable characters. '
        'Needs at least $minRosterSize. Add another anime to the pool.',
      );
    }

    final rng = random ?? math.Random();
    final shuffled = List<CadreFighter>.of(pool.fighters)..shuffle(rng);

    final handSize = handSizeFor(shuffled.length);
    final player = <CadreFighter>[];
    final opponent = <CadreFighter>[];

    for (var i = 0; i < handSize * 2; i++) {
      (i.isEven ? player : opponent).add(shuffled[i]);
    }

    return CadreMatch._(
      rosterTitle: pool.title,
      mode: mode,
      crossover: pool.isCrossover,
      rounds: handSize - 1,
      playerDeck: player,
      opponentDeck: opponent,
    )..drawRound();
  }

  bool get isLocal => mode == CadreMode.local;
  bool get isHonor => mode == CadreMode.honor;

  /// Both seats have named a winner.
  bool get bothVoted => playerVote != null && opponentVote != null;

  /// The seats disagree, so the round goes to a toss.
  bool get disputed => bothVoted && playerVote != opponentVote;

  /// Which seat still has to vote, or null when both have.
  int? get awaitingVote {
    if (playerVote == null) return sideA;
    if (opponentVote == null) return sideB;
    return null;
  }

  /// Rounds still to come after the one on screen.
  int get roundsLeft => rounds - roundNumber;
  int get playerScore => playerPile.length;

  /// Cards still to be drawn, not counting the one on the table.
  int deckLeftFor(int side) =>
      (side == sideA ? playerDeck.length : opponentDeck.length);
  int get opponentScore => opponentPile.length;
  int get potSize => pot.length;

  /// Combined power of a pile. Breaks a level card count.
  int get playerPilePower =>
      playerPile.fold<int>(0, (sum, f) => sum + f.power);
  int get opponentPilePower =>
      opponentPile.fold<int>(0, (sum, f) => sum + f.power);

  String labelFor(int side) {
    if (isLocal || isHonor) return side == sideA ? 'Player 1' : 'Player 2';
    return side == sideA ? 'You' : 'Bot';
  }

  CadreFighter? cardFor(int side) =>
      side == sideA ? playerCard : opponentCard;

  int pushesFor(int side) => side == sideA ? playerPushes : opponentPushes;

  bool pushedFor(int side) =>
      side == sideA ? playerPushedThisRound : opponentPushedThisRound;

  int skipsFor(int side) => side == sideA ? playerSkips : opponentSkips;

  bool skippedFor(int side) =>
      side == sideA ? playerSkippedThisRound : opponentSkippedThisRound;

  List<CadreFighter> _deckFor(int side) =>
      side == sideA ? playerDeck : opponentDeck;

  /// A skip needs a card left to swap to. The spare card means that holds
  /// right through the final round.
  ///
  /// Always false in Honor. The spare card is reserved as the decider for a
  /// level match, and spending it on a skip would leave nothing to break the
  /// tie with.
  bool canSkipFor(int side) =>
      !isHonor &&
      skipsFor(side) > 0 &&
      !skippedFor(side) &&
      _deckFor(side).isNotEmpty;

  bool get canSkip =>
      phase == CadrePhase.decision && canSkipFor(activeSide);

  /// Discards the current card for good and draws the next one.
  ///
  /// The card does not come back — that is what the spare eleventh card
  /// pays for. Any push already spent this round carries over to the
  /// replacement.
  void skipFor(int side) {
    if (!canSkipFor(side)) return;
    final deck = _deckFor(side);
    final replacement = deck.removeAt(0);

    if (side == sideA) {
      playerCard = replacement;
      playerSkips--;
      playerSkippedThisRound = true;
    } else {
      opponentCard = replacement;
      opponentSkips--;
      opponentSkippedThisRound = true;
    }
  }

  void skip() => skipFor(activeSide);

  /// The only rule that decides a round. Pure by design.
  ///
  /// A round can still tie — that is what fills the pot. A *match* cannot;
  /// see [finalOutcome].
  static CadreOutcome resolve(CadrePlay player, CadrePlay opponent) {
    if (player.effectivePower > opponent.effectivePower) {
      return CadreOutcome.playerWins;
    }
    if (opponent.effectivePower > player.effectivePower) {
      return CadreOutcome.opponentWins;
    }
    return CadreOutcome.tie;
  }

  /// The honor counterpart to [resolve], and pure for the same reason.
  ///
  /// The coin arrives as an argument rather than being drawn inside, so this
  /// stays deterministic and testable, and so a Cloud Function can supply a
  /// server-side coin when online play lands without the rule being written
  /// a second time.
  static CadreOutcome resolveHonor({
    required int playerVote,
    required int opponentVote,
    required bool tossFavoursPlayer,
  }) {
    if (playerVote == opponentVote) {
      return playerVote == sideA
          ? CadreOutcome.playerWins
          : CadreOutcome.opponentWins;
    }
    return tossFavoursPlayer
        ? CadreOutcome.playerWins
        : CadreOutcome.opponentWins;
  }

  /// A seat names the round's winner. Voting for the other side concedes.
  void castVote(int seat, int forSide) {
    if (!isHonor || phase != CadrePhase.voting) return;
    if (seat == sideA) {
      playerVote = forSide;
    } else {
      opponentVote = forSide;
    }
    final next = awaitingVote;
    if (next == null) {
      phase = CadrePhase.revealing;
    } else {
      activeSide = next;
    }
  }

  /// Pulls the next card for each side.
  void drawRound() {
    if (playerDeck.isEmpty || opponentDeck.isEmpty) {
      _finish();
      return;
    }
    playerCard = playerDeck.removeAt(0);
    opponentCard = opponentDeck.removeAt(0);
    playerPushedThisRound = false;
    opponentPushedThisRound = false;
    playerSkippedThisRound = false;
    opponentSkippedThisRound = false;
    lastResult = null;
    playerVote = null;
    opponentVote = null;
    lastWasToss = false;
    roundNumber++;
    activeSide = sideA;
    if (isHonor) {
      phase = CadrePhase.voting;
    } else {
      phase = isLocal ? CadrePhase.handoff : CadrePhase.decision;
    }
  }

  /// Handoff screen tapped: the active side may now look at its card.
  void beginTurn() {
    if (phase == CadrePhase.handoff) phase = CadrePhase.decision;
  }

  /// Always false in Honor: a push adds 25 to a number that mode does not
  /// show, so there is nothing to bet on.
  bool get canPush =>
      !isHonor &&
      phase == CadrePhase.decision &&
      pushesFor(activeSide) > 0 &&
      !pushedFor(activeSide);

  void spendPush() {
    if (!canPush) return;
    if (activeSide == sideA) {
      playerPushes--;
      playerPushedThisRound = true;
    } else {
      opponentPushes--;
      opponentPushedThisRound = true;
    }
  }

  /// The active side is done deciding.
  ///
  /// In local play this hands over to the second seat before the reveal. In a
  /// bot match it goes straight to the reveal.
  void endTurn() {
    if (isLocal && activeSide == sideA) {
      activeSide = sideB;
      phase = CadrePhase.handoff;
      return;
    }
    phase = CadrePhase.revealing;
  }

  /// Locks in the bot's push before the reveal. No effect in local play.
  void commitOpponentPush(bool push) {
    if (isLocal) return;
    if (!push || opponentPushes <= 0) return;
    opponentPushes--;
    opponentPushedThisRound = true;
  }

  /// Settles an Honor round from the two votes.
  ///
  /// [random] is injectable so a test can pin the coin. No pot is involved:
  /// assent and toss both produce a winner, so an Honor round is always
  /// decisive and nothing is ever left on the table.
  CadreRoundResult settleHonor({math.Random? random}) {
    final mine = playerVote!;
    final theirs = opponentVote!;
    final contested = mine != theirs;

    if (contested) {
      playerDisputes += mine == sideA ? 1 : 0;
      opponentDisputes += theirs == sideB ? 1 : 0;
    }

    final outcome = resolveHonor(
      playerVote: mine,
      opponentVote: theirs,
      tossFavoursPlayer: (random ?? math.Random()).nextBool(),
    );
    lastWasToss = contested;

    final player = CadrePlay(fighter: playerCard!);
    final opponent = CadrePlay(fighter: opponentCard!);
    final stake = <CadreFighter>[player.fighter, opponent.fighter];

    if (outcome == CadreOutcome.playerWins) {
      playerPile.addAll(stake);
    } else {
      opponentPile.addAll(stake);
    }

    final result = CadreRoundResult(
      player: player,
      opponent: opponent,
      outcome: outcome,
      cardsTaken: stake.length,
    );
    lastResult = result;
    history.add(outcome);
    phase = CadrePhase.resolved;
    return result;
  }

  /// Settles the round and moves cards into piles.
  CadreRoundResult settle() {
    if (isHonor) return settleHonor();
    final player = CadrePlay(
      fighter: playerCard!,
      pushed: playerPushedThisRound,
    );
    final opponent = CadrePlay(
      fighter: opponentCard!,
      pushed: opponentPushedThisRound,
    );

    final outcome = resolve(player, opponent);
    final stake = <CadreFighter>[player.fighter, opponent.fighter, ...pot];

    var taken = 0;
    switch (outcome) {
      case CadreOutcome.playerWins:
        playerPile.addAll(stake);
        pot.clear();
        taken = stake.length;
        break;
      case CadreOutcome.opponentWins:
        opponentPile.addAll(stake);
        pot.clear();
        taken = stake.length;
        break;
      case CadreOutcome.tie:
        pot
          ..clear()
          ..addAll(stake);
        taken = 0;
        break;
    }

    final result = CadreRoundResult(
      player: player,
      opponent: opponent,
      outcome: outcome,
      cardsTaken: taken,
    );
    lastResult = result;
    history.add(outcome);
    phase = CadrePhase.resolved;
    return result;
  }

  /// Advances past a settled round.
  void next() {
    final scheduledRoundsDone = roundNumber >= rounds;

    // Honor breaks a level match with one more voted round rather than on
    // pile power, so the last card in hand is allowed to play.
    if (scheduledRoundsDone &&
        isHonor &&
        playerScore == opponentScore &&
        playerDeck.isNotEmpty &&
        opponentDeck.isNotEmpty) {
      inSuddenDeath = true;
      drawRound();
      return;
    }

    if (scheduledRoundsDone ||
        playerDeck.isEmpty ||
        opponentDeck.isEmpty) {
      _finish();
      return;
    }
    drawRound();
  }

  /// Ends the match, awarding any pot left stranded by a final-round tie to
  /// whichever pile is stronger.
  void _finish() {
    if (pot.isNotEmpty) {
      if (playerPilePower >= opponentPilePower) {
        playerPile.addAll(pot);
      } else {
        opponentPile.addAll(pot);
      }
      pot.clear();
    }
    playerCard = null;
    opponentCard = null;
    phase = CadrePhase.matchOver;
  }

  /// The match result. **Never returns [CadreOutcome.tie].**
  ///
  /// Four tests, applied in order until one separates the sides:
  ///
  ///   1. card count — most cards wins
  ///   2. combined power of the pile
  ///   3. card by card, strongest first — whoever holds the better card at
  ///      the first point of difference
  ///   4. whoever took the last round that settled
  ///
  /// Tests 1 and 2 alone left a real draw in roughly 1 match in 700 on a
  /// 25-character cast, and 1 in 290 on a thin one, because two piles of ten
  /// integers can sum to the same number. Test 3 closes that: the piles are
  /// disjoint subsets, so while power values inside a pool are distinct they
  /// cannot match card for card. Test 4 exists only for a crossover pool that
  /// manages to repeat a character.
  ///
  /// [CadreOutcome.tie] still comes back from [resolve] — a *round* ties, and
  /// that is what fills the pot. A *match* does not.
  CadreOutcome get finalOutcome {
    if (playerScore > opponentScore) return CadreOutcome.playerWins;
    if (opponentScore > playerScore) return CadreOutcome.opponentWins;

    // Honor deliberately stops here rather than weighing piles: the power
    // number is the thing this mode exists to route around, so settling a
    // level Honor match with it would undo the point. A level match has
    // already been sent to sudden death by [next], which cannot tie, so
    // reaching this line means the decider could not be dealt.
    if (isHonor) {
      for (final outcome in history.reversed) {
        if (outcome != CadreOutcome.tie) return outcome;
      }
      return CadreOutcome.playerWins;
    }

    if (playerPilePower > opponentPilePower) return CadreOutcome.playerWins;
    if (opponentPilePower > playerPilePower) return CadreOutcome.opponentWins;

    final mine = playerPile.map((f) => f.power).toList()
      ..sort((a, b) => b.compareTo(a));
    final theirs = opponentPile.map((f) => f.power).toList()
      ..sort((a, b) => b.compareTo(a));

    final depth = math.min(mine.length, theirs.length);
    for (var i = 0; i < depth; i++) {
      if (mine[i] != theirs[i]) {
        return mine[i] > theirs[i]
            ? CadreOutcome.playerWins
            : CadreOutcome.opponentWins;
      }
    }

    for (final outcome in history.reversed) {
      if (outcome != CadreOutcome.tie) return outcome;
    }

    // Every single round tied, so _finish() handed the whole pot to one side
    // and the card count above would already have separated them. Unreachable
    // in practice; the return keeps the getter total.
    return CadreOutcome.playerWins;
  }

  /// True when the card count was level and a tiebreak decided the match.
  bool get decidedOnPower => playerScore == opponentScore;
}
