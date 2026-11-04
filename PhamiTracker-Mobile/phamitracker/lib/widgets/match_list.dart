import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Every rank change the worker picked up, newest first. Shows five, scrolls for the rest.
class MatchList extends StatelessWidget {
  const MatchList({super.key, required this.game, required this.matches, this.emptyText});

  static const visibleRows = 5;
  static const rowHeight = 64.0;

  final Game game;
  final List<MatchEntry> matches;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return TrackerCard(
        child: Text(
          emptyText ?? "No ranked games yet. They show up here a minute after each match, even with the app closed.",
          style: const TextStyle(color: AppColors.textDim, height: 1.4),
        ),
      );
    }
    return TrackerCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: SizedBox(
        height: rowHeight * math.min(matches.length, visibleRows),
        child: Scrollbar(
          child: ListView.separated(
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: matches.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 18, endIndent: 18, color: AppColors.border),
            itemBuilder: (context, i) => SizedBox(height: rowHeight - 1, child: _MatchTile(game: game, match: matches[i])),
          ),
        ),
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
    final color = match.isAdjustment ? AppColors.textDim : AppColors.delta(match.delta);
    final title = match.isAdjustment
        ? 'Rank adjustment'
        : [match.character, match.map].nonNulls.join(' · ').ifEmpty('Ranked match');
    final details = [
      matchDate(match.time),
      if (match.kills != null) '${match.kills}/${match.deaths}/${match.assists}',
      if (match.roundsWon != null) '${match.roundsWon}–${match.roundsLost}',
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          // Result tile: green up arrow for a gain, red down for a loss.
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
            child: Icon(
              match.isAdjustment
                  ? Icons.tune_rounded
                  : match.delta >= 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(15)),
                const SizedBox(height: 3),
                Text(details.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(size: 10)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text('${signed(match.delta)} ${game.unit}', style: AppText.display(17, color: color)),
        ],
      ),
    );
  }
}

/// "Today, 13:48", "Yesterday, 21:02", "Sun 1 Nov, 18:30" (with the year once it isn't this year).
String matchDate(DateTime time, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(time);
  final clock = DateFormat.Hm().format(time);
  if (day == today) return 'Today, $clock';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday, $clock';
  final date = day.year == today.year ? DateFormat('EEE d MMM') : DateFormat('d MMM yyyy');
  return '${date.format(time)}, $clock';
}

/// "18:30" in Danish time (Europe/Copenhagen, 24-hour), whatever the phone's own zone is.
String danishClock(DateTime time) => DateFormat('HH:mm').format(copenhagenTime(time));

/// [time] as a wall-clock in Copenhagen: CET (UTC+1), or CEST (UTC+2) from the last Sunday of
/// March to the last Sunday of October, switching at 01:00 UTC (the EU rule).
DateTime copenhagenTime(DateTime time) {
  final utc = time.toUtc();
  DateTime lastSunday(int month) {
    final lastDay = DateTime.utc(utc.year, month + 1, 0);
    return DateTime.utc(utc.year, month, lastDay.day - lastDay.weekday % 7, 1);
  }

  final summer = !utc.isBefore(lastSunday(3)) && utc.isBefore(lastSunday(10));
  return utc.add(Duration(hours: summer ? 2 : 1));
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
            if (i > 0) const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stat.map.toUpperCase(), style: AppText.display(15)),
                      const SizedBox(height: 3),
                      Text(
                        '${stat.matches} GAMES · ${(stat.wins * 100 / stat.matches).round()}% ${game == Game.apex ? 'GAINS' : 'WINS'}',
                        style: AppText.label(size: 10),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${signed(stat.delta)} ${game.unit}',
                  style: AppText.display(17, color: AppColors.delta(stat.delta)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ProgressBar(value: stat.delta.abs() / maxAbs, color: AppColors.delta(stat.delta), height: 5),
          ],
        ],
      ),
    );
  }
}

/// Apex's current and next maps, with the map art behind and a live countdown.
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
      ('Ranked', widget.rotation.ranked),
      ('Battle Royale', widget.rotation.battleRoyale),
      ('Mixtape', widget.rotation.ltm),
    ].where((m) => m.$2?.current != null).toList();

    return StreamBuilder(
      stream: _ticker,
      builder: (context, _) => Column(
        children: [
          for (final (i, (label, pair)) in modes.indexed) ...[
            if (i > 0) const SizedBox(height: 12),
            _RotationTile(label: label, pair: pair!, large: i == 0),
          ],
        ],
      ),
    );
  }
}

class _RotationTile extends StatelessWidget {
  const _RotationTile({required this.label, required this.pair, required this.large});

  final String label;
  final RotationPair pair;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final current = pair.current!;
    final now = DateTime.now();
    final remaining = current.end?.difference(now);
    final total = current.start != null && current.end != null ? current.end!.difference(current.start!) : null;
    final elapsed = total == null || total.inSeconds <= 0 || remaining == null
        ? null
        : 1 - remaining.inSeconds / total.inSeconds;
    final name = [current.map, if (label == 'Mixtape' && current.mode != null) current.mode].join(' · ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: large ? 190 : 120,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          image: current.image == null
              ? null
              : DecorationImage(image: NetworkImage(current.image!), fit: BoxFit.cover, onError: (_, _) {}),
        ),
        child: Container(
          // Darken toward the bottom so the text always reads.
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.6)],
              stops: const [0.35, 1],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(label.toUpperCase(), style: AppText.label(color: Colors.white, size: 10)),
                  ),
                  const Spacer(),
                  if (pair.next != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(99)),
                      child: Text('NEXT: ${pair.next!.map.toUpperCase()}', style: AppText.label(color: Colors.white, size: 10)),
                    ),
                ],
              ),
              const Spacer(),
              if (large)
                Row(
                  children: [
                    const LiveDot(color: AppColors.accent, size: 7),
                    const SizedBox(width: 8),
                    Text('NOW PLAYING', style: AppText.label(color: Colors.white, size: 10)),
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.display(large ? 30 : 22, color: Colors.white).copyWith(
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 12)],
                ),
              ),
              if (remaining != null && !remaining.isNegative) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(_countdown(remaining), style: AppText.mono(color: Colors.white, size: large ? 20 : 15)),
                    const SizedBox(width: 10),
                    Text(
                      'ENDS ${danishClock(current.end!)}',
                      style: AppText.mono(color: Colors.white70, size: 12),
                    ),
                  ],
                ),
              ],
              if (large && elapsed != null) ...[
                const SizedBox(height: 10),
                ProgressBar(value: elapsed, color: AppColors.accent, height: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _countdown(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    if (d.inHours >= 24) return '${d.inDays}d ${d.inHours % 24}h';
    return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
