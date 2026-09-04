import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stats Screen
// ─────────────────────────────────────────────────────────────────────────────

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Stats',
            style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestoreService.getAnimeList(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary, strokeWidth: 2),
            );
          }

          final docs = snapshot.data!.docs;

          // ── Compute ─────────────────────────────────────────
          int total = docs.length;
          int completed = 0, watching = 0, planToWatch = 0, dropped = 0;
          double totalRating = 0;
          int ratedCount = 0;
          int totalEpisodes = 0;
          Map<String, int> genreCounts = {};
          Map<String, int> monthlyAdded = {};
          Map<String, int> ratingDist = {
            '1-2': 0, '3-4': 0, '5-6': 0, '7-8': 0, '9-10': 0
          };
          DateTime? lastWatched;

          for (final doc in docs) {
            final d = doc.data() as Map<String, dynamic>;

            switch (d['status']) {
              case 'WATCHING':      watching++;      break;
              case 'COMPLETED':     completed++;     break;
              case 'PLAN_TO_WATCH': planToWatch++;   break;
              case 'DROPPED':       dropped++;       break;
            }

            if (d['userRating'] != null) {
              final r = (d['userRating'] as num).toDouble();
              totalRating += r;
              ratedCount++;
              if (r <= 2)       ratingDist['1-2'] = ratingDist['1-2']! + 1;
              else if (r <= 4)  ratingDist['3-4'] = ratingDist['3-4']! + 1;
              else if (r <= 6)  ratingDist['5-6'] = ratingDist['5-6']! + 1;
              else if (r <= 8)  ratingDist['7-8'] = ratingDist['7-8']! + 1;
              else              ratingDist['9-10'] = ratingDist['9-10']! + 1;
            }

            if (d['status'] == 'COMPLETED' && d['episodes'] != null) {
              totalEpisodes += (d['episodes'] as int);
            } else if (d['currentEpisode'] != null) {
              totalEpisodes += (d['currentEpisode'] as int);
            }

            final genres = d['genres'] as List<dynamic>?;
            if (genres != null) {
              for (final g in genres) {
                genreCounts[g] = (genreCounts[g] ?? 0) + 1;
              }
            }

            final addedAt = d['addedAt'] as Timestamp?;
            if (addedAt != null) {
              final dt = addedAt.toDate();
              final key =
                  '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
              monthlyAdded[key] = (monthlyAdded[key] ?? 0) + 1;
            }

            final lw = d['lastWatched'] as Timestamp?;
            if (lw != null) {
              final d2 = lw.toDate();
              if (lastWatched == null || d2.isAfter(lastWatched!)) {
                lastWatched = d2;
              }
            }
          }

          final avgRating =
              ratedCount > 0 ? (totalRating / ratedCount) : 0.0;
          final watchHours = (totalEpisodes * 24 / 60).floor();
          final watchDays = (watchHours / 24).floor();
          final completionRate =
              total > 0 ? (completed / total * 100) : 0.0;
          final daysSince = lastWatched != null
              ? DateTime.now().difference(lastWatched!).inDays
              : 999;

          final topGenres = (genreCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .take(5)
              .toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Hero row: time + completion ──────────────────
                Row(
                  children: [
                    Expanded(
                      child: _HeroCard(
                        value: watchDays > 0
                            ? '${watchDays}d'
                            : '${watchHours}h',
                        subtitle: 'watch time',
                        color: AppTheme.primary,
                        icon: Icons.schedule_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HeroCard(
                        value:
                            '${completionRate.toStringAsFixed(0)}%',
                        subtitle: 'completed',
                        color: AppTheme.completed,
                        icon: Icons.emoji_events_rounded,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Secondary stats ──────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'Total',
                        value: '$total',
                        icon: Icons.grid_view_rounded,
                        color: AppTheme.accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: 'Episodes',
                        value: '$totalEpisodes',
                        icon: Icons.play_arrow_rounded,
                        color: AppTheme.planToWatch,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: 'Avg Score',
                        value: avgRating > 0
                            ? avgRating.toStringAsFixed(1)
                            : '—',
                        icon: Icons.star_rounded,
                        color: const Color(0xFFFFCC48),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: 'Activity',
                        value: daysSince == 0
                            ? 'Today'
                            : daysSince == 999
                                ? '—'
                                : '${daysSince}d ago',
                        icon: Icons.local_fire_department_rounded,
                        color: daysSince <= 1
                            ? Colors.orange
                            : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── Status breakdown ─────────────────────────────
                _SectionHeader('Status Breakdown'),
                const SizedBox(height: 14),
                _StatusBreakdown(
                  total: total,
                  watching: watching,
                  completed: completed,
                  planToWatch: planToWatch,
                  dropped: dropped,
                ),

                const SizedBox(height: 28),

                // ── Monthly activity chart ───────────────────────
                if (monthlyAdded.isNotEmpty) ...[
                  _SectionHeader('Monthly Activity'),
                  const SizedBox(height: 14),
                  Container(
                    height: 180,
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: AppTheme.cardBorder),
                    ),
                    child: _MonthlyChart(monthlyData: monthlyAdded),
                  ),
                  const SizedBox(height: 28),
                ],

                // ── Rating distribution ──────────────────────────
                if (ratedCount > 0) ...[
                  _SectionHeader('Rating Distribution'),
                  const SizedBox(height: 14),
                  _RatingDistribution(
                    ratingDist: ratingDist,
                    total: ratedCount,
                  ),
                  const SizedBox(height: 28),
                ],

                // ── Genre affinities ─────────────────────────────
                if (topGenres.isNotEmpty) ...[
                  _SectionHeader('Genre Affinities'),
                  const SizedBox(height: 14),
                  _GenreAffinities(
                    topGenres: topGenres,
                    totalGenreEntries: genreCounts.values.fold(
                        0, (a, b) => a + b),
                  ),
                  const SizedBox(height: 28),
                ],

                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _HeroCard({
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTheme.serif(
                fontSize: 34,
                weight: FontWeight.w700,
                color: color),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle.toUpperCase(),
            style: AppTheme.mono(
                fontSize: 9,
                color: color.withValues(alpha: 0.8),
                letterSpacing: 1.2),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mini Stat
// ─────────────────────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTheme.sans(
                fontSize: 14,
                weight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTheme.mono(
                fontSize: 8,
                color: AppTheme.textMuted,
                letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Breakdown (stacked bar + legend)
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBreakdown extends StatelessWidget {
  final int total, watching, completed, planToWatch, dropped;

  const _StatusBreakdown({
    required this.total,
    required this.watching,
    required this.completed,
    required this.planToWatch,
    required this.dropped,
  });

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Center(
          child: Text('No anime in your list yet',
              style: AppTheme.sans(
                  color: AppTheme.textMuted, fontSize: 14)),
        ),
      );
    }

    final segments = [
      (watching, AppTheme.watching, 'Watching'),
      (completed, AppTheme.completed, 'Completed'),
      (planToWatch, AppTheme.planToWatch, 'Plan to Watch'),
      (dropped, AppTheme.dropped, 'Dropped'),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: [
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: Row(
                children: segments.map((seg) {
                  final frac = seg.$1 / total;
                  if (frac == 0) return const SizedBox.shrink();
                  return Flexible(
                    flex: seg.$1,
                    child: Container(color: seg.$2),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Cards
          Row(
            children: segments.map((seg) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _StatusItem(
                    count: seg.$1,
                    label: seg.$3,
                    color: seg.$2,
                    pct: total > 0
                        ? (seg.$1 / total * 100)
                        : 0,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final double pct;

  const _StatusItem({
    required this.count,
    required this.label,
    required this.color,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 6),
        Text(
          '$count',
          style: AppTheme.sans(
              fontSize: 18,
              weight: FontWeight.w700,
              color: AppTheme.textPrimary),
        ),
        Text(
          label,
          style: AppTheme.mono(
              fontSize: 8,
              color: AppTheme.textMuted,
              letterSpacing: 0.5),
          maxLines: 2,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Monthly Activity Chart
// ─────────────────────────────────────────────────────────────────────────────

class _MonthlyChart extends StatelessWidget {
  final Map<String, int> monthlyData;

  const _MonthlyChart({required this.monthlyData});

  @override
  Widget build(BuildContext context) {
    final sorted = monthlyData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final last6 = sorted.length > 6
        ? sorted.sublist(sorted.length - 6)
        : sorted;
    final maxY = last6.isEmpty
        ? 1.0
        : (last6.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1)
            .toDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppTheme.surfaceMid,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final count = rod.toY.toInt();
              return BarTooltipItem(
                '$count',
                AppTheme.sans(
                    fontSize: 12,
                    weight: FontWeight.w700,
                    color: AppTheme.primary),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i >= last6.length) return const SizedBox.shrink();
                final parts = last6[i].key.split('-');
                final month = int.parse(parts[1]);
                const abbr = [
                  'J', 'F', 'M', 'A', 'M', 'J',
                  'J', 'A', 'S', 'O', 'N', 'D'
                ];
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    abbr[month - 1],
                    style: AppTheme.mono(
                        fontSize: 9, color: AppTheme.textMuted),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 4 ? (maxY / 4).ceilToDouble() : 1,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppTheme.border.withValues(alpha: 0.5),
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        barGroups: last6.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.value.toDouble(),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    AppTheme.primary.withValues(alpha: 0.6),
                    AppTheme.primary,
                  ],
                ),
                width: 18,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rating Distribution
// ─────────────────────────────────────────────────────────────────────────────

class _RatingDistribution extends StatelessWidget {
  final Map<String, int> ratingDist;
  final int total;

  const _RatingDistribution(
      {required this.ratingDist, required this.total});

  @override
  Widget build(BuildContext context) {
    final buckets = ['1-2', '3-4', '5-6', '7-8', '9-10'];
    final maxVal = ratingDist.values.fold(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: buckets.map((b) {
          final count = ratingDist[b] ?? 0;
          final frac = maxVal > 0 ? count / maxVal : 0.0;
          final pct = total > 0 ? (count / total * 100) : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(
                    b,
                    style: AppTheme.mono(
                        fontSize: 10, color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 8,
                      backgroundColor:
                          AppTheme.surfaceLight,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _ratingColor(b),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 28,
                  child: Text(
                    '$count',
                    style: AppTheme.sans(
                        fontSize: 12,
                        weight: FontWeight.w600,
                        color: AppTheme.textSecondary),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _ratingColor(String bucket) {
    switch (bucket) {
      case '9-10': return AppTheme.completed;
      case '7-8':  return AppTheme.primary;
      case '5-6':  return AppTheme.accent;
      case '3-4':  return AppTheme.warning;
      default:     return AppTheme.dropped;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Genre Affinities
// ─────────────────────────────────────────────────────────────────────────────

class _GenreAffinities extends StatelessWidget {
  final List<MapEntry<String, int>> topGenres;
  final int totalGenreEntries;

  const _GenreAffinities(
      {required this.topGenres, required this.totalGenreEntries});

  // Cycle through a warm palette
  static const _genreColors = [
    AppTheme.primary,
    AppTheme.accent,
    AppTheme.planToWatch,
    AppTheme.completed,
    AppTheme.dropped,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        children: topGenres.asMap().entries.map((entry) {
          final i = entry.key;
          final genre = entry.value.key;
          final count = entry.value.value;
          final frac = totalGenreEntries > 0
              ? count / totalGenreEntries
              : 0.0;
          final color = _genreColors[i % _genreColors.length];
          final pct = (frac * 100).toStringAsFixed(0);

          return Padding(
            padding: EdgeInsets.only(bottom: i < topGenres.length - 1 ? 14 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      genre,
                      style: AppTheme.sans(
                          fontSize: 13,
                          weight: FontWeight.w500,
                          color: AppTheme.textPrimary),
                    ),
                    const Spacer(),
                    Text(
                      '$count  ·  $pct%',
                      style: AppTheme.mono(
                          fontSize: 10, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 6,
                    backgroundColor: AppTheme.surfaceLight,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title.toUpperCase(),
          style: AppTheme.mono(
              fontSize: 11,
              color: AppTheme.textSecondary,
              letterSpacing: 1.4),
        ),
      ],
    );
  }
}
