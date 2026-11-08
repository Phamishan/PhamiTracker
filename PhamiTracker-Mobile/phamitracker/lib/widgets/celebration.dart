import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'rank_hero.dart';

/// Rank up / goal reached: confetti over the new rank's art. Tap anywhere (or the button) to close.
Future<void> showCelebration(BuildContext context, Celebration celebration) {
  HapticFeedback.heavyImpact();
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)), child: child),
    ),
    pageBuilder: (context, _, _) => _CelebrationView(celebration: celebration),
  );
}

class _CelebrationView extends StatefulWidget {
  const _CelebrationView({required this.celebration});

  final Celebration celebration;

  @override
  State<_CelebrationView> createState() => _CelebrationViewState();
}

class _CelebrationViewState extends State<_CelebrationView> with SingleTickerProviderStateMixin {
  late final AnimationController _confetti = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))..forward();
  late final List<_Piece> _pieces = _Piece.burst(widget.celebration.game.glow);

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.celebration;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _confetti,
              builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_pieces, _confetti.value)),
            ),
          ),
          Center(
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c.game.glow.withValues(alpha: 0.45), blurRadius: 60, spreadRadius: 6)],
                    ),
                    child: RankBadge(name: c.rank, imageUrl: c.image, size: 120),
                  ),
                  const SizedBox(height: 24),
                  Text(c.title.toUpperCase(), style: AppText.label(color: AppColors.goalSoft, size: 13)),
                  const SizedBox(height: 8),
                  Text(c.rank.toUpperCase(), textAlign: TextAlign.center, style: AppText.display(34)),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(backgroundColor: c.game.glow, padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14)),
                    child: Text("LET'S GO", style: AppText.label(color: Colors.white, size: 13)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One bit of confetti: where it starts, how it falls and spins.
class _Piece {
  _Piece(this.x, this.delay, this.speed, this.drift, this.spin, this.size, this.color);

  final double x;
  final double delay;
  final double speed;
  final double drift;
  final double spin;
  final double size;
  final Color color;

  static List<_Piece> burst(Color gameColor, {int count = 110, int seed = 7}) {
    final rng = math.Random(seed);
    final colors = [gameColor, AppColors.goal, AppColors.goalSoft, AppColors.gain, Colors.white];
    return [
      for (var i = 0; i < count; i++)
        _Piece(
          rng.nextDouble(),
          rng.nextDouble() * 0.35,
          0.7 + rng.nextDouble() * 0.6,
          (rng.nextDouble() - 0.5) * 0.25,
          (rng.nextDouble() - 0.5) * 14,
          5 + rng.nextDouble() * 6,
          colors[rng.nextInt(colors.length)],
        ),
    ];
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in pieces) {
      final life = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (life <= 0) continue;
      final y = -20 + life * p.speed * (size.height + 60);
      final x = p.x * size.width + math.sin(life * math.pi * 3 + p.spin) * 18 + p.drift * size.width * life;
      paint.color = p.color.withValues(alpha: life > 0.85 ? (1 - life) / 0.15 : 1);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(life * p.spin);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5), const Radius.circular(1.5)),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
