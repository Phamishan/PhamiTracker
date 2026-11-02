import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Every rank change the worker picked up, newest first.
class MatchList extends StatelessWidget {
  const MatchList({super.key, required this.game, required this.matches});

  final Game game;
  final List<MatchEntry> matches;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return TrackerCard(
        child: Row(
          children: [
            Icon(Icons.sports_esports_rounded, color: game.glow),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                "No ranked games yet. They'll show up here a minute after each match, even with the app closed.",
                style: TextStyle(color: AppColors.textDim, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }
    return TrackerCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (i, match) in matches.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 72, color: AppColors.border),
            _MatchTile(game: game, match: match),
          ],
        ],
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.game, required this.match});

  final Game game;
  final MatchEntry match;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.delta(match.delta);
    final title = match.isAdjustment
        ? 'Rank adjustment'
        : [match.character, match.map].nonNulls.join(' · ').ifEmpty('Ranked match');
    final subtitle = [
      _when(match.time),
      if (match.kills != null) '${match.kills}/${match.deaths}/${match.assists}',
      if (match.roundsWon != null) '${match.roundsWon}–${match.roundsLost}',
      ?match.rank,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.08)]),
            ),
            child: Icon(
              match.isAdjustment
                  ? Icons.tune_rounded
                  : match.delta >= 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          DeltaChip(match.delta, unit: game.unit),
        ],
      ),
    );
  }

  static String _when(DateTime time) {
    final now = DateTime.now();
    final sameDay = time.year == now.year && time.month == now.month && time.day == now.day;
    return sameDay ? DateFormat.Hm().format(time) : DateFormat('d MMM, HH:mm').format(time);
  }
}

/// RP/RR won or lost per map, the "which map am I bad at" view.
class MapStatsCard extends StatelessWidget {
  const MapStatsCard({super.key, required this.game, required this.maps});

  final Game game;
  final List<MapStat> maps;

  @override
  Widget build(BuildContext context) {
    final maxAbs = maps.fold<int>(1, (m, s) => s.delta.abs() > m ? s.delta.abs() : m);
    return TrackerCard(
      child: Column(
        children: [
          for (final (i, stat) in maps.take(6).indexed) ...[
            if (i > 0) const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stat.map, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(
                        '${stat.matches} games · ${(stat.wins * 100 / stat.matches).round()}% ${game == Game.apex ? 'gains' : 'wins'}',
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${signed(stat.delta)} ${game.unit}',
                  style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.delta(stat.delta)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: stat.delta.abs() / maxAbs,
                minHeight: 6,
                backgroundColor: AppColors.surfaceHigh,
                color: AppColors.delta(stat.delta),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Apex's current and next maps for ranked and pubs, with a live countdown.
class RotationCard extends StatefulWidget {
  const RotationCard({super.key, required this.rotation});

  final MapRotation rotation;

  @override
  State<RotationCard> createState() => _RotationCardState();
}

class _RotationCardState extends State<RotationCard> {
  late final _ticker = Stream.periodic(const Duration(seconds: 1));

  @override
  Widget build(BuildContext context) {
    final modes = [
      ('Ranked', widget.rotation.ranked, AppColors.gold),
      ('Battle Royale', widget.rotation.battleRoyale, AppColors.cyan),
      ('Mixtape', widget.rotation.ltm, AppColors.violet),
    ].where((m) => m.$2?.current != null).toList();

    return StreamBuilder(
      stream: _ticker,
      builder: (context, _) => Column(
        children: [
          for (final (i, (label, pair, color)) in modes.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            _RotationTile(label: label, pair: pair!, color: color),
          ],
        ],
      ),
    );
  }
}

class _RotationTile extends StatelessWidget {
  const _RotationTile({required this.label, required this.pair, required this.color});

  final String label;
  final RotationPair pair;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final current = pair.current!;
    final remaining = current.end?.difference(DateTime.now());
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          color: AppColors.surface,
          image: current.image == null
              ? null
              : DecorationImage(
                  image: NetworkImage(current.image!),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.55), BlendMode.darken),
                  onError: (_, _) {},
                ),
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [current.map, if (current.mode != null && label == 'Mixtape') current.mode].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                  if (pair.next != null)
                    Text(
                      'Next: ${pair.next!.map}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            if (remaining != null && !remaining.isNegative)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)),
                child: Text(
                  _countdown(remaining),
                  style: TextStyle(color: color, fontWeight: FontWeight.w900, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _countdown(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours >= 24) return '${d.inDays}d ${d.inHours % 24}h';
    return d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
