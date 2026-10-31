import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../services/firestore_service.dart';
import '../../widgets/hanko_seal_register.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Stats Screen
// ─────────────────────────────────────────────────────────────────────────────

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  /// The page before Hanko (question 73): hero cards and stat tiles, a
  /// stacked bar in the status colours, the monthly chart in a coral
  /// gradient, five rating buckets and genre bars in a cycle of colours, each
  /// in a rounded card under a coral rule. Kept, switched off, as design
  /// history and a deletion candidate, so its widgets keep their call sites.
  static const bool _preHanko = false;

  // Hanko's press: an 8% washi wash, no ripple, square corners (Profile's).
  static const ButtonStyle _pressStyle = ButtonStyle(
    overlayColor: WidgetStatePropertyAll(AppTheme.hankoPressWash),
    splashFactory: NoSplash.splashFactory,
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppTheme.hankoRadius)),
    )),
  );

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Detail's back arrow (Hanko H3), with the label it lacked.
        leading: IconButton(
          tooltip: 'Back',
          style: _pressStyle,
          icon: const Icon(Icons.arrow_back_sharp, color: AppTheme.hankoWashi),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Stats',
            style: AppTheme.serif(fontSize: 20, weight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestoreService.getAnimeList(),
        builder: (context, snapshot) {
          // A failed read says so, in Profile's words (stage H5), naming no
          // cause the app can't verify. Before, the spinner never stopped.
          if (snapshot.hasError && !_preHanko) {
            return _hankoColumn(
              context,
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.hankoGutter, 16, AppTheme.hankoGutter, 0),
                child: Text('Couldn\'t load your list just now.',
                    style: AppTheme.hankoSerif(fontSize: 17, height: 1.5)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    color: AppTheme.hankoWashi, strokeWidth: 1.5),
              ),
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
          // Every rating as stored, for the seal register (question 39), as
          // Profile collects them (stage H5, item d).
          final ratings = <double>[];

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
              ratings.add(r);
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

          // Hanko (question 73), from the same numbers.
          if (!_preHanko) {
            return SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 40),
              child: _hankoColumn(
                context,
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.hankoGutter),
                  child: _HankoStats(
                    total: total,
                    watching: watching,
                    completed: completed,
                    planToWatch: planToWatch,
                    dropped: dropped,
                    totalEpisodes: totalEpisodes,
                    watchHours: watchHours,
                    watchDays: watchDays,
                    daysSince: daysSince,
                    monthlyAdded: monthlyAdded,
                    ratings: ratings,
                    topGenres: topGenres,
                    totalGenreEntries:
                        genreCounts.values.fold(0, (a, b) => a + b),
                  ),
                ),
              ),
            );
          }

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
          // The border at full strength: at half it measured 1.10:1 on the
          // card after the switch to sumi, too faint to see; 1.44:1 now.
          getDrawingHorizontalLine: (_) => const FlLine(
            color: AppTheme.border,
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

// ─────────────────────────────────────────────────────────────────────────────
// Stats in Hanko (question 73)
// ─────────────────────────────────────────────────────────────────────────────

/// On a wide window (1024 px and up) the page keeps the phone's column,
/// Responsive.proseMaxWidth plus the gutters, hung on the left under the
/// title as Profile's and Home's are, instead of stretching across the
/// window. Below 1024 it does nothing, so a phone keeps its layout in either
/// orientation (WEB.md §9.2).
Widget _hankoColumn(BuildContext context, Widget child) {
  if (!Responsive.isDesktop(context)) return child;
  return Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
          maxWidth: Responsive.proseMaxWidth + 2 * AppTheme.hankoGutter),
      child: child,
    ),
  );
}

/// Whether a stored rating lands on Hanj's 1–10 scale at its nearest half
/// step, as the seal register places it (Profile's rule, stage H5).
bool _onScale(double rating) {
  final step = (rating * 2).round() / 2;
  return step >= 1 && step <= 10;
}

