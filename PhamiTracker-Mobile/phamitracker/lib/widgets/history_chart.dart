import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Score over the chosen range (All / 3M / 1M / 14D / 7D), with the rank goal as a dashed line
/// when it's in reach.
class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.game,
    required this.history,
    required this.range,
    required this.onRange,
    this.goal,
  });

  final Game game;

  /// Null while the range is loading.
  final List<DayPoint>? history;
  final ClimbRange range;
  final ValueChanged<ClimbRange> onRange;
  final RankGoal? goal;

  @override
  Widget build(BuildContext context) {
    final history = this.history;
    final total = history?.fold<int>(0, (sum, d) => sum + d.delta) ?? 0;
    return TrackerCard(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 14),
            child: Row(
              children: [
                Expanded(child: _RangeToggle(range: range, onChanged: onRange)),
                const SizedBox(width: 10),
                if (history != null) DeltaChip(total, unit: game.unit),
              ],
            ),
          ),
          SizedBox(
            height: 180,
            child: switch (history) {
              null => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              final h when h.where((d) => d.score != null).length < 2 => const Center(
                  child: Text('Play a few games and your climb shows up here.', style: TextStyle(color: AppColors.textDim)),
                ),
              final h => _Chart(game: game, history: h, goal: goal, range: range),
            },
          ),
        ],
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.range, required this.onChanged});

  final ClimbRange range;
  final ValueChanged<ClimbRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          for (final r in ClimbRange.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r == range ? AppColors.surfaceHigh : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    r.label,
                    style: AppText.label(size: 12, color: r == range ? AppColors.text : AppColors.textFaint),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.game, required this.history, required this.goal, required this.range});

  final Game game;
  final List<DayPoint> history;
  final RankGoal? goal;
  final ClimbRange range;

  @override
  Widget build(BuildContext context) {
    final points = [
      for (final (i, d) in history.indexed)
        if (d.score != null) FlSpot(i.toDouble(), d.score!.toDouble()),
    ];
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
    // Long ranges label by month, short ones by day.
    final dayFormat = history.length > 120 ? DateFormat('MMM yy') : DateFormat('d MMM');

    return LineChart(
      duration: const Duration(milliseconds: 250),
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
              reservedSize: 44,
              getTitlesWidget: (value, meta) => value == meta.min || value == meta.max
                  ? const SizedBox.shrink()
                  : Text(NumberFormat.compact().format(value), style: AppText.mono(size: 11, color: AppColors.textFaint)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: math.max(1, (history.length / 4).floorToDouble()),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= history.length) return const SizedBox.shrink();
                // fl_chart always labels the last point too; skip it when it would crowd the previous label.
                if (value == meta.max && i % meta.appliedInterval.round() != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dayFormat.format(history[i].day), style: AppText.mono(size: 11, color: AppColors.textFaint)),
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
                color: AppColors.goal.withValues(alpha: 0.8),
                strokeWidth: 1.5,
                dashArray: [6, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topLeft,
                  style: AppText.label(color: AppColors.goal, size: 11),
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
                  '${DateFormat('d MMM yyyy').format(history[spot.x.toInt()].day)}\n'
                  '${NumberFormat.decimalPattern().format(spot.y)} ${game.unit}  '
                  '(${signed(history[spot.x.toInt()].delta)})',
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: points.length < 60,
            preventCurveOverShooting: true,
            barWidth: 2.5,
            color: game.glow,
            dotData: FlDotData(
              checkToShowDot: (spot, _) => spot == points.last,
              getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 4, color: game.glow, strokeWidth: 0),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [game.glow.withValues(alpha: 0.18), game.glow.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
