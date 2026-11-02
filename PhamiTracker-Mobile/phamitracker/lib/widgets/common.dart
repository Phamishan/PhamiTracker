import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// Makes [AppState] available to the widget tree and rebuilds dependents when it changes.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

/// Rounded dark card with a faint border, the base of every dashboard tile.
class TrackerCard extends StatelessWidget {
  const TrackerCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.gradient});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? AppColors.surface : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
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
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Small rounded "+24 RP" style pill coloured by sign.
class DeltaChip extends StatelessWidget {
  const DeltaChip(this.delta, {super.key, this.unit, this.large = false});

  final int delta;
  final String? unit;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.delta(delta);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 9, vertical: large ? 6 : 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(99)),
      child: Text(
        unit == null ? signed(delta) : '${signed(delta)} $unit',
        style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: large ? 15 : 13),
      ),
    );
  }
}

/// Pulsing green dot for "live" / "in match".
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
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.7), blurRadius: 8)],
        ),
      ),
    );
  }
}

String timeAgo(DateTime? time, {DateTime? now}) {
  if (time == null) return 'never';
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
