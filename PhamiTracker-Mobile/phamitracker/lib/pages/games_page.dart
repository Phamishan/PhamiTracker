import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../services/tracker_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/insight_cards.dart';
import '../widgets/match_list.dart';

/// Every game behind one By Legend / By Agent / By Map row: the totals, then each game.
class GamesPage extends StatefulWidget {
  const GamesPage({super.key, required this.game, required this.stat, required this.byMap, required this.load, this.subtitle, this.onOpenMatch});

  final Game game;

  /// The row that was tapped (its name and totals while the games load).
  final MapStat stat;
  final bool byMap;

  /// "This split" / "All" / "Last 100 games".
  final String? subtitle;
  final Future<List<MatchEntry>> Function() load;

  /// VALORANT: open a game's scoreboard.
  final ValueChanged<MatchEntry>? onOpenMatch;

  @override
  State<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends State<GamesPage> {
  List<MatchEntry>? _games;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final games = await widget.load();
      if (mounted) setState(() => _games = games);
    } on TrackerApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final stat = widget.stat;
    final games = _games;
    final kind = widget.byMap ? 'Map' : game == Game.apex ? 'Legend' : 'Agent';
    final kills = games?.where((m) => m.kills != null && m.deaths != null) ?? const <MatchEntry>[];
    final deaths = kills.fold<int>(0, (sum, m) => sum + m.deaths!);
    final best = games == null || games.isEmpty ? null : games.map((m) => m.delta).reduce((a, b) => a > b ? a : b);
    final worst = games == null || games.isEmpty ? null : games.map((m) => m.delta).reduce((a, b) => a < b ? a : b);
    return Scaffold(
      appBar: AppBar(title: Text(stat.map)),
      body: RefreshIndicator(
        color: game.glow,
        onRefresh: _fetch,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          children: [
            TrackerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text([kind, ?widget.subtitle].join('  ·  ').toUpperCase(), style: AppText.label(color: AppColors.textFaint)),
                  const SizedBox(height: 6),
                  Text('${signed(stat.delta)} ${game.unit}', style: AppText.display(34, color: AppColors.delta(stat.delta))),
                  const SizedBox(height: 14),
                  FactGrid(columns: 3, [
                    Fact('Games', '${stat.matches}'),
                    Fact(game == Game.apex ? 'Gains' : 'Wins', '${(stat.wins * 100 / stat.matches).round()}%'),
                    Fact('Avg', signed((stat.delta / stat.matches).round())),
                    Fact('Best', best == null ? '—' : signed(best), color: best == null ? AppColors.text : AppColors.delta(best)),
                    Fact('Worst', worst == null ? '—' : signed(worst), color: worst == null ? AppColors.text : AppColors.delta(worst)),
                    Fact('K/D', kills.isEmpty ? '—' : (kills.fold<int>(0, (sum, m) => sum + m.kills!) / (deaths == 0 ? 1 : deaths)).toStringAsFixed(2)),
                  ]),
                ],
              ),
            ),
            SectionTitle(games == null ? 'Games' : 'Games · ${games.length}'),
            if (_error != null)
              TrackerCard(child: Text(_error!, style: const TextStyle(color: AppColors.textDim)))
            else if (games == null)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else
              MatchList(game: game, matches: games, showAll: true, onOpen: widget.onOpenMatch, emptyText: 'No games here yet.'),
          ],
        ),
      ),
    );
  }
}
