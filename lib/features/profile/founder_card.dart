import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../services/founder_service.dart';

/// A premium "Founder" card shown to one of the first 50 users.
/// Minimal, classy layout — displays founder number, join date, and perks.
class FounderCard extends StatelessWidget {
  final FounderStatus status;
  const FounderCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (!status.isFounder) return const SizedBox.shrink();

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

/// Compact founder badge (a small pill) for showing inline, e.g. next to
/// the user's name on their profile header.
class FounderBadge extends StatelessWidget {
  final int number;
  const FounderBadge({super.key, required this.number});

  @override
  Widget build(BuildContext context) {
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
