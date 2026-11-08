import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/game_logo.dart';
import '../widgets/rank_hero.dart';

final _number = NumberFormat.decimalPattern();

/// One line of the head-to-head. [mine]/[theirs] decide who wins it (higher is better);
/// null on either side means there's nothing to compare, so nobody gets the point.
class CompareRow {
  const CompareRow(this.label, this.myText, this.theirText, {this.mine, this.theirs});

  final String label;
  final String myText;
  final String theirText;
  final num? mine;
  final num? theirs;

  /// 1 = you, -1 = them, 0 = tie / not comparable.
  int get winner {
    if (mine == null || theirs == null || mine == theirs) return 0;
    return mine! > theirs! ? 1 : -1;
  }
}

/// The rows for two players of the same game.
List<CompareRow> compareRows(PlayerSummary me, PlayerSummary them) {
  final game = me.game;
  final rows = <CompareRow>[
    CompareRow(
      game == Game.apex ? 'Ranked RP' : 'Rating (elo)',
      me.score == null ? '—' : _number.format(me.score),
      them.score == null ? '—' : _number.format(them.score),
      mine: me.score,
      theirs: them.score,
    ),
    CompareRow('Today', '${signed(me.today.delta)} ${game.unit}', '${signed(them.today.delta)} ${game.unit}',
        mine: me.today.delta, theirs: them.today.delta),
  ];

  List<MatchEntry> last10(PlayerSummary s) => [for (final m in s.matches) if (!m.isAdjustment) m].take(10).toList();
  final myGames = last10(me);
  final theirGames = last10(them);
  int net(List<MatchEntry> g) => g.fold(0, (sum, m) => sum + m.delta);
  int wins(List<MatchEntry> g) => g.where((m) => m.won ?? m.delta > 0).length;
  if (myGames.isNotEmpty || theirGames.isNotEmpty) {
    rows.add(CompareRow(
      'Last 10 games',
      myGames.isEmpty ? '—' : '${signed(net(myGames))} ${game.unit}',
      theirGames.isEmpty ? '—' : '${signed(net(theirGames))} ${game.unit}',
      mine: myGames.isEmpty ? null : net(myGames),
      theirs: theirGames.isEmpty ? null : net(theirGames),
    ));
    rows.add(CompareRow(
      game == Game.apex ? 'Gains · last 10' : 'Wins · last 10',
      myGames.isEmpty ? '—' : '${wins(myGames)}/${myGames.length}',
      theirGames.isEmpty ? '—' : '${wins(theirGames)}/${theirGames.length}',
      mine: myGames.isEmpty ? null : wins(myGames) / myGames.length,
      theirs: theirGames.isEmpty ? null : wins(theirGames) / theirGames.length,
    ));
    // Current run: +3 = three wins in a row, -2 = two losses.
    int streak(List<MatchEntry> g) {
      if (g.isEmpty) return 0;
      final won = g.first.won ?? g.first.delta > 0;
      final run = g.takeWhile((m) => (m.won ?? m.delta > 0) == won).length;
      return won ? run : -run;
    }

    String streakText(List<MatchEntry> g) {
      final s = streak(g);
      return g.isEmpty ? '—' : (s > 0 ? '${s}W' : '${-s}L');
    }

    rows.add(CompareRow('Current streak', streakText(myGames), streakText(theirGames),
        mine: myGames.isEmpty ? null : streak(myGames), theirs: theirGames.isEmpty ? null : streak(theirGames)));
  }

  if (game == Game.valorant) {
    final a = Performance.from(me.matches);
    final b = Performance.from(them.matches);
    String fixed(double? v) => v == null ? '—' : v.toStringAsFixed(2);
    String whole(double? v, [String suffix = '']) => v == null ? '—' : '${v.round()}$suffix';
    rows.addAll([
      CompareRow('K/D', fixed(a?.kd), fixed(b?.kd), mine: a?.kd, theirs: b?.kd),
      CompareRow('KDA', fixed(a?.kda), fixed(b?.kda), mine: a?.kda, theirs: b?.kda),
      CompareRow('Headshot %', whole(a?.headshotPct, '%'), whole(b?.headshotPct, '%'), mine: a?.headshotPct, theirs: b?.headshotPct),
      CompareRow('ACS', whole(a?.acs), whole(b?.acs), mine: a?.acs, theirs: b?.acs),
    ]);
  }

  MapStat? best(PlayerSummary s) =>
      s.characters.isEmpty ? null : (List.of(s.characters)..sort((x, y) => y.delta.compareTo(x.delta))).first;
  final myBest = best(me);
  final theirBest = best(them);
  if (myBest != null || theirBest != null) {
    // Shown for fun; not scored (different legends/agents aren't comparable).
    rows.add(CompareRow(
      game == Game.apex ? 'Best legend' : 'Best agent',
      myBest == null ? '—' : '${myBest.map} ${signed(myBest.delta)}',
      theirBest == null ? '—' : '${theirBest.map} ${signed(theirBest.delta)}',
    ));
  }
  return rows;
}

/// You vs a searched player, same game, row by row with a running score.
class ComparePage extends StatelessWidget {
  const ComparePage({super.key, required this.me, required this.myName, required this.them});

  final PlayerSummary me;
  final String myName;
  final PlayerSummary them;

  @override
  Widget build(BuildContext context) {
    final game = me.game;
    final rows = compareRows(me, them);
    final mine = rows.where((r) => r.winner == 1).length;
    final theirs = rows.where((r) => r.winner == -1).length;
    return Scaffold(
      appBar: AppBar(title: Text('HEAD TO HEAD', style: AppText.label(size: 14, color: AppColors.text))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
        children: [
          TrackerCard(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _Side(name: myName, summary: me, label: 'You')),
                    Column(
                      children: [
                        GameLogo(game, size: 18, color: game.glow),
                        const SizedBox(height: 8),
                        Text('$mine – $theirs', style: AppText.display(30)),
                      ],
                    ),
                    Expanded(child: _Side(name: them.name, summary: them, label: 'Them')),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  (mine == theirs ? 'Dead even' : mine > theirs ? 'You lead' : '${them.name.split('#').first} leads').toUpperCase(),
                  style: AppText.label(color: mine == theirs ? AppColors.textDim : mine > theirs ? AppColors.gain : AppColors.loss),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TrackerCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.border),
                  _Line(row: row),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            game == Game.apex
                ? 'Last-10 numbers need recorded games, which a searched Apex player only has if someone tracks them.'
                : 'K/D and the rest are from each player\'s recent ranked games.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.name, required this.summary, required this.label});

  final String name;
  final PlayerSummary summary;
  final String label;

  @override
  Widget build(BuildContext context) {
    final rank = summary.rankLabel ?? summary.rank.name ?? '—';
    return Column(
      children: [
        RankBadge(name: rank, imageUrl: summary.rank.image, size: 56),
        const SizedBox(height: 8),
        Text(label.toUpperCase(), style: AppText.label(size: 9, color: AppColors.textFaint)),
        const SizedBox(height: 2),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(rank.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.label(size: 10)),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.row});

  final CompareRow row;

  @override
  Widget build(BuildContext context) {
    TextStyle side(bool won) => AppText.display(16, color: won ? AppColors.gain : AppColors.text);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(row.myText, style: side(row.winner == 1))),
          Expanded(
            flex: 2,
            child: Text(row.label.toUpperCase(), textAlign: TextAlign.center, style: AppText.label(size: 10)),
          ),
          Expanded(child: Text(row.theirText, textAlign: TextAlign.right, style: side(row.winner == -1))),
        ],
      ),
    );
  }
}