/// Advanced Stats in Hanko (question 73), built from the numbers the screen
/// already computes: no new reads, no new fields. A record-book page with no
/// cards: your time in one Mincho sentence, then your list by status, what
/// you added by month, your ratings as the seal register (question 39) and
/// your genres, each under a Mincho head. Rows are words with figures in
/// Jost tabular and a washi bar, so no status needs a colour of its own.
/// Coral appears only in the register, where it marks your own verdicts.
class _HankoStats extends StatelessWidget {
  const _HankoStats({
    required this.total,
    required this.watching,
    required this.completed,
    required this.planToWatch,
    required this.dropped,
    required this.totalEpisodes,
    required this.watchHours,
    required this.watchDays,
    required this.daysSince,
    required this.monthlyAdded,
    required this.ratings,
    required this.topGenres,
    required this.totalGenreEntries,
  });

  final int total, watching, completed, planToWatch, dropped;
  final int totalEpisodes, watchHours, watchDays;

  /// Whole days since the newest `lastWatched`; 999 when no entry has one.
  final int daysSince;
  final Map<String, int> monthlyAdded;
  final List<double> ratings;
  final List<MapEntry<String, int>> topGenres;
  final int totalGenreEntries;

  /// Space above each section's head (hanko.html's section rhythm), and
  /// between measured rows.
  static const double _sectionGap = 26;
  static const double _rowGap = 14;

  static final NumberFormat _n = NumberFormat.decimalPattern();

  static String _count(int v, String one, String many) =>
      '${_n.format(v)} ${v == 1 ? one : many}';

  static String _share(double fraction) =>
      '${(fraction * 100).toStringAsFixed(0)}%';

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final quiet = AppTheme.hankoSans(
      fontSize: AppTheme.hankoMetaSize,
      color: AppTheme.hankoStone,
      height: 1.4,
    );

