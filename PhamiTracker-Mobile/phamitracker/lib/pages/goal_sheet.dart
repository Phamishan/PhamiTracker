import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/game.dart';
import '../models/ranks.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Pick the rank to grind towards (or, for Apex, a custom RP number).
Future<void> showGoalSheet(BuildContext context, Game game) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _GoalSheet(game: game),
  );
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({required this.game});

  final Game game;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  Future<void> _choose(String label, int target) async {
    await AppScope.of(context).setGoal(widget.game, label: label, targetScore: target);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final game = widget.game;
    final score = state.summaries[game]?.score ?? 0;
    final current = state.goals[game];
    final steps = ladderFor(game).where((r) => r.minScore > score).toList();
    final number = NumberFormat.decimalPattern();
    final predator = game == Game.apex ? state.summaries[game]?.predator : null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
        children: [
          const Text('Rank goal', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            'You\'re at ${number.format(score)} ${game == Game.apex ? 'RP' : 'elo'}. Progress counts from here.',
            style: const TextStyle(color: AppColors.textDim),
          ),
          if (game == Game.apex) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _custom,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'Custom RP target',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_rounded),
                  onPressed: () {
                    final value = int.tryParse(_custom.text);
                    if (value != null && value > score) _choose('${NumberFormat.compact().format(value)} RP', value);
                  },
                ),
              ),
            ),
          ],
          const SectionTitle('Ranks'),
          if (predator != null && predator.cutoff > score)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RankOption(
                step: RankStep(apexPredatorGoal, predator.cutoff),
                remaining: predator.cutoff - score,
                unit: 'RP',
                selected: current?.label == apexPredatorGoal,
                onTap: () => _choose(apexPredatorGoal, predator.cutoff),
                note: 'Top 750 · follows the live cutoff',
              ),
            ),
          if (steps.isEmpty)
            const Text('You\'re at the top of the ladder. 👑', style: TextStyle(fontWeight: FontWeight.w700)),
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RankOption(
                step: step,
                remaining: step.minScore - score,
                unit: game == Game.apex ? 'RP' : 'RR',
                selected: current?.targetScore == step.minScore,
                onTap: () => _choose(step.label, step.minScore),
              ),
            ),
          if (current != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                state.clearGoal(game);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.close_rounded),
              label: const Text('Remove goal'),
              style: TextButton.styleFrom(foregroundColor: AppColors.loss),
            ),
          ],
        ],
      ),
    );
  }
}

class _RankOption extends StatelessWidget {
  const _RankOption({
    required this.step,
    required this.remaining,
    required this.unit,
    required this.selected,
    required this.onTap,
    this.note,
  });

  final RankStep step;
  final int remaining;
  final String unit;
  final bool selected;
  final VoidCallback onTap;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final color = rankColor(step.label);
    return Material(
      color: selected ? color.withValues(alpha: 0.16) : AppColors.surfaceHigh,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 10)],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    if (note != null) Text(note!, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
              ),
              Text(
                '+${NumberFormat.decimalPattern().format(remaining)} $unit',
                style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w700),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, color: color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
