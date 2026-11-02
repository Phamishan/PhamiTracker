import 'package:flutter/material.dart';

import '../models/game.dart';
import '../theme/app_theme.dart';

/// Segmented pill for switching games. The selected game lights up in its own gradient.
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
        borderRadius: BorderRadius.circular(99),
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
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: game == selected ? game.linearGradient : null,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: game == selected
                        ? [BoxShadow(color: game.glow.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6))]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(game.icon, size: 18, color: game == selected ? Colors.white : AppColors.textDim),
                      const SizedBox(width: 6),
                      Text(
                        game.shortTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                          fontSize: 13,
                          color: game == selected ? Colors.white : AppColors.textDim,
                        ),
                      ),
                      if (linked.contains(game) && game != selected) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(color: game.glow, shape: BoxShape.circle),
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
