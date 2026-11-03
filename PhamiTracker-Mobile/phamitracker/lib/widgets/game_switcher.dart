import 'package:flutter/material.dart';

import '../models/game.dart';
import '../theme/app_theme.dart';

/// Segmented control for switching games. The selected segment lifts onto a lighter surface.
class GameSwitcher extends StatelessWidget {
  const GameSwitcher({super.key, required this.selected, required this.onChanged, this.linked = const {}});

  final Game selected;
  final ValueChanged<Game> onChanged;

  /// Games with a linked account get a small dot.
  final Set<Game> linked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final game in Game.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(game),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  height: 40,
                  decoration: BoxDecoration(
                    color: game == selected ? AppColors.surfaceHigh : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: game == selected ? AppColors.border : Colors.transparent),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(game.icon, size: 16, color: game == selected ? game.glow : AppColors.textFaint),
                      const SizedBox(width: 8),
                      Text(
                        game.shortTitle,
                        style: AppText.label(color: game == selected ? AppColors.text : AppColors.textFaint),
                      ),
                      if (linked.contains(game) && game != selected) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(color: AppColors.gain, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
