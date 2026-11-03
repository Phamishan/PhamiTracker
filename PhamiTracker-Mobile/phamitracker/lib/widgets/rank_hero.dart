import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/game.dart';
import '../models/ranks.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

final _number = NumberFormat.decimalPattern();

/// The top card: current rank on the left, rank goal on the right.
class RankHero extends StatelessWidget {
  const RankHero({
    super.key,
    required this.game,
    required this.summary,
    required this.accountName,
    required this.goal,
    required this.onGoalTap,
  });

  final Game game;
  final PlayerSummary? summary;
  final String accountName;
  final RankGoal? goal;
  final VoidCallback onGoalTap;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final tags = [
      if (s?.season?.name != null) [s!.season!.name, if (s.season!.split != null) 'Split ${s.season!.split}'].join(' · '),
      if (s?.rank.peak != null) 'Peak ${s!.rank.peak}',
      if (s?.level != null) 'Lvl ${s!.level}',
      if (s?.rank.ladderPos != null) '#${_number.format(s!.rank.ladderPos)}',
      if ((s?.rank.gamesNeeded ?? 0) > 0) '${s!.rank.gamesNeeded} placements left',
      'Updated ${timeAgo(s?.polledAt)}',
    ];

    return TrackerCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  accountName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDim),
                ),
              ),
              _Status(status: s?.status),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1, color: AppColors.border),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _CurrentRank(game: game, summary: s)),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onGoalTap,
                    child: _Goal(game: game, goal: goal, summary: s),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(tags.join('  ·  ').toUpperCase(), style: AppText.label(color: AppColors.textFaint, size: 10)),
        ],
      ),
    );
  }
}

class _CurrentRank extends StatelessWidget {
  const _CurrentRank({required this.game, required this.summary});

  final Game game;
  final PlayerSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final rankName = (s?.rankLabel ?? s?.rank.name ?? '—').toUpperCase();
    final score = s?.score;
    final today = s?.today ?? const TodayStats();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardLabel('Current rank', icon: Icons.shield_rounded),
        const SizedBox(height: 14),
        Row(
          children: [
            RankBadge(name: s?.rank.name ?? rankName, imageUrl: s?.rank.image),
            const SizedBox(width: 10),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(rankName, style: AppText.display(26)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          score == null
              ? '—'
              : game == Game.valorant
                  ? '${s!.rank.rr ?? 0} RR'
                  : '${_number.format(score)} RP',
          style: AppText.display(30, weight: FontWeight.w700),
        ),
        const Spacer(),
        const SizedBox(height: 16),
        Text('TODAY', style: AppText.label()),
        const SizedBox(height: 4),
        Text(
          '${signed(today.delta)} ${game.unit} · ${today.matches} ${today.matches == 1 ? 'game' : 'games'}',
          style: AppText.display(19, color: AppColors.delta(today.delta), weight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _Goal extends StatelessWidget {
  const _Goal({required this.game, required this.goal, required this.summary});

  final Game game;
  final RankGoal? goal;
  final PlayerSummary? summary;

  @override
  Widget build(BuildContext context) {
    final goal = this.goal;
    final score = summary?.score;
    if (goal == null) {
      final suggestion = score == null ? null : nextRank(game, score);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CardLabel('Rank goal', icon: Icons.gps_fixed_rounded),
          const SizedBox(height: 14),
          Text('SET A GOAL', style: AppText.display(26, color: AppColors.goalSoft)),
          const SizedBox(height: 10),
          Text(
            suggestion == null ? 'Pick the rank you\'re grinding for.' : 'Next up: ${suggestion.label}',
            style: const TextStyle(color: AppColors.textDim),
          ),
          const Spacer(),
          const Icon(Icons.add_circle_outline_rounded, color: AppColors.goal),
        ],
      );
    }

    final current = score ?? goal.startScore;
    final remaining = goal.remaining(current);
    final pace = summary?.pacePerDay;
    final days = pace != null && pace > 0 && remaining > 0 ? (remaining / pace).ceil() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CardLabel('Rank goal', icon: Icons.gps_fixed_rounded),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(goal.label.toUpperCase(), style: AppText.display(26, color: AppColors.goalSoft)),
        ),
        const SizedBox(height: 12),
        if (remaining == 0)
          Text('REACHED', style: AppText.display(30, color: AppColors.gain, weight: FontWeight.w700))
        else
          Text.rich(
            TextSpan(children: [
              TextSpan(text: _number.format(remaining), style: AppText.display(30, weight: FontWeight.w700)),
              TextSpan(text: '  ${game.unit} to go', style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const Spacer(),
        const SizedBox(height: 16),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '${_number.format(current)} / ${_number.format(goal.targetScore)}',
            style: AppText.mono(size: 12),
          ),
        ),
        const SizedBox(height: 6),
        ProgressBar(value: goal.progress(current)),
        const SizedBox(height: 6),
        Text(
          summary?.season?.goalPace(remaining, game.unit) ??
          switch ((pace, days)) {
            (final p?, final d?) => '~$p ${game.unit}/day · $d ${d == 1 ? 'day' : 'days'}',
            (final p?, _) when p <= 0 => 'Pace: ${signed(p)} ${game.unit}/day',
            _ => '${(goal.progress(current) * 100).round()}% of the way',
          },
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
        ),
      ],
    );
  }
}

/// Rank art from the API, or a ring in the rank's colour with its initial.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.name, required this.imageUrl, this.size = 44});

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = rankColor(name);
    final fallback = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.background,
        border: Border.all(color: color.withValues(alpha: 0.8), width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: AppText.display(size * 0.5, color: color),
      ),
    );
    return SizedBox.square(
      dimension: size,
      child: imageUrl == null
          ? fallback
          : Image.network(imageUrl!, fit: BoxFit.contain, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.status});

  final PlayerStatus? status;

  @override
  Widget build(BuildContext context) {
    final (text, live) = switch (status) {
      PlayerStatus(inGame: true, :final legend) => (legend == null ? 'In match' : 'In match · $legend', true),
      PlayerStatus(online: true, :final text) => (text ?? 'Online', true),
      _ => ('Tracking', false),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiveDot(color: live ? AppColors.live : AppColors.textFaint, size: 7),
        const SizedBox(width: 7),
        Text(text.toUpperCase(), style: AppText.label(color: live ? AppColors.live : AppColors.textFaint, size: 10)),
      ],
    );
  }
}