    // Nothing logged: one sentence and what to do, as Profile says it.
    if (total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Nothing logged yet.',
              style: AppTheme.hankoSerif(fontSize: 17, height: 1.5)),
          const SizedBox(height: 6),
          Text('Add a show from Discover or Search, and your stats start\u00A0'
              'here.', style: quiet),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _lede(quiet),
        const SizedBox(height: _sectionGap),
        _list(),
        if (monthlyAdded.isNotEmpty) ...[
          const SizedBox(height: _sectionGap),
          _months(quiet),
        ],
        if (ratings.isNotEmpty) ...[
          const SizedBox(height: _sectionGap),
          _ratings(quiet),
        ],
        if (topGenres.isNotEmpty) ...[
          const SizedBox(height: _sectionGap),
          _genres(quiet),
        ],
      ],
    );
  }

  /// Your time, the page's headline, in the Mincho of Home's lede: whole
  /// days once there is a day of it, else hours, from your episodes at 24
  /// minutes each, the estimate the old tile made, now said in words. Under
  /// it, the episodes behind the estimate and when your list last changed.
  Widget _lede(TextStyle quiet) {
    final time = watchDays > 0
        ? 'About ${_count(watchDays, 'day', 'days')} of anime.'
        : watchHours > 0
            ? 'About ${_count(watchHours, 'hour', 'hours')} of anime.'
            : totalEpisodes > 0
                ? 'Under an hour of anime so far.'
                : 'No episodes logged yet.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(time,
              style: AppTheme.hankoSerif(
                  fontSize: AppTheme.hankoLedeSize, height: 1.3)),
        ),
        if (totalEpisodes > 0) ...[
          const SizedBox(height: 8),
          Text(
              '${_count(totalEpisodes, 'episode', 'episodes')}, counted at '
              '24 minutes each.',
              style: quiet),
        ],
        // lastWatched moves with every add, status change and import, so
        // this says when the list last changed, not when you last watched.
        if (daysSince != 999) ...[
          const SizedBox(height: 2),
          Text(
              daysSince == 0
                  ? 'Last updated today.'
                  : 'Last updated ${_count(daysSince, 'day', 'days')} ago.',
              style: quiet),
        ],
      ],
    );
  }

  /// Your list by status: Status Breakdown's four counts as rows, named as
  /// the status sheet names them, each with its share of your titles and a
  /// bar that long. The words carry the status, so no colour has to.
  Widget _list() {
    final rows = [
      ('Watching', watching),
      ('Completed', completed),
      ('Plan to watch', planToWatch),
      ('Dropped', dropped),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HankoSectionHead('Your list',
            aside: _count(total, 'title', 'titles')),
        for (final (i, (label, n)) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: _rowGap),
          _MeasureRow(
            label: label,
            figure: _n.format(n),
            share: _share(n / total),
            fraction: n / total,
          ),
        ],
      ],
    );
  }

  /// What you added by month: Monthly Activity's chart, the same last six
  /// months that have entries, by `addedAt`. The aside names the span, and
  /// a line under the chart says what puts a title in a month: addedAt is
  /// rewritten whenever a show is given a status (addAnimeToList), so each
  /// title counts once, in the month it was added or last moved.
  Widget _months(TextStyle quiet) {
    final sorted = monthlyAdded.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final shown =
        sorted.length > 6 ? sorted.sublist(sorted.length - 6) : sorted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HankoSectionHead('Added by month', aside: _span(shown)),
        _HankoMonthChart(months: shown),
        const SizedBox(height: 10),
        Text('Each title counts once, in the month it was added or last '
            'given a status.', style: quiet),
      ],
    );
  }

  /// "May to October", or with years when the months aren't all this
  /// year's: "November 2025 to April 2026".
  static String _span(List<MapEntry<String, int>> months) {
    final thisYear = '${DateTime.now().year}-';
    final withYears = !months.every((e) => e.key.startsWith(thisYear));
    String name(String key) {
      final parts = key.split('-');
      final month = _monthNames[int.parse(parts[1]) - 1];
      return withYears ? '$month ${parts[0]}' : month;
    }

    final first = name(months.first.key);
    return months.length == 1 ? first : '$first to ${name(months.last.key)}';
  }

  /// Your ratings as Hanko's seal register (question 39), as Profile draws
  /// it (stage H5, item d), in place of Rating Distribution's five buckets:
  /// each score keeps its place on the 1–10 ruler in half steps, and how
  /// often you gave it is the size of its impression. The caption above it
  /// gives the key numbers in words. Ratings imported on another scale (D20)
  /// can't be placed, so they're left out and counted in a line below.
  Widget _ratings(TextStyle quiet) {
    final offScale = ratings.where((r) => !_onScale(r)).length;
    final drawn = ratings.length - offScale;
    final register = HankoSealRegister.fromRatings(ratings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HankoSectionHead('Your ratings', bottom: drawn > 0 ? 8 : 12),
        if (drawn > 0) ...[
          Text(register.summary, style: quiet),
          const SizedBox(height: 10),
          register,
        ],
        if (offScale > 0) ...[
          if (drawn > 0) const SizedBox(height: 8),
          Text(
            offScale == 1
                ? '1 imported rating is on another scale, so it isn\'t '
                    'drawn\u00A0here.'
                : '$offScale imported ratings are on another scale, so '
                    'they aren\'t drawn\u00A0here.',
            style: quiet,
          ),
        ],
      ],
    );
  }

  /// Your top genres: Genre Affinities' five, each with its titles and its
  /// share of all the genre tags on your list (the old figures), and a bar
  /// that long. A line under them says what the share is of, since most
  /// shows carry several genres.
  Widget _genres(TextStyle quiet) {
    double share(int count) =>
        totalGenreEntries > 0 ? count / totalGenreEntries : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _HankoSectionHead('Genres'),
        for (final (i, e) in topGenres.indexed) ...[
          if (i > 0) const SizedBox(height: _rowGap),
          _MeasureRow(
            label: e.key,
            figure: _count(e.value, 'title', 'titles'),
            share: _share(share(e.value)),
            fraction: share(e.value),
          ),
        ],
        const SizedBox(height: 10),
        Text('Each share is of all the genre tags on your list, and most '
            'shows carry several.', style: quiet),
      ],
    );
  }
}

/// A Hanko section head (hanko.html's .sec-h), as Profile's: Shippori 16 in
/// washi, with an optional aside in Jost 12 stone at the line's end. The
/// aside wraps under the head when the line is too short, so large text
/// never pushes it off the edge.
class _HankoSectionHead extends StatelessWidget {
  const _HankoSectionHead(this.title, {this.aside, this.bottom = 12});

  final String title;
  final String? aside;

  /// Space below the head; 8 where a caption follows it.
  final double bottom;

  @override
  Widget build(BuildContext context) {
    final aside = this.aside;
    final head = Semantics(
      header: true,
      child: Text(title,
          style: AppTheme.hankoSerif(
              fontSize: AppTheme.hankoSectionSize, height: 1.3)),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      // The Wrap takes the full width, or it would shrink to its children
      // and spaceBetween would leave the aside beside the head.
      child: aside == null
          ? head
          : SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                runSpacing: 2,
                children: [
                  head,
                  Text(aside,
                      style: AppTheme.hankoSans(
                        fontSize: AppTheme.hankoLabelSize,
                        color: AppTheme.hankoStone,
                        height: 1.3,
                      )),
                ],
              ),
            ),
    );
  }
}

