import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/game.dart';
import '../models/ranks.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

final _number = NumberFormat.decimalPattern();

/// The profile card at the top: a big rank badge, the rank and score, and today at a glance.
/// Laid out like a PhamiJam artist page: centred art, spaced-caps kicker, big name.
class RankHero extends StatelessWidget {
  const RankHero({super.key, required this.game, required this.summary, required this.accountName});

  final Game game;
  final PlayerSummary? summary;
  final String accountName;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final rankName = (s?.rankLabel ?? s?.rank.name ?? '—').toUpperCase();
    final today = s?.today ?? const TodayStats();
    final tags = [
      if (s?.season?.name != null) [s!.season!.name, if (s.season!.split != null) 'Split ${s.season!.split}'].join(' · '),
      if (s?.rank.peak != null) 'Peak ${s!.rank.peak}',
      ?predatorTag(s),
      if ((s?.rank.gamesNeeded ?? 0) > 0) '${s!.rank.gamesNeeded} placements left',
      'Updated ${timeAgo(s?.polledAt)}',
    ];

    return TrackerCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  accountName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textDim),
                ),
              ),
              _Status(status: s?.status),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: AppColors.surfaceLow, shape: BoxShape.circle),
            child: RankBadge(name: s?.rank.name ?? rankName, imageUrl: s?.rank.image, size: 84),
          ),
          const SizedBox(height: 14),
          Text('CURRENT RANK', style: AppText.label()),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(rankName, style: AppText.display(30))),
          const SizedBox(height: 4),
          Text(
            s?.score == null
                ? '—'
                : game == Game.valorant
                    ? '${s!.rank.rr ?? 0} RR  ·  ${_number.format(s.score)} elo'
                    : '${_number.format(s!.score)} RP',
            style: AppText.mono(size: 15),
          ),
          if (s?.score case final score? when s!.rank.gamesNeeded <= 0)
            if (nextRank(game, score) case final next?) ...[
              const SizedBox(height: 16),
              NextRankBar(game: game, score: score, next: next),
            ],
          const SizedBox(height: 18),
          Row(
            children: [
              _Stat(label: 'Today', value: '${signed(today.delta)} ${game.unit}', color: AppColors.delta(today.delta)),
              _Stat(label: 'Games', value: '${today.matches}'),
              _Stat(
                label: 'W / L',
                valueSpan: TextSpan(children: [
                  TextSpan(text: '${today.wins}', style: const TextStyle(color: AppColors.gain)),
                  const TextSpan(text: ' / ', style: TextStyle(color: AppColors.textFaint)),
                  TextSpan(text: '${today.losses}', style: const TextStyle(color: AppColors.loss)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            tags.join('  ·  ').toUpperCase(),
            textAlign: TextAlign.center,
            style: AppText.label(color: AppColors.textFaint, size: 10),
          ),
        ],
      ),
    );
  }
}

/// How far through this division: a bar from its floor to the next one, like PhamiBot's
/// "▰▰▰▱▱ 7,320/7,750 RP".
class NextRankBar extends StatelessWidget {
  const NextRankBar({super.key, required this.game, required this.score, required this.next});

  final Game game;
  final int score;
  final RankStep next;

  @override
  Widget build(BuildContext context) {
    final floor = rankAt(game, score).minScore;
    final span = next.minScore - floor;
    final progress = span <= 0 ? 0.0 : (score - floor) / span;
    // VALORANT shows RR within the division (0-100); Apex shows the RP itself.
    final have = game == Game.apex ? _number.format(score) : '${score - floor}';
    final need = game == Game.apex ? _number.format(next.minScore) : '$span';
    final unit = game == Game.apex ? 'RP' : 'RR';
    return Column(
      children: [
        ProgressBar(value: progress, color: rankColor(next.label), height: 6),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('$have / $need $unit', style: AppText.mono(size: 11, color: AppColors.textDim)),
            const Spacer(),
            Text(
              '${_number.format(next.minScore - score)} to ${next.label}'.toUpperCase(),
              style: AppText.label(size: 9, color: AppColors.textFaint),
            ),
          ],
        ),
      ],
    );
  }
}

