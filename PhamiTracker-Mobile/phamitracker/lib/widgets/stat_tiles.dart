import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Today's session as a running total, game by game, with the best and worst game.
class TodayTile extends StatelessWidget {
  const TodayTile({super.key, required this.game, required this.today});

  final Game game;
  final TodayStats today;

  @override
  Widget build(BuildContext context) {
    return TrackerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: CardLabel("Today's session")),
              if (today.best != null) ...[
                Text('BEST ', style: AppText.label(size: 10, color: AppColors.textFaint)),
                Text(signed(today.best!), style: AppText.display(15, color: AppColors.delta(today.best!))),
                const SizedBox(width: 12),
                Text('WORST ', style: AppText.label(size: 10, color: AppColors.textFaint)),
                Text(signed(today.worst!), style: AppText.display(15, color: AppColors.delta(today.worst!))),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (today.series.isEmpty)
            const SizedBox(
              height: 64,
              child: Center(child: Text('No games today yet.', style: TextStyle(color: AppColors.textDim))),
            )
          else
            Sparkline(values: today.series, color: AppColors.delta(today.delta), height: 64),
        ],
      ),
    );
  }
}