/// One measured row (question 73): the label in Jost 14 washi, the figure in
/// Jost 500 tabular, its share in stone, and under them a 4 px bar as long
/// as that share, washi on a sumi 3 track. That is hanko.html's bar at twice
/// its weight, since here the bars are the chart. The track sits on the page
/// at 1.18:1, against the N1 fix-up's 1.10 on the old card, so it stays
/// visible. The figures wrap under the label when large text needs it.
class _MeasureRow extends StatelessWidget {
  const _MeasureRow({
    required this.label,
    required this.figure,
    required this.share,
    required this.fraction,
  });

  final String label;
  final String figure;
  final String share;

  /// How much of the bar is filled, 0 to 1.
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final figures = Text.rich(
      TextSpan(children: [
        TextSpan(
          text: figure,
          style: AppTheme.hankoSans(weight: FontWeight.w500, tabular: true),
        ),
        TextSpan(
          text: '  $share',
          style: AppTheme.hankoSans(
            fontSize: AppTheme.hankoMetaSize,
            color: AppTheme.hankoStone,
            tabular: true,
          ),
        ),
      ]),
      maxLines: 1,
      softWrap: false,
    );
    return Semantics(
      label: '$label: $figure, $share',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(label,
                  style: AppTheme.hankoSans(height: 1.3)),
              figures,
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 4,
            child: ColoredBox(
              color: AppTheme.hankoSumi3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: const ColoredBox(color: AppTheme.hankoWashi),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Monthly Activity's chart in Hanko (question 73): the same months and
/// counts as washi bars with 2 px corners and no gradient. Washi is the
/// reel's ink: this is your record, not a verdict, so it isn't coral. Each
/// month is named in three letters, which "J", "J" and "J" were not, with its
/// count under it, so the numbers no longer need a touch. The dashed grid
/// keeps the border's full strength from the N2 fix-up: 1.55:1 on sumi,
/// against 1.44 on the old card. A screen reader hears the months and their
/// counts as one label.
class _HankoMonthChart extends StatelessWidget {
  const _HankoMonthChart({required this.months});

  /// 'yyyy-MM' keys with their counts, oldest first, at most six.
  final List<MapEntry<String, int>> months;

  static const _abbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _month(MapEntry<String, int> e) =>
      _abbr[int.parse(e.key.split('-')[1]) - 1];

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final maxY = months.isEmpty
        ? 1.0
        : (months.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 1)
            .toDouble();
    final monthStyle = AppTheme.hankoSans(
      fontSize: AppTheme.hankoDataSmallSize,
      color: AppTheme.hankoStone,
      height: 1.2,
    );
    final countStyle = AppTheme.hankoSans(
      fontSize: AppTheme.hankoLabelSize,
      weight: FontWeight.w500,
      height: 1.2,
      tabular: true,
    );
    // Room under the bars for the month and its count: 6 px, then two lines
    // that grow with the text size.
    final reserved = 8 +
        scaler.scale(AppTheme.hankoDataSmallSize) * 1.2 +
        scaler.scale(AppTheme.hankoLabelSize) * 1.2;
    return Semantics(
      container: true,
      label: 'Titles added by month: '
          '${months.map((e) => '${_month(e)} ${e.value}').join(', ')}',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 140 + reserved,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY,
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppTheme.hankoSumi3,
                  tooltipBorderRadius:
                      BorderRadius.circular(AppTheme.hankoRadius),
                  tooltipBorder: const BorderSide(color: AppTheme.hankoEdge),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${rod.toY.toInt()}',
                      AppTheme.hankoSans(
                        fontSize: AppTheme.hankoMetaSize,
                        weight: FontWeight.w500,
                        tabular: true,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: reserved,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= months.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_month(months[i]), style: monthStyle),
                            Text('${months[i].value}', style: countStyle),
                          ],
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
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: AppTheme.border,
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              barGroups: [
                for (final (i, e) in months.indexed)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.toDouble(),
                        color: AppTheme.hankoWashi,
                        width: 14,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppTheme.hankoRadius),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
