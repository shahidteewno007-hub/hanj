import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cadre_fighter.dart';
import '../models/cadre_pool.dart';
import '../models/cadre_squad.dart';
import '../widgets/cadre_fighter_card.dart';

/// Squad: eight blind draws, five slots, no second chances.
///
/// Placement is two taps rather than one. A slot is armed first and committed
/// second, because a tap on a 60px target is permanent and a mis-tap costs the
/// match. Arming also lets the rail answer the only question that matters —
/// what this card is worth in each slot — before anything is spent.
class CadreSquadScreen extends StatefulWidget {
  final CadrePool pool;

  const CadreSquadScreen({super.key, required this.pool});

  @override
  State<CadreSquadScreen> createState() => _CadreSquadScreenState();
}

class _CadreSquadScreenState extends State<CadreSquadScreen> {
  late final CadreSquadMatch _match;
  String? _dealError;

  /// The slot selected but not yet committed.
  String? _armed;

  @override
  void initState() {
    super.initState();
    try {
      _match = CadreSquadMatch.deal(widget.pool);
    } on ArgumentError catch (e) {
      _dealError = e.message as String?;
    }
  }

  void _arm(String slot) {
    HapticFeedback.selectionClick();
    setState(() => _armed = _armed == slot ? null : slot);
  }

  void _place() {
    final slot = _armed;
    if (slot == null) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _match.place(slot);
      _armed = null;
    });
  }

  void _pass() {
    if (!_match.canPass) return;
    HapticFeedback.lightImpact();
    setState(() {
      _match.pass();
      _armed = null;
    });
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

    return Scaffold(
      backgroundColor: CadreColors.bg,
      appBar: _bar(),
      body: SafeArea(
        top: false,
        child: _match.phase == CadreSquadPhase.done
            ? _SquadResult(
                match: _match,
                onDone: () => Navigator.of(context).pop(),
              )
            : _buildDraft(),
      ),
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

  Widget _buildDraft() {
    final card = _match.playerCard;
    if (card == null) return const SizedBox.shrink();

    return Column(
      children: [
        _DraftMeta(match: _match),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // Sized off the height it has been given, so the rail and the
              // buttons below can never be pushed off a short screen.
              final byHeight = (box.maxHeight - 12) * 2 / 3;
              final byWidth = box.maxWidth - 72;
              final width = math.min(math.min(byHeight, byWidth), 300.0);
              if (width < 40) return const SizedBox.shrink();

              return Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.07),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: SizedBox(
                    key: ValueKey<int>(_match.playerDrawn),
                    width: width,
                    child: CadreFighterCard(fighter: card),
                  ),
                ),
              );
            },
          ),
        ),
        _SlotRail(
          match: _match,
          card: card,
          armed: _armed,
          onArm: _arm,
        ),
        _Footer(
          match: _match,
          card: card,
          armed: _armed,
          onPass: _pass,
          onPlace: _place,
        ),
      ],
    );
  }
}

/// The arithmetic that does the work of a token. Once the draws left equal the
/// slots left, passing is gone — so the count is the pressure and it is stated
/// rather than hidden behind a disabled button.
class _DraftMeta extends StatelessWidget {
  final CadreSquadMatch match;

  const _DraftMeta({required this.match});

