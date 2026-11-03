import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// `TODAY · 6 GAMES`, a big net number and a sparkline of the session.
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
          CardLabel('Today · ${today.matches} ${today.matches == 1 ? 'game' : 'games'}', color: AppColors.textFaint),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: signed(today.delta), style: AppText.display(54, color: color, weight: FontWeight.w700)),
                TextSpan(text: ' ${game.unit}', style: AppText.display(18, color: AppColors.textDim, weight: FontWeight.w700)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            today.best == null ? 'No games yet' : 'Net ${game.unit} · best ${signed(today.best!)}',
            style: const TextStyle(color: AppColors.textDim, fontSize: 13.5),
          ),
          const Spacer(),
          const SizedBox(height: 14),
          if (today.series.isEmpty)
            const SizedBox(height: 54)
          else
            Sparkline(values: today.series, color: game.glow),
        ],
      ),
    );
  }
}

/// Win-rate dial with the day's W/L underneath.
class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.today});

  final TodayStats today;

  @override
  Widget build(BuildContext context) {
    final played = today.wins + today.losses;
    final rate = played == 0 ? 0.0 : today.wins / played;
    return TrackerCard(
      child: Column(
        children: [
          const CardLabel('Win rate', color: AppColors.textFaint),
          const SizedBox(height: 10),
          GaugeRing(
            progress: rate,
            color: AppColors.gain,
            size: 128,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(played == 0 ? '—' : '${(rate * 100).round()}%', style: AppText.display(32)),
                Text('TODAY', style: AppText.label(size: 9, color: AppColors.textFaint)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${today.wins}W', style: AppText.display(20, color: AppColors.gain, weight: FontWeight.w700)),
              const SizedBox(width: 12),
              Text('${today.losses}L', style: AppText.display(20, color: AppColors.loss, weight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}
