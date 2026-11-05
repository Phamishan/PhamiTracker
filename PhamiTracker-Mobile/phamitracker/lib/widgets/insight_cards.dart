import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/game.dart';
import '../models/insights.dart';
import '../models/ranks.dart';
import '../theme/app_theme.dart';
import 'common.dart';
import 'game_logo.dart';
import 'match_list.dart';

final _number = NumberFormat.decimalPattern();

/// A card with a share button that shares the card itself as an image.
class ShareableCard extends StatefulWidget {
  const ShareableCard({super.key, required this.fileName, required this.child});

  final String fileName;
  final Widget child;

  @override
  State<ShareableCard> createState() => _ShareableCardState();
}

class _ShareableCardState extends State<ShareableCard> {
  final _boundary = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    // Where the share sheet points from on iPad.
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: '${widget.fileName}.png')],
        sharePositionOrigin: origin,
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        Positioned(
          top: 6,
          right: 6,
          child: IconButton(
            tooltip: 'Share',
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share_rounded, size: 18, color: AppColors.textDim),
          ),
        ),
      ],
    );
  }
}

/// Small stat block: big value over a spaced-caps label.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.color = AppColors.text});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surfaceLow, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: AppText.display(18, color: color))),
          const SizedBox(height: 3),
          Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(size: 9, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

/// Facts laid out two (or three) to a row.
class _FactGrid extends StatelessWidget {
  const _FactGrid(this.facts, {this.columns = 2});

  final List<Widget> facts;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < facts.length; i += columns) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var j = i; j < i + columns; j++) ...[
                if (j > i) const SizedBox(width: 8),
                Expanded(child: j < facts.length ? facts[j] : const SizedBox()),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// The player name + game logo strip at the top of shareable cards, so a shared image says whose it is.
class _ShareHeader extends StatelessWidget {
  const _ShareHeader({required this.game, required this.player, required this.title});

  final Game game;
  final String player;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 36),
      child: Row(
        children: [
          GameLogo(game, size: 14, color: game.glow),
          const SizedBox(width: 8),
          Flexible(child: Text(title.toUpperCase(), overflow: TextOverflow.ellipsis, style: AppText.label())),
          Text('  ·  $player', overflow: TextOverflow.ellipsis, style: AppText.label(color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

/// "Last Session" / "Current Session": games played close together, with a share button.
class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.game, required this.session, required this.player, this.now});

  final Game game;
  final Session session;
  final String player;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final over = s.isOver(now ?? DateTime.now());
    final minutes = s.end.difference(s.start).inMinutes;
    final when = '${matchDate(s.start, now: now)} – ${DateFormat.Hm().format(s.end)}';
    return ShareableCard(
      fileName: 'phamitracker-session',
      child: TrackerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShareHeader(game: game, player: player, title: over ? 'Last session' : 'Current session'),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${signed(s.net)} ${game.unit}', style: AppText.display(34, color: AppColors.delta(s.net))),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(rankAt(game, s.endScore).label.toUpperCase(), style: AppText.display(14)),
                    Text('${_number.format(s.startScore)} → ${_number.format(s.endScore)}', style: AppText.mono(size: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$when  ·  ${minutes < 60 ? '$minutes min' : '${minutes ~/ 60}h ${minutes % 60}m'}'.toUpperCase(),
              style: AppText.label(size: 10, color: AppColors.textFaint),
            ),
            const SizedBox(height: 14),
            _FactGrid(columns: 4, [
              _Fact('Games', '${s.matches.length}'),
              _Fact('W / L', '${s.wins}/${s.losses}'),
              _Fact('Best', signed(s.best), color: AppColors.delta(s.best)),
              _Fact('Worst', signed(s.worst), color: AppColors.delta(s.worst)),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Split (Apex) / act (VALORANT) recap: where it started, where it is (or ended), peak and best pick.
class SplitRecapCard extends StatelessWidget {
  const SplitRecapCard({super.key, required this.game, required this.period, required this.player, this.finished = false});

  final Game game;
  final PeriodStats period;
  final String player;

  /// The previous split: "end" instead of "now", no days left.
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final p = period;
    final left = p.end?.difference(DateTime.now());
    final top = p.topCharacter;
    return ShareableCard(
      fileName: 'phamitracker-${p.noun.toLowerCase().replaceAll(' ', '-')}-recap',
      child: TrackerCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ShareHeader(game: game, player: player, title: p.name),
            if (!finished && left != null && !left.isNegative) ...[
              const SizedBox(height: 4),
              Text(
                (left.inDays > 0 ? '${left.inDays} days left' : '${left.inHours} hours left').toUpperCase(),
                style: AppText.label(size: 10, color: AppColors.goalSoft),
              ),
            ],
            const SizedBox(height: 16),
            if (p.games == 0)
              Text(
                'No ranked games this ${p.noun.toLowerCase()} yet.',
                style: const TextStyle(color: AppColors.textDim),
              )
            else ...[
              Row(
                children: [
                  Expanded(child: _Endpoint(label: 'Start', game: game, score: p.startScore)),
                  const Icon(Icons.arrow_forward_rounded, color: AppColors.textFaint),
                  Expanded(child: _Endpoint(label: finished ? 'End' : 'Now', game: game, score: p.endScore, alignEnd: true)),
                ],
              ),
              const SizedBox(height: 14),
              _FactGrid([
                _Fact('Net ${game.unit}', signed(p.net), color: AppColors.delta(p.net)),
                _Fact('Games · W/L', '${p.games} · ${p.wins}/${p.losses}'),
                _Fact('Peak', p.peak == null ? '—' : _number.format(p.peak)),
                _Fact(
                  game == Game.apex ? 'Best legend' : 'Best agent',
                  top == null ? '—' : '${top.map} ${signed(top.delta)}',
                  color: top == null ? AppColors.text : AppColors.delta(top.delta),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({required this.label, required this.game, required this.score, this.alignEnd = false});

  final String label;
  final Game game;
  final int? score;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final align = alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label.toUpperCase(), style: AppText.label(size: 9, color: AppColors.textFaint)),
        const SizedBox(height: 4),
        Text(score == null ? '—' : rankAt(game, score!).label.toUpperCase(), style: AppText.display(17)),
        Text(score == null ? '' : '${_number.format(score)} ${game == Game.apex ? 'RP' : 'elo'}', style: AppText.mono(size: 12)),
      ],
    );
  }
}

/// Streaks and personal bests this split/act.
class RecordsCard extends StatelessWidget {
  const RecordsCard({super.key, required this.game, required this.period});

  final Game game;
  final PeriodStats period;

  @override
  Widget build(BuildContext context) {
    final p = period;
    final streakColor = p.streakWon ? AppColors.gain : AppColors.loss;
    return TrackerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel('This ${p.noun.toLowerCase()}', icon: Icons.emoji_events_rounded),
          const SizedBox(height: 14),
          _FactGrid(columns: 3, [
            _Fact(
              p.streakWon ? 'Win streak' : 'Loss streak',
              p.streak == 0 ? '—' : '${p.streak}',
              color: p.streak == 0 ? AppColors.text : streakColor,
            ),
            _Fact('Best streak', p.longestWinStreak == 0 ? '—' : '${p.longestWinStreak}'),
            _Fact('Peak', p.peak == null ? '—' : _number.format(p.peak)),
            _Fact(
              p.bestDay == null ? 'Best day' : 'Best day · ${DateFormat('d MMM').format(p.bestDay!)}',
              p.bestDayDelta == null ? '—' : signed(p.bestDayDelta!),
              color: p.bestDayDelta == null ? AppColors.text : AppColors.gain,
            ),
            _Fact('Best game', p.biggestGain == null ? '—' : signed(p.biggestGain!), color: p.biggestGain == null ? AppColors.text : AppColors.gain),
            _Fact('Worst game', p.biggestLoss == null ? '—' : signed(p.biggestLoss!), color: p.biggestLoss == null ? AppColors.text : AppColors.loss),
          ]),
          const SizedBox(height: 10),
          Text(
            '${p.games} games over ${p.daysPlayed} ${p.daysPlayed == 1 ? 'day' : 'days'}'.toUpperCase(),
            style: AppText.label(size: 10, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}
