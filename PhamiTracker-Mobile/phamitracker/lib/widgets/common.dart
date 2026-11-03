import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// Makes [AppState] available to the widget tree and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Graphite card (top-lit gradient, hairline border), the base of every dashboard tile.
class TrackerCard extends StatelessWidget {
  const TrackerCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
    return onTap == null ? card : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: card);
  }
}

/// Small dim label, optionally with a leading icon: `◎ Rank goal`.
class CardLabel extends StatelessWidget {
  const CardLabel(this.text, {super.key, this.icon, this.color = AppColors.textDim, this.trailing});

  final String text;
  final IconData? icon;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(text, style: AppText.label(color: color), overflow: TextOverflow.ellipsis)),
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: CardLabel(title, color: AppColors.text, trailing: trailing),
    );
  }
}

/// `+24 RP` in green, `-35 RP` in red.
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.delta, {super.key, this.unit, this.large = false});

  final int delta;
  final String? unit;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.delta(delta);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 9, vertical: large ? 5 : 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(
        unit == null ? signed(delta) : '${signed(delta)} $unit',
        style: AppText.display(large ? 18 : 16, color: color, weight: FontWeight.w700),
      ),
    );
  }
}

/// Pulsing dot for "live" / "now playing".
class LiveDot extends StatefulWidget {
  const LiveDot({super.key, this.color = AppColors.live, this.size = 8});

  final Color color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_controller),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Thin progress bar on a dark track (goal progress, map rotation time).
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color = AppColors.goal, this.height = 8});

  final double value;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: AppColors.surfaceHigh,
          color: color,
        ),
      ),
    );
  }
}

/// Little line chart with a soft fill and a dot on the latest value.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color = AppColors.accent, this.height = 54});

  final List<num> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SparklinePainter(values, color)));
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter(this.values, this.color);

  final List<num> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // A single game still gets a line: start it from zero.
    final points = [if (values.length == 1) 0.0, for (final v in values) v.toDouble()];
    if (points.length < 2) return;
    final lo = points.reduce(math.min);
    final hi = points.reduce(math.max);
    final span = (hi - lo).abs() < 1 ? 1.0 : hi - lo;
    const dot = 5.0;
    final w = size.width - dot;
    final h = size.height - dot * 2;
    Offset at(int i) => Offset(w * i / (points.length - 1), dot + h - (points[i] - lo) / span * h);

    final line = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      line.lineTo(at(i).dx, at(i).dy);
    }
    final fill = Path.from(line)
      ..lineTo(at(points.length - 1).dx, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    canvas.drawCircle(at(points.length - 1), dot, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values || old.color != color;
}

String timeAgo(DateTime? time, {DateTime? now}) {
  if (time == null) return 'never';
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
