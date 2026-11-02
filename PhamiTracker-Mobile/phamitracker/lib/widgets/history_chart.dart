import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Score over the last couple of weeks, with the rank goal as a dashed line when it's in reach.
class HistoryChart extends StatelessWidget {
  const HistoryChart({super.key, required this.game, required this.history, this.goal});

  final Game game;
  final List<DayPoint> history;
  final RankGoal? goal;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final (i, d) in history.indexed)
        if (d.score != null) FlSpot(i.toDouble(), d.score!.toDouble()),
    ];
    if (points.length < 2) {
      return const TrackerCard(
        child: SizedBox(
          height: 120,
          child: Center(
            child: Text('Play a few games and your climb shows up here.', style: TextStyle(color: AppColors.textDim)),
          ),
        ),
      );
    }

    final scores = points.map((p) => p.y);
    var minY = scores.reduce(math.min);
    var maxY = scores.reduce(math.max);
    final span = math.max(maxY - minY, 50.0);
    final goalY = goal?.targetScore.toDouble();
    final showGoal = goalY != null && goalY <= maxY + span * 0.6 && goalY >= minY - span * 0.6;
    if (showGoal) {
      minY = math.min(minY, goalY);
      maxY = math.max(maxY, goalY);
    }
    final pad = math.max((maxY - minY) * 0.12, 20.0);
    final dayFormat = DateFormat('d MMM');
    final total = history.fold<int>(0, (sum, d) => sum + d.delta);

    return TrackerCard(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, bottom: 12),
            child: Row(
              children: [
                Text('${history.length} days', style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w700)),
                const Spacer(),
                DeltaChip(total, unit: game.unit),
              ],
            ),
          ),
          SizedBox(
            height: 170,
            child: LineChart(
              LineChartData(
                minY: minY - pad,
                maxY: maxY + pad,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 46,
                      getTitlesWidget: (value, meta) => value == meta.min || value == meta.max
                          ? const SizedBox.shrink()
                          : Text(
                              NumberFormat.compact().format(value),
                              style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                            ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: math.max(1, (history.length / 4).floorToDouble()),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= history.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            dayFormat.format(history[i].day),
                            style: const TextStyle(color: AppColors.textDim, fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    if (showGoal)
                      HorizontalLine(
                        y: goalY,
                        color: AppColors.cyan.withValues(alpha: 0.8),
                        strokeWidth: 1.5,
                        dashArray: [6, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topLeft,
                          style: const TextStyle(color: AppColors.cyan, fontWeight: FontWeight.w800, fontSize: 11),
                          labelResolver: (_) => goal!.label,
                        ),
                      ),
                  ],
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.surfaceHigh,
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          '${dayFormat.format(history[spot.x.toInt()].day)}\n'
                          '${NumberFormat.decimalPattern().format(spot.y)} ${game.unit}  '
                          '(${signed(history[spot.x.toInt()].delta)})',
                          const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: points,
                    isCurved: true,
                    preventCurveOverShooting: true,
                    barWidth: 3.5,
                    gradient: LinearGradient(colors: game.gradient),
                    dotData: FlDotData(
                      checkToShowDot: (spot, _) => spot == points.last,
                      getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                        radius: 5,
                        color: Colors.white,
                        strokeWidth: 3,
                        strokeColor: game.gradient.last,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [game.glow.withValues(alpha: 0.35), game.glow.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
