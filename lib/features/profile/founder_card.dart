import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/founder_service.dart';

/// The Founder card, its placeholder and the Founder pill as they were
/// before Hanko: coral, with a glow, a 120 px watermark and three perk rows.
/// Kept, switched off, as design history (question 57).
const bool _preHankoFounder = false;

/// A premium "Founder" card shown to one of the first 50 users.
/// Minimal, classy layout — displays founder number, join date, and perks.
///
/// Collapsed in Hanko (question 57, as question 2 recommends): the Founder
/// pill under your name already says you are a founder, so the big card
/// becomes a short note at the foot of Profile, like the colophon at the end
/// of a printed book, which says which edition you hold. It keeps everything
/// the card said: your number of the first fifty, the day you joined and
/// the three perks, in washi and stone with the pill's icon. No coral: in
/// Hanko coral marks only your verdicts. A few lines where the card took
/// about 280 px.
class FounderCard extends StatelessWidget {
  final FounderStatus status;
  const FounderCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (!status.isFounder) return const SizedBox.shrink();
    if (_preHankoFounder) return _buildFullCard();

    final number = status.number;
    final joined = status.joinedAt;
    final who = number == null
        ? 'One of the first fifty members of Hanj'
        : 'No.\u00A0$number of the first fifty members of Hanj';
    final when = joined == null ? '' : ', joined ${_formatDay(joined)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppTheme.hankoGutter, 26, AppTheme.hankoGutter, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.workspace_premium_sharp,
              size: 22, color: AppTheme.hankoStone),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Founding member',
                  style: AppTheme.hankoSans(
                      fontSize: 15, weight: FontWeight.w500, height: 1.25),
                ),
                const SizedBox(height: 4),
                Text(
                  '$who$when. Your badge and number are yours for good, and '
                  'you get new features early.',
                  style: AppTheme.hankoSans(
                    fontSize: AppTheme.hankoMetaSize,
                    color: AppTheme.hankoStone,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "14 March 2025", held together by no-break spaces so a date never
  /// splits across lines ("joined 14 / March 2025" on the emulator run). A
  /// date is short enough to fit the note's column on a 360 px phone even at
  /// 2.0x text, so the no-break spaces never force a break inside a word.
  static String _formatDay(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    return '${d.day}\u00A0${months[d.month - 1]}\u00A0${d.year}';
  }

  /// The full card as it was before Hanko ([_preHankoFounder]).
  Widget _buildFullCard() {
    final number = status.number ?? 0;
    final joined = status.joinedAt;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1614), Color(0xFF0E0C0B)],
        ),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.10),
            blurRadius: 24,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle large watermark number in the corner
          Positioned(
            right: -8,
            bottom: -24,
            child: Text(
              '#$number',
              style: AppTheme.serif(
                fontSize: 120,
                weight: FontWeight.w700,
              ).copyWith(
                color: AppTheme.primary.withValues(alpha: 0.06),
                height: 1,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Icon(Icons.workspace_premium_outlined,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'FOUNDER',
                      style: AppTheme.mono(
                        fontSize: 12,
                        color: AppTheme.primary,
                        letterSpacing: 3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'No. ${number.toString().padLeft(2, '0')} / 50',
                      style: AppTheme.mono(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Title
                Text(
                  'Founding Member',
                  style: AppTheme.serif(fontSize: 26, weight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Among the first fifty members of Hanj.',
                  style: AppTheme.sans(
                      fontSize: 13, color: AppTheme.textSecondary),
                ),

                if (joined != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Joined ${_formatDate(joined)}',
                    style: AppTheme.mono(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                        letterSpacing: 1),
                  ),
                ],

                const SizedBox(height: 20),
                Divider(color: AppTheme.primary.withValues(alpha: 0.15), height: 1),
                const SizedBox(height: 16),

                // Perks
                _perk(Icons.verified_outlined, 'Permanent founder badge'),
                const SizedBox(height: 10),
                _perk(Icons.auto_awesome_outlined,
                    'Early access to new features'),
                const SizedBox(height: 10),
                _perk(Icons.tag_rounded, 'Reserved founder number'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _perk(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppTheme.sans(fontSize: 13, color: AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime d) {
    const months = [
      'JAN','FEB','MAR','APR','MAY','JUN',
      'JUL','AUG','SEP','OCT','NOV','DEC'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// Skeleton shown in the founder card's footprint while founder status is
/// still being resolved for the first time, so the real card fills in rather
/// than appearing from nothing and shoving the rest of the profile down.
///
/// Mirrors [FounderCard]'s chrome (same margin, radius, gradient) and the
/// shape of its content rows, so the reserved height lands within a few px of
/// the real card. It is only ever seen once per install — after the first
/// successful resolve, [FounderService.getCachedStatus] answers from disk on
/// the first frame and this never renders again.
///
/// In Hanko it reserves nothing: the collapsed note sits last on Profile, so
/// when it fills in nothing below it moves, while a reserved box would leave
/// an empty gap on the way for everyone who isn't a founder.
class FounderCardPlaceholder extends StatelessWidget {
  const FounderCardPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_preHankoFounder) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1614), Color(0xFF0E0C0B)],
        ),
        border: Border.all(
          // Dimmer than the real card's 0.45 so it reads as pending, not live.
          color: AppTheme.primary.withValues(alpha: 0.18),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row — premium icon, 'FOUNDER', 'No. xx / 50'
            Row(
              children: [
                _block(20, 20, radius: 4),
                const SizedBox(width: 8),
                _block(78, 12),
                const Spacer(),
                _block(64, 11),
              ],
            ),
            const SizedBox(height: 18),
            _block(210, 34), // 'Founding Member' — 26px serif
            const SizedBox(height: 6),
            _block(240, 17), // 'Among the first fifty members of Hanj.'
            const SizedBox(height: 4),
            _block(150, 13), // 'Joined MMM D, YYYY'
            const SizedBox(height: 20),
            Divider(color: AppTheme.primary.withValues(alpha: 0.15), height: 1),
            const SizedBox(height: 16),
            _perkRow(),
            const SizedBox(height: 10),
            _perkRow(),
            const SizedBox(height: 10),
            _perkRow(),
          ],
        ),
      ),
    );
  }

  Widget _perkRow() => Row(
        children: [
          _block(16, 16, radius: 4),
          const SizedBox(width: 10),
          _block(180, 17),
        ],
      );

  static Widget _block(double w, double h, {double radius = 3}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: AppTheme.textMuted.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
}

/// Compact founder badge (a small pill) for showing inline, e.g. next to
/// the user's name on their profile header.
///
/// In Hanko it is stamped rather than lit, like the rarity mark on a Hanj
/// Card: a 1 px edge outline with Hanko's 2 px corners (4.02:1 on sumi),
/// "Founder #7" in Jost 500 washi (15.3:1) and the icon in stone. Coral
/// marks only your verdicts now, so the pill no longer borrows it. Kept
/// small and unfilled so it reads as a label, not as a chip to press.
class FounderBadge extends StatelessWidget {
  final int number;
  const FounderBadge({super.key, required this.number});

  @override
  Widget build(BuildContext context) {
    if (_preHankoFounder) return _buildCoralPill();
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.hankoRadius),
        border: Border.all(color: AppTheme.hankoEdge),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium_sharp,
                size: 14, color: AppTheme.hankoStone),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                'Founder #$number',
                style: AppTheme.hankoSans(
                  fontSize: AppTheme.hankoLabelSize,
                  weight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The coral pill as it was before Hanko ([_preHankoFounder]).
  Widget _buildCoralPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_outlined,
              size: 12, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(
            'FOUNDER #$number',
            style: AppTheme.mono(
              fontSize: 10,
              color: AppTheme.primary,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
