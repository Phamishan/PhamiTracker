import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/summary.dart';
import '../services/tracker_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/game_switcher.dart';
import '../widgets/history_chart.dart';
import '../widgets/match_list.dart';
import '../widgets/rank_hero.dart';
import '../widgets/stat_tiles.dart';
import 'home_page.dart';
import 'link_account_page.dart';

/// Who to look up. Kept so the player page can refresh itself.
class PlayerQuery {
  const PlayerQuery({required this.game, required this.name, this.tag, required this.platform, this.region});

  final Game game;
  final String name;
  final String? tag;
  final String platform;
  final String? region;

  Future<PlayerSummary> run(TrackerApi api) =>
      api.search(game: game, name: name, tag: tag, platform: platform, region: region);
}

/// Look up any player's rank and recent games without tracking them.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.initialGame});

  final Game initialGame;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _name = TextEditingController();
  final _tag = TextEditingController();
  late Game _game = widget.initialGame;
  late String _platform = _defaultPlatform(_game);
  String _region = 'eu';
  bool _busy = false;
  String? _error;

  static String _defaultPlatform(Game game) => game == Game.apex ? 'PC' : 'pc';

  @override
  void initState() {
    super.initState();
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    if (locale.countryCode == 'US' || locale.countryCode == 'CA') _region = 'na';
  }

  @override
  void dispose() {
    _name.dispose();
    _tag.dispose();
    super.dispose();
  }

  void _selectGame(Game game) => setState(() {
        _game = game;
        _platform = _defaultPlatform(game);
        _error = null;
      });

  Future<void> _search() async {
    var name = _name.text.trim();
    var tag = _tag.text.trim().replaceFirst('#', '');
    // Accept "Name#TAG" typed into the name field.
    if (_game == Game.valorant && name.contains('#') && tag.isEmpty) {
      final parts = name.split('#');
      name = parts.first.trim();
      tag = parts.last.trim();
    }
    if (name.isEmpty || (_game == Game.valorant && tag.isEmpty)) {
      setState(() => _error = _game == Game.valorant ? 'Enter a Riot ID and tag.' : 'Enter a player name.');
      return;
    }
    FocusScope.of(context).unfocus();
    final query = PlayerQuery(
      game: _game,
      name: name,
      tag: _game == Game.valorant ? tag : null,
      platform: _platform,
      region: _game == Game.valorant ? _region : null,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final summary = await query.run(AppScope.of(context).api);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerPage(query: query, initial: summary)),
      );
    } on TrackerApiException catch (e) {
      setState(() => _error = e.statusCode == 404 ? "Couldn't find that player. Check the spelling and platform." : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = _game;
    final platforms = game == Game.apex ? apexPlatforms : valorantPlatforms;
    return Scaffold(
      appBar: AppBar(title: const Text('Search Player')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          GameSwitcher(selected: game, onChanged: _selectGame),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _name,
                  autocorrect: false,
                  textInputAction: game == Game.valorant ? TextInputAction.next : TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: game == Game.apex ? 'Player name' : 'Riot ID',
                    prefixIcon: const Icon(Icons.search_rounded),
                  ),
                  onSubmitted: (_) => game == Game.apex ? _search() : null,
                ),
              ),
              if (game == Game.valorant) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _tag,
                    autocorrect: false,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(labelText: 'Tag', prefixText: '#'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
              ],
            ],
          ),
          const SectionTitle('Platform'),
          OptionChips(options: platforms, selected: _platform, game: game, onSelected: (v) => setState(() => _platform = v)),
          if (game == Game.valorant) ...[
            const SectionTitle('Region'),
            OptionChips(options: valorantRegions, selected: _region, game: game, onSelected: (v) => setState(() => _region = v)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(_error!, style: const TextStyle(color: AppColors.loss, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 28),
          GradientButton(game: game, label: 'Search', busy: _busy, onPressed: _search),
          const SizedBox(height: 14),
          Text(
            game == Game.apex
                ? 'Shows their live rank. Matches show up if someone tracks the account in PhamiTracker.'
                : 'Shows their rank and recent ranked games from Riot.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// A searched player's page: the same cards as your own dashboard, minus the goal.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.query, required this.initial});

  final PlayerQuery query;
  final PlayerSummary initial;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late PlayerSummary _summary = widget.initial;

  Future<void> _refresh() async {
    try {
      final summary = await widget.query.run(AppScope.of(context).api);
      if (mounted) setState(() => _summary = summary);
    } on TrackerApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final game = s.game;
    return Scaffold(
      appBar: AppBar(title: Text(s.name)),
      body: RefreshIndicator(
        color: game.glow,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          children: [
            RankHero(game: game, summary: s, accountName: s.name),
            const SizedBox(height: 12),
            TodayTile(game: game, today: s.today),
            if (s.history.isNotEmpty) ...[
              const SectionTitle('Climb'),
              HistoryChart(game: game, history: s.history, range: ClimbRange.twoWeeks),
            ],
            if (s.maps.isNotEmpty) ...[
              const SectionTitle('By Map'),
              MapStatsCard(game: game, maps: s.maps),
            ],
            SectionTitle(s.matches.isEmpty ? 'Recent Matches' : 'Recent Matches · ${s.matches.length}'),
            MatchList(
              game: game,
              matches: s.matches,
              emptyText: game == Game.apex && !s.tracked
                  ? "Apex doesn't share match history. Games show up here once someone tracks this account in PhamiTracker."
                  : 'No recent ranked games.',
            ),
          ],
        ),
      ),
    );
  }
}
