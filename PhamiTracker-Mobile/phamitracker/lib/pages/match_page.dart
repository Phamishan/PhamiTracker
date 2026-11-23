import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/match_detail.dart';
import '../models/player_query.dart';
import '../models/summary.dart';
import '../services/tracker_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/match_list.dart';
import '../widgets/rank_hero.dart';
import 'search_page.dart';

/// One VALORANT match: final score, then both teams with every player's agent, rank and stats.
class MatchPage extends StatefulWidget {
  const MatchPage({
    super.key,
    required this.match,
    required this.region,
    required this.playerName,
    this.teamNames = const [],
    this.teamLabel,
  });

  /// The row that was tapped (for the RR change and a header while loading).
  final MatchEntry match;
  final String region;

  /// "Name#TAG" of the player whose page this came from, highlighted in the scoreboard.
  final String playerName;

  /// Premier: the roster, so whoever of them played marks the team's side.
  final List<String> teamNames;

  /// Premier: the team's name instead of "Your Team" (and "Opponents" for the other side).
  final String? teamLabel;

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  Future<MatchDetail>? _detail;

  /// The player being looked up after a tap (their row shows a spinner).
  String? _opening;

  /// Any player in the scoreboard: their profile, looked up like a search in this match's region.
  Future<void> _openPlayer(MatchPlayer player) async {
    final tag = player.tag;
    if (tag == null || tag.isEmpty || _opening != null) return;
    setState(() => _opening = player.riotId);
    final query = PlayerQuery(game: Game.valorant, name: player.name, tag: tag, platform: 'pc', region: widget.region);
    try {
      final summary = await query.run(AppScope.of(context).api);
      if (!mounted) return;
      AppScope.of(context).addRecentSearch(query.withDisplayName(summary.name));
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(query: query.withDisplayName(summary.name), initial: summary),
      ));
    } on TrackerApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detail ??= _load();
  }

  Future<MatchDetail> _load() => AppScope.of(context).api.valorantMatch(widget.match.matchId!, region: widget.region);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text((widget.match.map ?? 'Match').toUpperCase(), style: AppText.label(size: 14, color: AppColors.text)),
      ),
      body: FutureBuilder<MatchDetail>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return _Message(
              text: error is TrackerApiException ? error.message : "Couldn't load this match.",
              onRetry: () => setState(() => _detail = _load()),
            );
          }
          final detail = snapshot.data;
          if (detail == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
          return _Scoreboard(
            detail: detail,
            match: widget.match,
            playerName: widget.playerName,
            teamNames: widget.teamNames,
            teamLabel: widget.teamLabel,
            onOpen: _openPlayer,
            opening: _opening,
          );
        },
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({
    required this.detail,
    required this.match,
    required this.playerName,
    this.teamNames = const [],
    this.teamLabel,
    this.onOpen,
    this.opening,
  });

  final MatchDetail detail;
  final MatchEntry match;
  final String playerName;
  final List<String> teamNames;
  final String? teamLabel;
  final ValueChanged<MatchPlayer>? onOpen;
  final String? opening;

  @override
  Widget build(BuildContext context) {
    final ours = {playerName.toLowerCase(), for (final n in teamNames) n.toLowerCase()};
    final me = detail.players.where((p) => p.riotId.toLowerCase() == playerName.toLowerCase()).firstOrNull ??
        detail.players.where((p) => ours.contains(p.riotId.toLowerCase())).firstOrNull;
    final teams = [...detail.teams];
    // Your team first.
    if (me != null) teams.sort((a, b) => (a.id == me.team ? 0 : 1) - (b.id == me.team ? 0 : 1));
    final mine = teams.firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        _Header(detail: detail, match: match, team: mine),
        for (final (i, team) in teams.indexed) ...[
          SectionTitle(
            me == null
                ? 'Team ${team.id}'
                : i == 0
                    ? (teamLabel ?? 'Your Team')
                    : (teamLabel == null ? 'Enemy Team' : 'Opponents'),
            trailing: team.won == null
                ? null
                : Text(
                    team.won! ? 'WON' : 'LOST',
                    style: AppText.label(color: team.won! ? AppColors.gain : AppColors.loss),
                  ),
          ),
          _TeamCard(players: detail.teamPlayers(team.id), me: me, onOpen: onOpen, opening: opening),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail, required this.match, required this.team});

  final MatchDetail detail;
  final MatchEntry match;
  final MatchTeam? team;

  @override
  Widget build(BuildContext context) {
    final won = team?.won;
    final color = won == null ? AppColors.text : (won ? AppColors.gain : AppColors.loss);
    final facts = [
      detail.mode,
      if (detail.startedAt != null) matchDate(detail.startedAt!),
      if (detail.duration != null) '${detail.duration!.inMinutes} min',
    ].nonNulls.join('  ·  ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 170,
        color: AppColors.surface,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (detail.mapImage != null)
              Image.network(detail.mapImage!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x55000000), Color(0xCC000000)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text((detail.map ?? match.map ?? 'Match').toUpperCase(), style: AppText.label(color: Colors.white70)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        team?.roundsWon == null ? '—' : '${team!.roundsWon} – ${team!.roundsLost}',
                        style: AppText.display(40, color: color),
                      ),
                      const Spacer(),
                      if (!match.isAdjustment)
                        Text(
                          '${signed(match.delta)} ${Game.valorant.unit}',
                          style: AppText.display(20, color: AppColors.delta(match.delta)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(facts.toUpperCase(), style: AppText.label(color: Colors.white70, size: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.players, required this.me, this.onOpen, this.opening});

  final List<MatchPlayer> players;
  final MatchPlayer? me;
  final ValueChanged<MatchPlayer>? onOpen;
  final String? opening;

  @override
  Widget build(BuildContext context) {
    final header = AppText.label(color: AppColors.textFaint, size: 9);
    return TrackerCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Row(
              children: [
                Expanded(child: Text('PLAYER', style: header)),
                SizedBox(
                  width: _kdaWidth,
                  child: Text('K / D / A', style: header, textAlign: TextAlign.center),
                ),
                SizedBox(
                  width: _statWidth,
                  child: Text('ACS', style: header, textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          for (final p in players)
            _PlayerRow(
              player: p,
              isMe: identical(p, me),
              loading: opening == p.riotId,
              onTap: onOpen == null || (p.tag ?? '').isEmpty ? null : () => onOpen!(p),
            ),
        ],
      ),
    );
  }
}

const _kdaWidth = 76.0;
const _statWidth = 40.0;

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.player, required this.isMe, this.onTap, this.loading = false});

  final MatchPlayer player;
  final bool isMe;

  /// Opens their profile.
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final extra = [
      p.rank ?? 'Unrated',
      if (p.adr != null) '${p.adr} ADR',
      if (p.headshotPct != null) '${p.headshotPct}% HS',
    ].join('  ·  ');
    final row = Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: isMe ? AppColors.accent.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 36,
              height: 36,
              color: AppColors.surfaceHigh,
              child: p.agentIcon == null
                  ? const Icon(Icons.person_rounded, color: AppColors.textFaint, size: 20)
                  : Image.network(p.agentIcon!, errorBuilder: (_, _, _) => const SizedBox()),
            ),
          ),
          const SizedBox(width: 10),
          RankBadge(name: p.rank ?? '', imageUrl: p.rankIcon, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.riotId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: isMe ? AppColors.accent : AppColors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  extra.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label(color: AppColors.textFaint, size: 9),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _kdaWidth,
            child: Text(
              '${p.kills} / ${p.deaths} / ${p.assists}',
              textAlign: TextAlign.center,
              style: AppText.mono(size: 12),
            ),
          ),
          SizedBox(
            width: _statWidth,
            child: Text('${p.acs ?? '—'}', textAlign: TextAlign.right, style: AppText.display(15)),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: loading ? null : onTap,
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            row,
            if (loading)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textDim),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
