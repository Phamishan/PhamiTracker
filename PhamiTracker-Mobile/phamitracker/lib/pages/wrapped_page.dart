import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/game.dart';
import '../models/insights.dart';
import '../models/ranks.dart';
import '../theme/app_theme.dart';
import '../widgets/insight_cards.dart';

final _number = NumberFormat.decimalPattern();

/// Split / act Wrapped: story cards to swipe (or tap) through, each one shareable as an image.
class WrappedPage extends StatefulWidget {
  const WrappedPage({super.key, required this.game, required this.period, required this.player, this.finished = false});

  final Game game;
  final PeriodStats period;
  final String player;

  /// The split is over ("Wrapped"), or still running ("so far").
  final bool finished;

  @override
  State<WrappedPage> createState() => _WrappedPageState();
}

class _WrappedPageState extends State<WrappedPage> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index, int count) {
    if (index < 0 || index >= count) return;
    _pages.animateToPage(index, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final cards = wrappedCards(widget.game, widget.period, widget.player, finished: widget.finished);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${widget.period.noun} Wrapped'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Story-style progress: one bar per card.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 3,
                        decoration: BoxDecoration(
                          color: i <= _index ? Colors.white : Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                // Tap the right side for the next card, the left for the previous one.
                onTapUp: (d) {
                  final width = context.size?.width ?? 1;
                  _go(d.localPosition.dx > width / 3 ? _index + 1 : _index - 1, cards.length);
                },
                child: PageView(
                  controller: _pages,
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    for (final (i, card) in cards.indexed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 9 / 16,
                            child: ShareableCard(
                              fileName: 'phamitracker-wrapped-${i + 1}',
                              child: _WrappedCard(game: widget.game, card: card, player: widget.player, period: widget.period),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One story card's content.
class WrappedCardData {
  const WrappedCardData({required this.kicker, required this.big, this.title, this.lines = const [], this.color, this.icon});

  final String kicker;

  /// The headline number or name.
  final String big;
  final String? title;
  final List<String> lines;
  final Color? color;
  final IconData? icon;
}

/// The cards for a split, skipping the ones there's no data for.
List<WrappedCardData> wrappedCards(Game game, PeriodStats p, String player, {bool finished = false}) {
  final w = p.wrapped;
  final unit = game.unit;
  String? rank(int? score) => score == null ? null : rankAt(game, score).label;
  final gains = game.winWord;
  return [
    WrappedCardData(
      kicker: player,
      big: p.name.isEmpty ? 'This ${p.noun.toLowerCase()}' : p.name,
      title: finished ? '${p.noun} Wrapped' : '${p.noun} Wrapped, so far',
      lines: [if (p.start != null) '${DateFormat('d MMM').format(p.start!)} – ${p.end == null ? 'now' : DateFormat('d MMM').format(p.end!)}'],
      icon: Icons.auto_awesome_rounded,
    ),
    WrappedCardData(
      kicker: 'You played',
      big: '${_number.format(p.games)} games',
      lines: [
        if (w != null) '≈ ${w.hours} ${w.hours == 1 ? 'hour' : 'hours'} in ${w.sessions} ${w.sessions == 1 ? 'session' : 'sessions'}',
        'over ${p.daysPlayed} ${p.daysPlayed == 1 ? 'day' : 'days'}',
        '${p.wins} $gains · ${p.losses} ${game.lossWord}',
      ],
      icon: Icons.sports_esports_rounded,
    ),
    WrappedCardData(
      kicker: finished ? 'You finished' : 'So far you are',
      big: '${signed(p.net)} $unit',
      color: AppColors.delta(p.net),
      lines: [
        if (rank(p.startScore) != null && rank(p.endScore) != null) '${rank(p.startScore)} → ${rank(p.endScore)}',
        if (p.endScore != null && game != Game.lol) scoreText(game, p.endScore!),
      ],
      icon: p.net >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
    ),
    if (p.peak != null)
      WrappedCardData(
        kicker: 'Your peak',
        big: rank(p.peak)!,
        lines: [
          scoreText(game, p.peak!),
          if (p.peakAt != null) DateFormat('EEEE d MMMM').format(p.peakAt!),
        ],
        color: rankColor(rank(p.peak)),
        icon: Icons.emoji_events_rounded,
      ),
    if (w?.mostPlayed case final main?)
      WrappedCardData(
        kicker: game == Game.apex ? 'Your main' : 'Your main ${game.characterNoun.toLowerCase()}',
        big: main.map,
        lines: [
          '${main.matches} games · ${signed(main.delta)} $unit',
          '${(main.wins * 100 / main.matches).round()}% $gains',
          if (main.kd != null) 'K/D ${main.kd!.toStringAsFixed(2)}',
        ],
        icon: Icons.person_rounded,
      ),
    if (w?.bestMap case final map?)
      WrappedCardData(
        kicker: 'Your best map',
        big: map.map,
        color: AppColors.gain,
        lines: ['${signed(map.delta)} $unit in ${map.matches} games'],
        icon: Icons.map_rounded,
      ),
    if (p.bestDay != null && p.bestDayDelta != null)
      WrappedCardData(
        kicker: 'Your best day',
        big: DateFormat('d MMMM').format(p.bestDay!),
        color: AppColors.gain,
        lines: [
          '${signed(p.bestDayDelta!)} $unit',
          if (w?.bestSessionNet case final net?) 'Best session: ${signed(net)} $unit in ${w!.bestSessionGames} games',
        ],
        icon: Icons.calendar_month_rounded,
      ),
    if (p.longestWinStreak > 1 || p.biggestGain != null)
      WrappedCardData(
        kicker: 'On fire',
        big: '${p.longestWinStreak} in a row',
        title: 'longest ${game.hasWins ? 'win' : 'gain'} streak',
        lines: [if (p.biggestGain != null) 'Biggest game: ${signed(p.biggestGain!)} $unit'],
        color: AppColors.gain,
        icon: Icons.local_fire_department_rounded,
      ),
    if (w?.climb case final climb? when climb > 0)
      WrappedCardData(
        kicker: 'Your biggest climb',
        big: '${signed(climb)} $unit',
        color: AppColors.gain,
        lines: [
          if (rank(w!.climbFrom) != null && rank(w.climbTo) != null) 'from ${rank(w.climbFrom)} to ${rank(w.climbTo)}',
          if (p.biggestLoss != null) 'Worst game along the way: ${signed(p.biggestLoss!)} $unit',
        ],
        icon: Icons.terrain_rounded,
      ),
    WrappedCardData(
      kicker: 'That was your',
      big: finished ? p.noun : '${p.noun} so far',
      title: p.name,
      lines: [
        '${_number.format(p.games)} games · ${signed(p.net)} $unit',
        if (p.peak != null) 'Peak ${rank(p.peak)}',
        if (w?.mostPlayed != null) 'Main ${w!.mostPlayed!.map}',
        if (w?.bestMap != null) 'Best map ${w!.bestMap!.map}',
      ],
      icon: Icons.ios_share_rounded,
    ),
  ];
}

class _WrappedCard extends StatelessWidget {
  const _WrappedCard({required this.game, required this.card, required this.player, required this.period});

  final Game game;
  final WrappedCardData card;
  final String player;
  final PeriodStats period;

  @override
  Widget build(BuildContext context) {
    final color = card.color ?? game.glow;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color.lerp(color, Colors.black, 0.35)!, const Color(0xFF111114), Color.lerp(game.glow, Colors.black, 0.6)!],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 30, 26, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PHAMITRACKER', style: AppText.label(color: Colors.white54, size: 10)),
              const Spacer(),
              if (card.icon != null) Icon(card.icon, color: Colors.white, size: 34),
              const SizedBox(height: 18),
              Text(card.kicker.toUpperCase(), style: AppText.label(color: Colors.white70, size: 12)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(card.big, style: AppText.display(46, color: Colors.white)),
              ),
              if (card.title != null) ...[
                const SizedBox(height: 4),
                Text(card.title!.toUpperCase(), style: AppText.label(color: color, size: 12)),
              ],
              const SizedBox(height: 16),
              for (final line in card.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500)),
                ),
              const Spacer(flex: 2),
              Text(
                [player, period.name].where((s) => s.isNotEmpty).join('  ·  ').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(color: Colors.white38, size: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
