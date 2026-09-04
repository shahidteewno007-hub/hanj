import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cadre_match.dart';
import '../models/cadre_pool.dart';
import '../models/cadre_stats.dart';
import '../services/cadre_bot.dart';
import '../services/cadre_stats_service.dart';
import '../widgets/cadre_fighter_card.dart';
import '../widgets/cadre_flip_card.dart';

class CadreClashScreen extends StatefulWidget {
  final CadrePool pool;
  final CadreMode mode;

  const CadreClashScreen({
    super.key,
    required this.pool,
    this.mode = CadreMode.bot,
  });

  @override
  State<CadreClashScreen> createState() => _CadreClashScreenState();
}

class _CadreClashScreenState extends State<CadreClashScreen>
    with TickerProviderStateMixin {
  late final CadreMatch _match;
  late final CadreBot _bot;
  String? _dealError;

  /// Cards arriving for a new round.
  late final AnimationController _deal;

  /// The reveal itself: flip, then the power values counting up.
  late final AnimationController _reveal;

  /// The beat after the result lands: winner swells, loser recedes.
  late final AnimationController _impact;

  late final CurvedAnimation _flipT;
  late final CurvedAnimation _countT;

  bool _recorded = false;

  @override
  void initState() {
    super.initState();
    _bot = CadreBot();

    _deal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _impact = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    // The flip lands first, then the numbers climb into the gap it leaves.
    _flipT = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.0, 0.46, curve: Curves.easeInOutCubic),
    );
    _countT = CurvedAnimation(
      parent: _reveal,
      curve: const Interval(0.38, 1.0, curve: Curves.easeOutCubic),
    );

    // A toss is a short beat, not a reveal — there is nothing counting up.
    if (widget.mode == CadreMode.honor) {
      _reveal.duration = const Duration(milliseconds: 620);
    }

    try {
      _match = CadreMatch.deal(widget.pool, mode: widget.mode);
      _deal.forward();
    } on ArgumentError catch (e) {
      _dealError = e.message as String?;
    }
  }

  @override
  void dispose() {
    _flipT.dispose();
    _countT.dispose();
    _deal.dispose();
    _reveal.dispose();
    _impact.dispose();
    super.dispose();
  }

  /// True when this side's card was already face-up before the reveal, so it
  /// shouldn't flip or re-count its number.
  bool _wasVisible(int side) {
    // Honor puts both cards face up from the deal: the seats are judging the
    // characters, not a number, so there is nothing to conceal.
    if (_match.isHonor) return true;
    if (side == CadreMatch.sideA) {
      return !_match.isLocal || _match.activeSide == CadreMatch.sideA;
    }
    return _match.isLocal && _match.activeSide == CadreMatch.sideB;
  }

  void _push() {
    HapticFeedback.lightImpact();
    setState(_match.spendPush);
  }

  void _skip() {
    HapticFeedback.lightImpact();
    setState(_match.skip);
  }

  Future<void> _lockIn() async {
    HapticFeedback.mediumImpact();
    setState(_match.endTurn);

    // Local play hands the phone over instead of revealing.
    if (_match.phase != CadrePhase.revealing) return;

    if (!_match.isLocal) {
      if (_bot.shouldSkip(
        ownPower: _match.opponentCard!.power,
        skipsLeft: _match.opponentSkips,
      )) {
        _match.skipFor(CadreMatch.sideB);
      }
      _match.commitOpponentPush(
        _bot.shouldPush(
          ownPower: _match.opponentCard!.power,
          pushesLeft: _match.opponentPushes,
          roundsLeft: _match.roundsLeft,
          cardDeficit: _match.playerScore - _match.opponentScore,
        ),
      );
    }

    await _reveal.forward(from: 0);
    if (!mounted) return;

    setState(_match.settle);
    _impact.forward(from: 0);

    final outcome = _match.lastResult?.outcome;
    if (outcome == CadreOutcome.tie) {
      HapticFeedback.selectionClick();
    } else {
      HapticFeedback.heavyImpact();
    }
  }

  /// A seat names the round's winner by tapping that card.
  ///
  /// Votes are open rather than sealed: the second seat can see the first
  /// seat's pick. That is the format this mode copies — an argument across a
  /// table, not a secret ballot — and it saves a handoff screen.
  Future<void> _vote(int forSide) async {
    final seat = _match.awaitingVote;
    if (seat == null) return;

    HapticFeedback.selectionClick();
    setState(() => _match.castVote(seat, forSide));

    // First of two seats: wait for the other.
    if (_match.phase != CadrePhase.revealing) return;

    // Assent settles instantly. A dispute earns a beat, so the toss reads as
    // something that happened rather than a number appearing.
    if (_match.disputed) {
      HapticFeedback.mediumImpact();
      await _reveal.forward(from: 0);
      if (!mounted) return;
    }

    setState(_match.settleHonor);
    _impact.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  void _next() {
    _reveal.value = 0;
    _impact.value = 0;
    setState(_match.next);
    if (_match.phase == CadrePhase.matchOver) {
      _record();
    } else {
      _deal.forward(from: 0);
    }
  }

  void _beginTurn() {
    HapticFeedback.selectionClick();
    setState(_match.beginTurn);
    _deal.forward(from: 0);
  }

  /// Only bot matches count. Pass-and-play has two people on one device and
  /// there is no honest way to say whose record it is.
  void _record() {
    // Honor is two people on one phone, same as local play, so the same
    // reasoning applies: there is no honest way to say whose record it is.
    if (_recorded || _match.isLocal || _match.isHonor) return;
    _recorded = true;
    final outcome = _match.finalOutcome;
    final stats = CadreStatsService.instance.cached.recording(
      win: outcome == CadreOutcome.playerWins,
      loss: outcome == CadreOutcome.opponentWins,
      cards: _match.playerScore,
      pool: _match.rosterTitle,
    );
    CadreStatsService.instance.save(stats);
  }

  @override
  Widget build(BuildContext context) {
    if (_dealError != null) {
      return Scaffold(
        backgroundColor: CadreColors.bg,
        appBar: _bar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _dealError!,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                color: CadreColors.ivoryDim,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ),
        ),
      );
    }

    final Widget body;
    switch (_match.phase) {
      case CadrePhase.matchOver:
        body = _MatchOver(match: _match, onAgain: () => Navigator.pop(context));
        break;
      case CadrePhase.handoff:
        body = _Handoff(match: _match, onReady: _beginTurn);
        break;
      case CadrePhase.voting:
        body = _buildRound();
        break;
      default:
        body = _buildRound();
    }

    return Scaffold(
      backgroundColor: CadreColors.bg,
      appBar: _bar(),
      body: SafeArea(top: false, child: body),
    );
  }

  PreferredSizeWidget _bar() {
    return AppBar(
      backgroundColor: CadreColors.bg,
      elevation: 0,
      iconTheme: const IconThemeData(color: CadreColors.ivory),
      title: Text(
        widget.pool.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.dmSans(
          color: CadreColors.ivoryDim,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildRound() {
    final resolved = _match.phase == CadrePhase.resolved;
    final revealing = _match.phase == CadrePhase.revealing;
    final result = _match.lastResult;

    return Column(
      children: [
        _RoundTrack(match: _match),
        const SizedBox(height: 12),
        _Scoreline(match: _match, impact: _impact),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              const centre = 46.0;
              const labelBlock = 34.0;
              final byWidth = (box.maxWidth - 40 - centre) / 2;
              final byHeight = (box.maxHeight - labelBlock) * 2 / 3;
              final cardWidth = byWidth < byHeight ? byWidth : byHeight;

              return Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _buildSide(CadreMatch.sideA, resolved, result),
                    ),
                    SizedBox(
                      width: centre,
                      child: _Clash(
                        reveal: _reveal,
                        impact: _impact,
                        resolved: resolved,
                        revealing: revealing,
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _buildSide(CadreMatch.sideB, resolved, result),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        _VerdictStrip(match: _match, impact: _impact),
        _Controls(
          match: _match,
          onPush: _push,
          onSkip: _skip,
          onLockIn: _lockIn,
          onNext: _next,
        ),
      ],
    );
  }

  Widget _buildSide(int side, bool resolved, CadreRoundResult? result) {
    final fighter = _match.cardFor(side)!;
    final settled = _wasVisible(side);
    final pushed = _match.pushedFor(side);
    final skipped = _match.skippedFor(side);
    final show = settled || resolved;

    final voting = _match.isHonor && _match.phase == CadrePhase.voting;
    final seat = _match.awaitingVote;

    // Who has already named this card. Drives the coral ring so a seat can
    // see the argument so far before committing to it.
    final namedBy = <String>[
      if (_match.playerVote == side) _match.labelFor(CadreMatch.sideA),
      if (_match.opponentVote == side) _match.labelFor(CadreMatch.sideB),
    ];

    final winning = resolved &&
        ((side == CadreMatch.sideA &&
                result?.outcome == CadreOutcome.playerWins) ||
            (side == CadreMatch.sideB &&
                result?.outcome == CadreOutcome.opponentWins));
    final losing = resolved &&
        result?.outcome != CadreOutcome.tie &&
        !winning;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_deal, _reveal, _impact]),
      builder: (context, _) {
        // Cards arrive from below with a short stagger between sides.
        final dealT = Curves.easeOutCubic.transform(
          (_deal.value * 1.25 - (side == CadreMatch.sideB ? 0.25 : 0.0))
              .clamp(0.0, 1.0),
        );

        // The freshly turned card counts its power up rather than snapping.
        final int? override = (!settled && !resolved)
            ? (fighter.power * _countT.value).round()
            : null;

        Widget card;
        if (settled) {
          card = CadreFighterCard(
            fighter: fighter,
            // The whole point of Honor: no number on the card, so the broken
            // one cannot influence the call.
            showPower: !_match.isHonor,
            highlighted: pushed || namedBy.isNotEmpty,
            onTap: voting && seat != null ? () => _vote(side) : null,
          );
        } else if (resolved) {
          card = CadreFighterCard(
            fighter: fighter,
            showPower: !_match.isHonor,
            highlighted: pushed,
          );
        } else {
          card = CadreFlipCard(
            t: _flipT.value,
            back: CadreFighterCard(fighter: fighter, faceDown: true),
            front: CadreFighterCard(
              fighter: fighter,
              highlighted: pushed,
              powerOverride: override,
            ),
          );
        }

        final scale = winning
            ? 1.0 + (0.06 * Curves.easeOutBack.transform(_impact.value))
            : (losing ? 1.0 - (0.05 * _impact.value) : 1.0);

        return Opacity(
          opacity: dealT,
          child: Transform.translate(
            offset: Offset(0, (1 - dealT) * 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: winning
                          ? [
                              BoxShadow(
                                color: Color.fromRGBO(
                                  232,
                                  98,
                                  74,
                                  0.42 * _impact.value,
                                ),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Opacity(
                      opacity: losing ? 1.0 - (0.35 * _impact.value) : 1.0,
                      child: card,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _SideLabel(
                  label: _match.labelFor(side),
                  pushed: show && pushed,
                  skipped: show && skipped,
                  deckLeft: _match.deckLeftFor(side),
                  namedBy: namedBy,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The centre column between the cards. Quiet until the moment of comparison,
/// then it fires: this is the beat the whole round is built around.
class _Clash extends StatelessWidget {
  final AnimationController reveal;
  final AnimationController impact;
  final bool resolved;
  final bool revealing;

  const _Clash({
    required this.reveal,
    required this.impact,
    required this.resolved,
    required this.revealing,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[reveal, impact]),
      builder: (context, _) {
        final flash = impact.value < 0.5
            ? impact.value * 2
            : (1 - impact.value) * 2;
        final live = revealing || resolved;

        return SizedBox(
          height: 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 1,
                height: 60,
                color: Color.fromRGBO(243, 238, 231, live ? 0.10 : 0.05),
              ),
              Transform.scale(
                scale: 1 + (0.5 * flash),
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: CadreColors.bg,
                    border: Border.all(
                      color: Color.fromRGBO(
                        232,
                        98,
                        74,
                        0.28 + (0.72 * flash),
                      ),
                      width: 1 + flash,
                    ),
                  ),
                  child: Text(
                    'VS',
                    style: GoogleFonts.spaceGrotesk(
                      color: Color.fromRGBO(
                        243,
                        238,
                        231,
                        0.45 + (0.55 * flash),
                      ),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One pip per round, filled in as the match goes. Gives the match a shape you
/// can read at a glance instead of just a pair of numbers.
class _RoundTrack extends StatelessWidget {
  final CadreMatch match;
  const _RoundTrack({required this.match});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (var i = 0; i < match.rounds; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                height: i == match.history.length ? 5 : 3,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: _colourFor(i),
                ),
              ),
            ),
            if (i != match.rounds - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Color _colourFor(int i) {
    if (i < match.history.length) {
      switch (match.history[i]) {
        case CadreOutcome.playerWins:
          return CadreColors.coral;
        case CadreOutcome.opponentWins:
          return const Color(0xFF3A2A24);
        case CadreOutcome.tie:
          return const Color(0x66F3EEE7);
      }
    }
    if (i == match.history.length) return const Color(0x8AF3EEE7);
    return const Color(0x14F3EEE7);
  }
}

class _Scoreline extends StatelessWidget {
  final CadreMatch match;
  final AnimationController impact;

  const _Scoreline({required this.match, required this.impact});

  @override
  Widget build(BuildContext context) {
    final result = match.lastResult;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Tally(
            label: match.labelFor(CadreMatch.sideA),
            value: match.playerScore,
            impact: impact,
            popping: result?.outcome == CadreOutcome.playerWins,
          ),
          Column(
            children: [
              Text(
                'ROUND ${match.roundNumber} / ${match.rounds}',
                style: GoogleFonts.dmSans(
                  color: CadreColors.ivoryFaint,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (match.potSize > 0) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: CadreColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: CadreColors.coralEdge),
                  ),
                  child: Text(
                    '${match.potSize} in the pot',
                    style: GoogleFonts.spaceGrotesk(
                      color: CadreColors.coral,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          _Tally(
            label: match.labelFor(CadreMatch.sideB),
            value: match.opponentScore,
            impact: impact,
            popping: result?.outcome == CadreOutcome.opponentWins,
          ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  final String label;
  final int value;
  final AnimationController impact;
  final bool popping;

  const _Tally({
    required this.label,
    required this.value,
    required this.impact,
    required this.popping,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: impact,
      builder: (context, _) {
        final t = popping ? impact.value : 0.0;
        final pop = t < 0.5 ? t * 2 : (1 - t) * 2;
        return Column(
          children: [
            Transform.scale(
              scale: 1 + (0.22 * pop),
              child: Text(
                '$value',
                style: GoogleFonts.spaceGrotesk(
                  color: popping && pop > 0.1
                      ? CadreColors.coral
                      : CadreColors.ivory,
                  fontSize: 27,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.dmSans(
                color: CadreColors.ivoryFaint,
                fontSize: 11,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SideLabel extends StatelessWidget {
  final String label;
  final bool pushed;
  final bool skipped;
  final int deckLeft;

  /// Honor only: seats that have named this card as the round's winner.
  final List<String> namedBy;

  const _SideLabel({
    required this.label,
    required this.pushed,
    required this.skipped,
    required this.deckLeft,
    this.namedBy = const <String>[],
  });

  @override
  Widget build(BuildContext context) {
    final marks = <String>[
      if (skipped) 'skipped',
      if (pushed) '+${CadreMatch.pushBonus}',
      ...namedBy.map((seat) => '$seat says this'),
    ];
    final marked = marks.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          marked ? '$label  \u00B7  ${marks.join('  \u00B7  ')}' : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.dmSans(
            color: marked ? CadreColors.coral : CadreColors.ivoryFaint,
            fontSize: 12,
            fontWeight: marked ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$deckLeft left',
          style: GoogleFonts.spaceGrotesk(
            color: const Color(0x59F3EEE7),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _VerdictStrip extends StatelessWidget {
  final CadreMatch match;
  final AnimationController impact;

  const _VerdictStrip({required this.match, required this.impact});

  @override
  Widget build(BuildContext context) {
    final result = match.lastResult;
    if (match.phase != CadrePhase.resolved || result == null) {
      return const SizedBox(height: 52);
    }

    final String text;
    switch (result.outcome) {
      case CadreOutcome.playerWins:
        text = '${match.labelFor(CadreMatch.sideA)} takes ${result.cardsTaken}';
        break;
      case CadreOutcome.opponentWins:
        text = '${match.labelFor(CadreMatch.sideB)} takes ${result.cardsTaken}';
        break;
      case CadreOutcome.tie:
        text = 'Dead even \u2014 both to the pot';
        break;
    }

    final tie = result.outcome == CadreOutcome.tie;

    final settledBy = match.isHonor
        ? (match.lastWasToss ? '  \u00B7  coin toss' : '  \u00B7  agreed')
        : '';

    return AnimatedBuilder(
      animation: impact,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(impact.value);
        return SizedBox(
          height: 52,
          child: Center(
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: CadreColors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: tie
                          ? CadreColors.hairline
                          : CadreColors.coralEdge,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The score pair is the one place power would still
                      // reach the screen in Honor, at the loudest possible
                      // moment. Suppressed there; how the round settled goes
                      // in its place.
                      if (!match.isHonor) ...[
                        Text(
                          '${result.player.effectivePower}',
                          style: GoogleFonts.spaceGrotesk(
                            color: CadreColors.ivory,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '  \u2013  ',
                          style: GoogleFonts.spaceGrotesk(
                            color: CadreColors.ivoryFaint,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '${result.opponent.effectivePower}',
                          style: GoogleFonts.spaceGrotesk(
                            color: CadreColors.ivory,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 14,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          color: CadreColors.hairline,
                        ),
                      ],
                      Flexible(
                        child: Text(
                          '$text$settledBy',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            color: tie
                                ? CadreColors.ivoryDim
                                : CadreColors.ivory,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Covers the board while the phone changes hands.
class _Handoff extends StatelessWidget {
  final CadreMatch match;
  final VoidCallback onReady;

  const _Handoff({required this.match, required this.onReady});

  @override
  Widget build(BuildContext context) {
    final name = match.labelFor(match.activeSide);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onReady,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '\u72D0',
                style: TextStyle(color: CadreColors.coralEdge, fontSize: 64),
              ),
              const SizedBox(height: 26),
              Text(
                'Pass to $name',
                style: GoogleFonts.playfairDisplay(
                  color: CadreColors.ivory,
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Round ${match.roundNumber}. Tap when $name is holding the phone.',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  color: CadreColors.ivoryDim,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final CadreMatch match;
  final VoidCallback onPush;
  final VoidCallback onSkip;
  final VoidCallback onLockIn;
  final VoidCallback onNext;

  const _Controls({
    required this.match,
    required this.onPush,
    required this.onSkip,
    required this.onLockIn,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = match.phase == CadrePhase.resolved;
    final revealing = match.phase == CadrePhase.revealing;

    // Honor has no tokens and nothing to lock in: the round advances when
    // both seats have tapped a card. Until then the prompt stands in for the
    // button, so there is no control to press by mistake.
    if (match.isHonor && !resolved) {
      final seat = match.awaitingVote;
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: SizedBox(
          height: 56,
          child: Center(
            child: Text(
              seat == null
                  ? 'Settling\u2026'
                  : '${match.labelFor(seat)} \u2014 tap the card that wins',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                color: seat == null
                    ? CadreColors.ivoryFaint
                    : CadreColors.ivory,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    final lockLabel = match.isLocal && match.activeSide == CadreMatch.sideA
        ? 'Lock in and pass'
        : 'Reveal';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!resolved) ...[
            Row(
              children: [
                Expanded(
                  child: _TokenButton(
                    label: 'Skip',
                    tokensLeft: match.skipsFor(match.activeSide),
                    spent: match.skippedFor(match.activeSide),
                    spentLabel: 'Skipped',
                    enabled: match.canSkip && !revealing,
                    onTap: onSkip,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TokenButton(
                    label: 'Push +${CadreMatch.pushBonus}',
                    tokensLeft: match.pushesFor(match.activeSide),
                    spent: match.pushedFor(match.activeSide),
                    spentLabel: 'Pushed',
                    enabled: match.canPush && !revealing,
                    onTap: onPush,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          _PrimaryButton(
            label: resolved
                ? (match.roundsLeft == 0 ? 'See result' : 'Next round')
                : lockLabel,
            enabled: !revealing,
            onTap: resolved ? onNext : onLockIn,
          ),
        ],
      ),
    );
  }
}

class _TokenButton extends StatelessWidget {
  final String label;
  final String spentLabel;
  final int tokensLeft;
  final bool spent;
  final bool enabled;
  final VoidCallback onTap;

  const _TokenButton({
    required this.label,
    required this.spentLabel,
    required this.tokensLeft,
    required this.spent,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: spent ? CadreColors.coral : CadreColors.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: enabled ? CadreColors.coralEdge : CadreColors.hairline,
          ),
        ),
        child: FittedBox(
          child: Text(
            spent ? spentLabel : '$label  \u00B7  $tokensLeft',
            style: GoogleFonts.dmSans(
              color: spent
                  ? Colors.white
                  : (enabled ? CadreColors.ivory : CadreColors.ivoryFaint),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        height: 54,
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [CadreColors.ember, CadreColors.coral],
                )
              : null,
          color: enabled ? null : CadreColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            color: enabled ? Colors.white : CadreColors.ivoryFaint,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MatchOver extends StatelessWidget {
  final CadreMatch match;
  final VoidCallback onAgain;

  const _MatchOver({required this.match, required this.onAgain});

  @override
  Widget build(BuildContext context) {
    final outcome = match.finalOutcome;
    final String headline;
    switch (outcome) {
      case CadreOutcome.playerWins:
        headline = match.isLocal || match.isHonor ? 'Player 1 wins' : 'You win';
        break;
      case CadreOutcome.opponentWins:
        headline = match.isLocal || match.isHonor ? 'Player 2 wins' : 'Bot wins';
        break;
      case CadreOutcome.tie:
        headline = 'Dead level';
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoundTrack(match: match),
            const SizedBox(height: 30),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                color: CadreColors.ivory,
                fontSize: 40,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${match.playerScore} cards to ${match.opponentScore}',
              style: GoogleFonts.spaceGrotesk(
                color: CadreColors.ivoryDim,
                fontSize: 16,
              ),
            ),
            if (match.inSuddenDeath) ...[
              const SizedBox(height: 8),
              Text(
                'Level after ${match.rounds} \u2014 decided on the last card',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  color: CadreColors.coral,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
            if (match.isHonor &&
                (match.playerDisputes > 0 || match.opponentDisputes > 0)) ...[
              const SizedBox(height: 8),
              Text(
                'Disputes \u2014 ${match.labelFor(CadreMatch.sideA)} '
                '${match.playerDisputes}, ${match.labelFor(CadreMatch.sideB)} '
                '${match.opponentDisputes}',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  color: CadreColors.ivoryFaint,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
            if (!match.isHonor && match.decidedOnPower) ...[
              const SizedBox(height: 8),
              Text(
                'Level on cards \u2014 decided on strength, '
                '${match.playerPilePower} to ${match.opponentPilePower}',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  color: CadreColors.coral,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 34),
            _PrimaryButton(
              label: 'Back to the lobby',
              enabled: true,
              onTap: onAgain,
            ),
          ],
        ),
      ),
    );
  }
}
