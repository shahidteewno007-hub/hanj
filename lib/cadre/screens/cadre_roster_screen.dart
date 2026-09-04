import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cadre_fighter.dart';
import '../models/cadre_pool.dart';
import '../widgets/cadre_fighter_card.dart';

/// Read-only view of a pool: everyone in it, strongest first.
///
/// This screen deliberately does not search, edit, or start anything. The
/// lobby owns starting a match and the pool builder owns changing what is in
/// the pool. All this answers is "who is in here, and what are they rated" —
/// which is otherwise only visible for the two seconds a card is on the table.
///
/// A crossover pool is shown one cast at a time rather than merged, because
/// power is normalised inside each anime. Ranking a One Piece 82 against a
/// Frieren 82 in a single list would imply a comparison the numbers do not
/// actually make.
class CadreRosterScreen extends StatelessWidget {
  final CadrePool pool;

  const CadreRosterScreen({super.key, required this.pool});

  /// Thresholds mirror the frames in cadre_frame.dart. Kept local so this
  /// screen doesn't bind to that file's enum member names — if those two ever
  /// disagree, cadre_frame.dart is the one telling the truth.
  static String tierLabel(int power) {
    if (power >= 90) return 'Apex';
    if (power >= 75) return 'Elite';
    if (power >= 60) return 'Solid';
    return 'Base';
  }

  @override
  Widget build(BuildContext context) {
    final rosters = pool.rosters;
    final multi = rosters.length > 1;

    return Scaffold(
      backgroundColor: CadreColors.bg,
      appBar: AppBar(
        backgroundColor: CadreColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: CadreColors.ivory),
        title: Text(
          'Roster',
          style: GoogleFonts.dmSans(
            color: CadreColors.ivoryDim,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pool.title,
                      style: GoogleFonts.playfairDisplay(
                        color: CadreColors.ivory,
                        fontSize: 30,
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${pool.length} characters \u00B7 strongest first',
                      style: GoogleFonts.spaceGrotesk(
                        color: CadreColors.ivoryFaint,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ScoringNote(pool: pool),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            for (final roster in rosters) ...[
              if (multi)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 15,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [CadreColors.ember, CadreColors.coral],
                            ),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            roster.title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.dmSans(
                              color: CadreColors.ivoryDim,
                              fontSize: 11,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${roster.length}',
                          style: GoogleFonts.spaceGrotesk(
                            color: CadreColors.ivoryFaint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                sliver: _RosterGrid(roster: roster),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One cast, sorted strongest first.
class _RosterGrid extends StatelessWidget {
  final CadreRoster roster;

  const _RosterGrid({required this.roster});

  @override
  Widget build(BuildContext context) {
    // Copied before sorting — the roster's own list is shared with the pool
    // and the deal, and reordering it underneath them would be a nasty bug.
    final fighters = List<CadreFighter>.of(roster.fighters)
      ..sort((a, b) => b.power.compareTo(a.power));

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2 / 3,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final fighter = fighters[i];
          return CadreFighterCard(
            fighter: fighter,
            onTap: () => _showDetail(context, fighter),
          );
        },
        childCount: fighters.length,
      ),
    );
  }
}

/// Says out loud what the power number currently measures.
///
/// Until the enrichment pass lands, power is derived from AniList favourites,
/// which tracks popularity rather than strength. Saying so is better than
/// letting someone find Itachi below Kakashi and conclude the game is broken.
class _ScoringNote extends StatelessWidget {
  final CadrePool pool;

  const _ScoringNote({required this.pool});

  @override
  Widget build(BuildContext context) {
    final total = pool.fighters.length;
    final ranked = pool.fighters.where((f) => f.enriched).length;
    final enriched = total > 0 && ranked == total;
    final partial = ranked > 0 && ranked < total;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: CadreColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: CadreColors.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            enriched || partial
                ? Icons.verified_outlined
                : Icons.info_outline_rounded,
            size: 15,
            color: enriched || partial
                ? CadreColors.coral
                : CadreColors.ivoryFaint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              enriched
                  ? 'Rated on how each character performs in the source, '
                      'normalised inside their own anime.'
                  : partial
                      ? '$ranked of $total ranked on strength. The rest are '
                          'still scored on how prominent they are in the '
                          'source, which measures fame more than power.'
                      : 'Rated on how prominent each character is in the '
                          'source, normalised inside their own anime. That '
                          'measures fame more than strength, so the order '
                          'will not always match a power scaling argument.',
              style: GoogleFonts.dmSans(
                color: CadreColors.ivoryDim,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _showDetail(BuildContext context, CadreFighter fighter) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: CadreColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  fighter.name,
                  style: GoogleFonts.playfairDisplay(
                    color: CadreColors.ivory,
                    fontSize: 22,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${fighter.power}',
                    style: GoogleFonts.spaceGrotesk(
                      color: CadreColors.ivory,
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    CadreRosterScreen.tierLabel(fighter.power).toUpperCase(),
                    style: GoogleFonts.dmSans(
                      color: CadreColors.coral,
                      fontSize: 10,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${fighter.favourites} favourites  \u00B7  ${fighter.role.label.toLowerCase()}',
            style: GoogleFonts.spaceGrotesk(
              color: CadreColors.ivoryDim,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            fighter.enriched
                ? 'Enriched roster.'
                : 'Scored from favourites. Role fit is neutral until the '
                    'enrichment pass runs.',
            style: GoogleFonts.dmSans(
              color: CadreColors.ivoryFaint,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    ),
  );
}