/// "1,920 RP to Predator" for Masters (and "Predator cutoff 24,078" once they're above it).
String? predatorTag(PlayerSummary? s) {
  final cutoff = s?.predator?.cutoff;
  final score = s?.score;
  if (s == null || cutoff == null || score == null || s.game != Game.apex) return null;
  if (score < apexLadder.last.minScore) return null;
  return score < cutoff ? '${_number.format(cutoff - score)} RP to Predator' : 'Predator cutoff ${_number.format(cutoff)}';
}

/// One of the three little stat blocks under the rank.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, this.value, this.valueSpan, this.color = AppColors.text});

  final String label;
  final String? value;
  final TextSpan? valueSpan;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: AppColors.surfaceLow, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(valueSpan ?? TextSpan(text: value), style: AppText.display(18, color: color)),
            ),
            const SizedBox(height: 3),
            Text(label.toUpperCase(), style: AppText.label(size: 9, color: AppColors.textFaint)),
          ],
        ),
      ),
    );
  }
}

/// The rank goal: target rank art + name in gold, what's left, a gold progress bar and the pace.
class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.game, required this.goal, required this.summary, required this.onTap});

  final Game game;
  final RankGoal? goal;
  final PlayerSummary? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final goal = this.goal;
    final score = summary?.score;
    if (goal == null) {
      final suggestion = score == null ? null : nextRank(game, score);
      return TrackerCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: AppColors.goal.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: const Icon(Icons.flag_rounded, color: AppColors.goal),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SET A RANK GOAL', style: AppText.display(18, color: AppColors.goalSoft)),
                  const SizedBox(height: 4),
                  Text(
                    suggestion == null ? 'Pick the rank you\'re grinding for.' : 'Next up: ${suggestion.label}',
                    style: const TextStyle(color: AppColors.textDim),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
          ],
        ),
      );
    }

    final current = score ?? goal.startScore;
    final remaining = goal.remaining(current);
    final pace = summary?.pacePerDay;
    final days = pace != null && pace > 0 && remaining > 0 ? (remaining / pace).ceil() : null;
    final paceText = summary?.season?.goalPace(remaining, game.unit) ??
        switch ((pace, days)) {
          (final p?, final d?) => '~$p ${game.unit}/day · $d ${d == 1 ? 'day' : 'days'}',
          (final p?, _) when p <= 0 => 'Pace: ${signed(p)} ${game.unit}/day',
          _ => '${(goal.progress(current) * 100).round()}% of the way',
        };

    return TrackerCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RankBadge(name: goal.label, imageUrl: goalIconUrl(game, goal.targetScore, label: goal.label), size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RANK GOAL', style: AppText.label()),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(goal.label.toUpperCase(), style: AppText.display(22, color: AppColors.goalSoft)),
                    ),
                  ],
                ),
              ),
              if (remaining == 0)
                Text('REACHED', style: AppText.display(18, color: AppColors.gain))
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_number.format(remaining), style: AppText.display(24)),
                    Text('${game.unit} TO GO', style: AppText.label(size: 9, color: AppColors.textFaint)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          ProgressBar(value: goal.progress(current), color: AppColors.goal, height: 10),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  paceText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_number.format(current)} / ${_number.format(goal.targetScore)}',
                style: AppText.mono(size: 12, color: AppColors.textFaint),
              ),
            ],
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.surfaceLow, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiveDot(color: live ? AppColors.live : AppColors.textFaint, size: 7),
          const SizedBox(width: 7),
          Text(text.toUpperCase(), style: AppText.label(color: live ? AppColors.live : AppColors.textFaint, size: 10)),
        ],
      ),
    );
  }
}