  @override
  Widget build(BuildContext context) {
    final open = match.openSlots.length;
    final locked = match.mustPlace;

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Draw ${match.playerDrawn + 1} of ${CadreSquadMatch.drawsPerSide}',
            style: GoogleFonts.dmSans(
              color: CadreColors.ivoryDim,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            locked
                ? '${match.drawsLeft} draws for $open slots'
                : '$open ${open == 1 ? 'slot' : 'slots'} open',
            style: GoogleFonts.dmSans(
              color: locked ? CadreColors.coral : CadreColors.ivoryFaint,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Five slots, each showing what the face-up card would be worth in it.
class _SlotRail extends StatelessWidget {
  final CadreSquadMatch match;
  final CadreFighter card;
  final String? armed;
  final void Function(String slot) onArm;

  const _SlotRail({
    required this.match,
    required this.card,
    required this.armed,
    required this.onArm,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      // No CrossAxisAlignment.stretch here. The rail sits straight in a
      // Column, so its incoming max height is unbounded, and stretch would
      // hand every chip a tight height of infinity. The chips size
      // themselves instead.
      child: Row(
        children: <Widget>[
          for (var i = 0; i < CadreSlots.all.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _SlotChip(
                slot: CadreSlots.all[i],
                held: match.playerSquad[CadreSlots.all[i]],
                card: card,
                armed: armed == CadreSlots.all[i],
                onTap: () => onArm(CadreSlots.all[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  final String slot;
  final CadreFighter? held;
  final CadreFighter card;
  final bool armed;
  final VoidCallback onTap;

  const _SlotChip({
    required this.slot,
    required this.held,
    required this.card,
    required this.armed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final taken = held;
    final value = taken != null
        ? CadreSquadMatch.contribution(taken, slot).round()
        : CadreSquadMatch.contribution(card, slot).round();

    return GestureDetector(
      onTap: taken != null ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 94,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        decoration: BoxDecoration(
          color: armed ? const Color(0x24E8624A) : CadreColors.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: armed
                ? CadreColors.coral
                : (taken != null ? CadreColors.hairline : CadreColors.coralEdge),
            width: armed ? 1.6 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (taken != null)
              _Face(url: taken.imageUrl)
            else
              Text(
                '$value',
                maxLines: 1,
                style: GoogleFonts.spaceGrotesk(
                  color: armed ? CadreColors.ivory : CadreColors.ivoryDim,
                  fontSize: 18,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 6),
            Text(
              CadreSlots.labels[slot] ?? slot,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                color: taken != null
                    ? CadreColors.ivoryDim
                    : (armed ? CadreColors.coral : CadreColors.ivoryDim),
                fontSize: 10,
                height: 1.1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              taken != null
                  ? '$value'
                  : '\u00D7${cadreWeightLabel(CadreSquadMatch.weights[slot])}',
              maxLines: 1,
              style: GoogleFonts.spaceGrotesk(
                color: CadreColors.ivoryFaint,
                fontSize: 9.5,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Face extends StatelessWidget {
  final String url;

  const _Face({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          fadeInDuration: const Duration(milliseconds: 160),
          placeholder: (_, __) => const ColoredBox(color: CadreColors.bg),
          errorWidget: (_, __, ___) => const ColoredBox(
            color: CadreColors.bg,
            child: Icon(
              Icons.person_outline,
              size: 16,
              color: CadreColors.ivoryFaint,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pass on the left, commit on the right. Both stay in place all match so
/// neither moves under a thumb that is already reaching for it.
class _Footer extends StatelessWidget {
  final CadreSquadMatch match;
  final CadreFighter card;
  final String? armed;
  final VoidCallback onPass;
  final VoidCallback onPlace;

  const _Footer({
    required this.match,
    required this.card,
    required this.armed,
    required this.onPass,
    required this.onPlace,
  });

  @override
  Widget build(BuildContext context) {
    final slot = armed;
    final label = slot == null
        ? 'Tap a slot'
        : 'Place as ${CadreSlots.labels[slot] ?? slot}'
            '  \u00B7  ${CadreSquadMatch.contribution(card, slot).round()}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 2, 22, 18),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: _GhostButton(
              label: match.canPass ? 'Pass' : 'Locked',
              enabled: match.canPass,
              onTap: onPass,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _PrimaryButton(
              label: label,
              enabled: slot != null,
              onTap: onPlace,
            ),
          ),
        ],
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _GhostButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: CadreColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? CadreColors.coralEdge : CadreColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            color: enabled ? CadreColors.ivory : CadreColors.ivoryFaint,
            fontSize: 15,
            fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(
                  colors: [CadreColors.ember, CadreColors.coral],
                )
              : null,
          color: enabled ? null : CadreColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: GoogleFonts.dmSans(
              color: enabled ? Colors.white : CadreColors.ivoryFaint,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Both squads read as one team sheet rather than two lists, so the slot you
/// lost is the thing you see, not a total you have to take on trust.
class _SquadResult extends StatelessWidget {
  final CadreSquadMatch match;
  final VoidCallback onDone;

  const _SquadResult({required this.match, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final String headline;
    switch (match.outcome) {
      case CadreSquadOutcome.playerWins:
        headline = 'You win';
        break;
      case CadreSquadOutcome.opponentWins:
        headline = 'Bot wins';
        break;
      case CadreSquadOutcome.tie:
        headline = 'Dead level';
        break;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              color: CadreColors.ivory,
              fontSize: 38,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${match.playerScore} to ${match.opponentScore}',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              color: CadreColors.ivoryDim,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'YOU',
                  textAlign: TextAlign.right,
                  style: _capStyle(),
                ),
              ),
              const SizedBox(width: 76),
              Expanded(
                child: Text(
                  'BOT',
                  textAlign: TextAlign.left,
                  style: _capStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final slot in CadreSlots.all) ...[
            _ResultRow(
              slot: slot,
              mine: match.playerSquad[slot],
              theirs: match.opponentSquad[slot],
            ),
            const SizedBox(height: 10),
          ],
          if (match.playerPassed.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Passed on ${match.playerPassed.map((f) => f.name).join(', ')}',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                color: CadreColors.ivoryFaint,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 26),
          _PrimaryButton(
            label: 'Back to the lobby',
            enabled: true,
            onTap: onDone,
          ),
        ],
      ),
    );
  }

  TextStyle _capStyle() => GoogleFonts.dmSans(
        color: CadreColors.ivoryFaint,
        fontSize: 10,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
      );
}

class _ResultRow extends StatelessWidget {
  final String slot;
  final CadreFighter? mine;
  final CadreFighter? theirs;

  const _ResultRow({
    required this.slot,
    required this.mine,
    required this.theirs,
  });

  @override
  Widget build(BuildContext context) {
    final a = mine == null ? 0 : CadreSquadMatch.contribution(mine!, slot).round();
    final b = theirs == null
        ? 0
        : CadreSquadMatch.contribution(theirs!, slot).round();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _ResultSide(
            fighter: mine,
            value: a,
            won: a > b,
            alignEnd: true,
          ),
        ),
        SizedBox(
          width: 76,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                (CadreSlots.labels[slot] ?? slot).toUpperCase(),
                maxLines: 1,
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  color: CadreColors.ivoryDim,
                  fontSize: 10,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '\u00D7${cadreWeightLabel(CadreSquadMatch.weights[slot])}',
                maxLines: 1,
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  color: CadreColors.ivoryFaint,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _ResultSide(
            fighter: theirs,
            value: b,
            won: b > a,
            alignEnd: false,
          ),
        ),
      ],
    );
  }
}

class _ResultSide extends StatelessWidget {
  final CadreFighter? fighter;
  final int value;
  final bool won;
  final bool alignEnd;

  const _ResultSide({
    required this.fighter,
    required this.value,
    required this.won,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    final name = fighter?.name ?? 'Empty';

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: GoogleFonts.dmSans(
            color: won ? CadreColors.ivory : CadreColors.ivoryDim,
            fontSize: 12.5,
            fontWeight: won ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$value',
          maxLines: 1,
          style: GoogleFonts.spaceGrotesk(
            color: won ? CadreColors.coral : CadreColors.ivoryFaint,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 1.30 reads as noise next to 1.15, so trailing zeros come off.
String cadreWeightLabel(double? weight) {
  if (weight == null) return '1';
  final text = weight.toStringAsFixed(2);
  return text.endsWith('0') ? text.substring(0, text.length - 1) : text;
}
