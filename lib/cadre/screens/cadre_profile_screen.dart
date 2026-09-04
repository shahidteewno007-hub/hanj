import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cadre_stats.dart';
import '../services/cadre_stats_service.dart';
import '../widgets/cadre_fighter_card.dart';

/// The Cadre record. Bot matches only.
class CadreProfileScreen extends StatefulWidget {
  const CadreProfileScreen({super.key});

  @override
  State<CadreProfileScreen> createState() => _CadreProfileScreenState();
}

class _CadreProfileScreenState extends State<CadreProfileScreen> {
  CadreStats _stats = CadreStatsService.instance.cached;

  @override
  Widget build(BuildContext context) {
    final s = _stats;

    return Scaffold(
      backgroundColor: CadreColors.bg,
      appBar: AppBar(
        backgroundColor: CadreColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: CadreColors.ivory),
        title: Text(
          'Record',
          style: GoogleFonts.dmSans(
            color: CadreColors.ivoryDim,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _WinRateBlock(stats: s),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _StatTile(label: 'Played', value: '${s.played}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    label: 'Cards taken',
                    value: '${s.cardsTaken}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Current streak',
                    value: '${s.currentStreak}',
                    accent: s.currentStreak >= 3,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    label: 'Best streak',
                    value: '${s.bestStreak}',
                  ),
                ),
              ],
            ),
            if (s.lastPool != null) ...[
              const SizedBox(height: 12),
              _StatTile(label: 'Last pool', value: s.lastPool!, wide: true),
            ],
            const SizedBox(height: 28),
            Text(
              'Only matches against the bot are recorded. Pass-and-play has '
              'two people on one phone, so there is no honest way to say '
              'whose record it is.',
              style: GoogleFonts.dmSans(
                color: CadreColors.ivoryFaint,
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _confirmReset,
              child: Container(
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: CadreColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CadreColors.hairline),
                ),
                child: Text(
                  'Reset record',
                  style: GoogleFonts.dmSans(
                    color: CadreColors.ivoryDim,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CadreColors.surface,
        title: Text(
          'Reset your record?',
          style: GoogleFonts.playfairDisplay(
            color: CadreColors.ivory,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Every match, streak and card count goes back to zero. This cannot '
          'be undone.',
          style: GoogleFonts.dmSans(
            color: CadreColors.ivoryDim,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Keep it',
              style: GoogleFonts.dmSans(color: CadreColors.ivoryDim),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Reset',
              style: GoogleFonts.dmSans(
                color: CadreColors.coral,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await CadreStatsService.instance.reset();
    if (!mounted) return;
    setState(() => _stats = CadreStatsService.instance.cached);
  }
}

/// The signature block: the record read as a single bar rather than a number.
class _WinRateBlock extends StatelessWidget {
  final CadreStats stats;
  const _WinRateBlock({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.played == 0 ? 1 : stats.played;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: CadreColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: CadreColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stats.hasRecord
                    ? '${(stats.winRate * 100).round()}'
                    : '\u2014',
                style: GoogleFonts.spaceGrotesk(
                  color: CadreColors.ivory,
                  fontSize: 54,
                  height: 0.95,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (stats.hasRecord)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 3),
                  child: Text(
                    '%',
                    style: GoogleFonts.spaceGrotesk(
                      color: CadreColors.coral,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  stats.hasRecord ? 'win rate' : 'no matches yet',
                  style: GoogleFonts.dmSans(
                    color: CadreColors.ivoryFaint,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  // Only non-zero segments are laid out. A zero-flex Expanded
                  // is legal but pointless, and this keeps the bar honest.
                  if (stats.won > 0)
                    Expanded(
                      flex: stats.won * 1000 ~/ total,
                      child: const ColoredBox(color: CadreColors.coral),
                    ),
                  if (stats.lost > 0)
                    Expanded(
                      flex: stats.lost * 1000 ~/ total,
                      child: const ColoredBox(color: Color(0xFF2A211C)),
                    ),
                  if (!stats.hasRecord)
                    const Expanded(
                      child: ColoredBox(color: Color(0xFF1C1917)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Legend(color: CadreColors.coral, label: 'Won ${stats.won}'),
              const SizedBox(width: 16),
              _Legend(
                color: const Color(0xFF2A211C),
                label: 'Lost ${stats.lost}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.dmSans(
            color: CadreColors.ivoryDim,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool accent;
  final bool wide;

  const _StatTile({
    required this.label,
    required this.value,
    this.accent = false,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: CadreColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent ? CadreColors.coralEdge : CadreColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.dmSans(
              color: CadreColors.ivoryFaint,
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: wide ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: wide
                ? GoogleFonts.dmSans(
                    color: CadreColors.ivory,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  )
                : GoogleFonts.spaceGrotesk(
                    color: accent ? CadreColors.coral : CadreColors.ivory,
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w700,
                  ),
          ),
        ],
      ),
    );
  }
}
