import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/insights.dart';
import '../models/player_query.dart';
import '../models/summary.dart';
import '../services/tracker_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/game_logo.dart';
import '../widgets/game_switcher.dart';
import '../widgets/history_chart.dart';
import '../widgets/insight_cards.dart';
import '../widgets/match_list.dart';
import '../widgets/performance_card.dart';
import '../widgets/rank_hero.dart';
import '../widgets/stat_tiles.dart';
import 'home_page.dart';
import 'compare_page.dart';
import 'link_account_page.dart';
import 'match_page.dart';

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
    await _open(PlayerQuery(
      game: _game,
      name: name,
      tag: _game == Game.valorant ? tag : null,
      platform: _platform,
      region: _game == Game.valorant ? _region : null,
    ));
  }

  /// Looks the player up, remembers the search and opens their page.
  Future<void> _open(PlayerQuery query) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final state = AppScope.of(context);
    try {
      final summary = await query.run(state.api);
      final found = query.withDisplayName(summary.name);
      state.addRecentSearch(found);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerPage(query: found, initial: summary)),
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
          if (AppScope.of(context).favorites.isNotEmpty) ...[
            const SectionTitle('Favourites'),
            _SavedList(players: AppScope.of(context).favorites, onOpen: _busy ? null : _open),
          ],
          if (AppScope.of(context).recentSearches.isNotEmpty) ...[
            SectionTitle(
              'Recent',
              trailing: TextButton(
                onPressed: AppScope.of(context).clearRecentSearches,
                child: Text('CLEAR', style: AppText.label(color: AppColors.textDim)),
              ),
            ),
            _SavedList(
              players: AppScope.of(context).recentSearches,
              onOpen: _busy ? null : _open,
              onRemove: AppScope.of(context).removeRecentSearch,
            ),
          ],
        ],
      ),
    );
  }
}

/// Favourite or recent players: tap to open, swipe a recent one away.
class _SavedList extends StatelessWidget {
  const _SavedList({required this.players, required this.onOpen, this.onRemove});

  final List<PlayerQuery> players;
  final ValueChanged<PlayerQuery>? onOpen;
  final ValueChanged<PlayerQuery>? onRemove;

  @override
  Widget build(BuildContext context) {
    return TrackerCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final (i, q) in players.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18, color: AppColors.border),
            _row(q),
          ],
        ],
      ),
    );
  }

  Widget _row(PlayerQuery q) {
    final where = q.game == Game.apex
        ? apexPlatforms[q.platform] ?? q.platform
        : '${valorantRegions[q.region] ?? q.region} · ${valorantPlatforms[q.platform] ?? q.platform}';
    final tile = ListTile(
      onTap: onOpen == null ? null : () => onOpen!(q),
      leading: GameLogo(q.game, size: 20, color: q.game.glow),
      title: Text(q.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(where.toUpperCase(), style: AppText.label(size: 9, color: AppColors.textFaint)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
    );
    if (onRemove == null) return tile;
    return Dismissible(
      key: ValueKey(q.key),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove!(q),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.loss),
      ),
      child: tile,
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
    final state = AppScope.of(context);
    final favorite = state.isFavorite(widget.query);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [
          // Head to head: needs your own account for this game.
          if (state.summaries[game] case final mine? when state.accounts[game] != null)
            IconButton(
              tooltip: 'Compare with you',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ComparePage(me: mine, myName: state.accounts[game]!.displayName, them: s),
              )),
              icon: const Icon(Icons.compare_arrows_rounded, color: AppColors.textDim),
            ),
          IconButton(
            tooltip: favorite ? 'Remove from favourites' : 'Add to favourites',
            onPressed: () => state.toggleFavorite(widget.query.withDisplayName(s.name)),
            icon: Icon(
              favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: favorite ? AppColors.goal : AppColors.textDim,
            ),
          ),
        ],
      ),
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
            // Their last session, from the games we have (VALORANT recent games, or Apex if tracked).
            if (Session.all(s.matches, game: game) case final sessions when sessions.isNotEmpty) ...[
              const SizedBox(height: 12),
              SessionsCard(game: game, sessions: sessions, player: s.name),
            ],
            if (game == Game.valorant && Performance.from(s.matches) != null) ...[
              const SectionTitle('Performance'),
              PerformanceCard(game: game, matches: s.matches),
            ],
            if (s.history.isNotEmpty) ...[
              const SectionTitle('Climb'),
              HistoryChart(game: game, history: s.history, range: ClimbRange.twoWeeks),
            ],
            if (s.characters.isNotEmpty) ...[
              SectionTitle(game == Game.apex ? 'By Legend' : 'By Agent'),
              MapStatsCard(game: game, maps: s.characters),
            ],
            if (s.maps.isNotEmpty) ...[
              const SectionTitle('By Map'),
              MapStatsCard(game: game, maps: s.maps),
            ],
            SectionTitle(s.matches.isEmpty ? 'Recent Matches' : 'Recent Matches · ${s.matches.length}'),
            MatchList(
              game: game,
              matches: s.matches,
              onOpen: game == Game.valorant
                  ? (match) => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MatchPage(match: match, region: widget.query.region ?? 'eu', playerName: s.name),
                      ))
                  : null,
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
