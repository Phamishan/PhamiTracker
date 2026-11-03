import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Today's net points, W/L and best game, with a sparkline of the session.
class TodayTile extends StatelessWidget {
  const TodayTile({super.key, required this.game, required this.today});

  final Game game;
  final TodayStats today;

  @override
  Widget build(BuildContext context) {
    return TrackerCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardLabel('Today · ${today.matches} ${today.matches == 1 ? 'game' : 'games'}'),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: signed(today.delta), style: AppText.display(40, color: AppColors.delta(today.delta))),
                    TextSpan(text: ' ${game.unit}', style: AppText.label(size: 16)),
                  ]),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('${today.wins}W', style: AppText.label(color: AppColors.gain, size: 14)),
                    const SizedBox(width: 8),
                    Text('${today.losses}L', style: AppText.label(color: AppColors.loss, size: 14)),
                    if (today.best != null) ...[
                      const SizedBox(width: 12),
                      Text('Best ${signed(today.best!)}', style: AppText.label(size: 14)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (today.series.isNotEmpty) ...[
            const SizedBox(width: 16),
            SizedBox(width: 130, child: Sparkline(values: today.series, color: game.glow, height: 64)),
          ],
        ],
      ),
    );
  }
}
