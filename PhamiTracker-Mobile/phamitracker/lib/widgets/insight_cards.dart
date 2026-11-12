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
class Fact extends StatelessWidget {
  const Fact(this.label, this.value, {super.key, this.color = AppColors.text});

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
class FactGrid extends StatelessWidget {
  const FactGrid(this.facts, {super.key, this.columns = 2});

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

/// Every session in the match list, newest first: swipe (or tap the arrows) to go back in time.
class SessionsCard extends StatefulWidget {
  const SessionsCard({super.key, required this.game, required this.sessions, required this.player, this.now});

  final Game game;

  /// Newest first (Session.all).
  final List<Session> sessions;
  final String player;
  final DateTime? now;

  @override
  State<SessionsCard> createState() => _SessionsCardState();
}

class _SessionsCardState extends State<SessionsCard> {
  int _index = 0;
  bool _back = true;

  void _go(int index) {
    if (index < 0 || index >= widget.sessions.length) return;
    setState(() {
      _back = index > _index;
      _index = index;
    });
  }

  @override
  void didUpdateWidget(SessionsCard old) {
    super.didUpdateWidget(old);
    // A new game can start a new session; stay in range and keep showing the latest on refresh.
    if (_index >= widget.sessions.length || widget.sessions.length != old.sessions.length) _index = 0;
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.sessions.length;
    final i = _index.clamp(0, count - 1);
    final card = SessionCard(
      key: ValueKey(widget.sessions[i].start),
      game: widget.game,
      session: widget.sessions[i],
      player: widget.player,
      now: widget.now,
      title: i == 0 ? null : 'Earlier session',
    );
    return Column(
      children: [
        GestureDetector(
          // Swipe left for older sessions, right for newer.
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -200) _go(i + 1);
            if (v > 200) _go(i - 1);
          },
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) {
                final incoming = child.key == card.key;
                final dx = (_back ? 1.0 : -1.0) * (incoming ? 0.25 : -0.25);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                );
              },
              layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
              child: card,
            ),
          ),
        ),
        if (count > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Newer session',
                  visualDensity: VisualDensity.compact,
                  onPressed: i > 0 ? () => _go(i - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: AppColors.textDim,
                ),
                Text('${i + 1} / $count', style: AppText.label(size: 10, color: AppColors.textFaint)),
                IconButton(
                  tooltip: 'Older session',
                  visualDensity: VisualDensity.compact,
                  onPressed: i < count - 1 ? () => _go(i + 1) : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: AppColors.textDim,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// "Last Session" / "Current Session": games played close together, with a share button.
class SessionCard extends StatelessWidget {
  const SessionCard({super.key, required this.game, required this.session, required this.player, this.now, this.title});

  final Game game;
  final Session session;
  final String player;
  final DateTime? now;

  /// Overrides "Last session" / "Current session" (older sessions in [SessionsCard]).
  final String? title;

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
            _ShareHeader(game: game, player: player, title: title ?? (over ? 'Last session' : 'Current session')),
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
            FactGrid(columns: 4, [
              Fact('Games', '${s.matches.length}'),
              Fact('W / L', '${s.wins}/${s.losses}'),
              Fact('Best', signed(s.best), color: AppColors.delta(s.best)),
              Fact('Worst', signed(s.worst), color: AppColors.delta(s.worst)),
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
              FactGrid([
                Fact('Net ${game.unit}', signed(p.net), color: AppColors.delta(p.net)),
                Fact('Games · W/L', '${p.games} · ${p.wins}/${p.losses}'),
                Fact('Peak', p.peak == null ? '—' : _number.format(p.peak)),
                Fact(
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
          FactGrid(columns: 3, [
            Fact(
              p.streakWon ? 'Win streak' : 'Loss streak',
              p.streak == 0 ? '—' : '${p.streak}',
              color: p.streak == 0 ? AppColors.text : streakColor,
            ),
            Fact('Best streak', p.longestWinStreak == 0 ? '—' : '${p.longestWinStreak}'),
            Fact('Peak', p.peak == null ? '—' : _number.format(p.peak)),
            Fact(
              p.bestDay == null ? 'Best day' : 'Best day · ${DateFormat('d MMM').format(p.bestDay!)}',
              p.bestDayDelta == null ? '—' : signed(p.bestDayDelta!),
              color: p.bestDayDelta == null ? AppColors.text : AppColors.gain,
            ),
            Fact('Best game', p.biggestGain == null ? '—' : signed(p.biggestGain!), color: p.biggestGain == null ? AppColors.text : AppColors.gain),
            Fact('Worst game', p.biggestLoss == null ? '—' : signed(p.biggestLoss!), color: p.biggestLoss == null ? AppColors.text : AppColors.loss),
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
