import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// VALORANT K/D, KDA, headshot % and ACS over the recent matches that have stats.
/// (Apex doesn't report kills or deaths per match, so it has no card.)
class PerformanceCard extends StatelessWidget {
  const PerformanceCard({super.key, required this.game, required this.matches});

  final Game game;
  final List<MatchEntry> matches;

  @override
  Widget build(BuildContext context) {
    final p = Performance.from(matches);
    if (p == null) return const SizedBox.shrink();
    String fixed(double? v) => v == null ? '—' : v.toStringAsFixed(2);
    final stats = [
      ('K/D', fixed(p.kd), _kdColor(p.kd)),
      ('KDA', fixed(p.kda), null),
      ('HS%', p.headshotPct == null ? '—' : '${p.headshotPct!.round()}%', null),
      ('ACS', p.acs == null ? '—' : '${p.acs!.round()}', null),
    ];

    return TrackerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel('Last ${p.games} ${p.games == 1 ? 'game' : 'games'}', icon: Icons.insights_rounded),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final (label, value, color) in stats)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(value, style: AppText.display(22, color: color ?? AppColors.text)),
                      ),
                      const SizedBox(height: 4),
                      Text(label.toUpperCase(), style: AppText.label(color: AppColors.textFaint, size: 10)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color? _kdColor(double? kd) => kd == null ? null : AppColors.delta(kd - 1);
}
