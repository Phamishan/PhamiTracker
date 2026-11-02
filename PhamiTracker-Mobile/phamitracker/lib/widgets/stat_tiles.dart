import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

final _number = NumberFormat.decimalPattern();

/// "+184 RP today" with the session's match count, W/L and best game.
class TodayTile extends StatelessWidget {
  const TodayTile({super.key, required this.game, required this.today});

  final Game game;
  final TodayStats today;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.delta(today.delta);
    return TrackerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TileLabel(icon: Icons.bolt_rounded, text: 'Today', color: AppColors.orange),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: signed(today.delta),
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: color, height: 1),
                ),
                TextSpan(
                  text: ' ${game.unit}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color.withValues(alpha: 0.7)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          _MiniRow('Matches', '${today.matches}'),
          _MiniRow('W / L', '${today.wins} / ${today.losses}'),
          _MiniRow('Best', today.best == null ? '—' : signed(today.best!), color: today.best == null ? null : AppColors.delta(today.best!)),
        ],
      ),
    );
  }
}

/// Progress ring towards the player's rank goal. Tapping opens the goal picker.
class GoalTile extends StatelessWidget {
  const GoalTile({super.key, required this.game, required this.goal, required this.score, required this.onTap});

  final Game game;
  final RankGoal? goal;
  final int? score;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final goal = this.goal;
    final score = this.score;
    final progress = goal != null && score != null ? goal.progress(score) : 0.0;
    const color = AppColors.purple;

    return GestureDetector(
      onTap: onTap,
      child: TrackerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TileLabel(icon: Icons.flag_rounded, text: 'Rank goal', color: AppColors.purple),
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                width: 108,
                height: 108,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => CustomPaint(
                    painter: GoalRingPainter(progress: value, colors: const [AppColors.orange, AppColors.purple]),
                    child: Center(
                      child: goal == null
                          ? const Icon(Icons.add_rounded, size: 36, color: AppColors.textDim)
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${(value * 100).round()}%',
                                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                                ),
                                Text(
                                  goal.label,
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                switch ((goal, score)) {
                  (null, _) => 'Set a goal',
                  (final g?, final s?) when s >= g.targetScore => 'Goal reached! 🎉',
                  (final g?, final s?) => '${_number.format(g.remaining(s))} ${game.unit} to go',
                  _ => '…',
                },
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDim, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GoalRingPainter extends CustomPainter {
  GoalRingPainter({required this.progress, required this.colors});

  final double progress;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 11.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(
      arcRect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.surfaceHigh,
    );
    if (progress <= 0) return;
    final sweep = math.pi * 2 * progress;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [...colors, colors.first],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(arcRect, -math.pi / 2, sweep, false, paint);
  }

  @override
  bool shouldRepaint(GoalRingPainter old) => old.progress != progress || old.colors != colors;
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textDim)),
      ],
    );
  }
}

class _MiniRow extends StatelessWidget {
  const _MiniRow(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color)),
        ],
      ),
    );
  }
}
