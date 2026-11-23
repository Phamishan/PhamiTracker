import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/player_query.dart';
import '../models/premier.dart';
import '../models/summary.dart';
import '../services/tracker_api.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/insight_cards.dart';
import '../widgets/match_list.dart';
import 'match_page.dart';
import 'search_page.dart';

/// A VALORANT Premier team, like PhamiBot's /premierteam: division and points to the playoffs,
/// record, conference place, league matches (tap for the scoreboard) and the roster.
class PremierPage extends StatefulWidget {
  const PremierPage({super.key, required this.team});

  final PremierTeam team;

  @override
  State<PremierPage> createState() => _PremierPageState();
}

class _PremierPageState extends State<PremierPage> {
  late PremierTeam _team = widget.team;
  String? _opening;

  Future<void> _refresh() async {
    try {
      final team = await AppScope.of(context).api.premierTeam(name: _team.name, tag: _team.tag);
      if (mounted) setState(() => _team = team);
    } on TrackerApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// A roster member's player page (looked up like a search).
  Future<void> _openMember(PremierMember member) async {
    if (_opening != null) return;
    setState(() => _opening = member.riotId);
    final query = PlayerQuery(game: Game.valorant, name: member.name, tag: member.tag, platform: 'pc', region: _team.region);
    try {
      final summary = await query.run(AppScope.of(context).api);
      if (!mounted) return;
      AppScope.of(context).addRecentSearch(query.withDisplayName(summary.name));
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerPage(query: query.withDisplayName(summary.name), initial: summary),
        ),
      );
    } on TrackerApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  void _openMatch(PremierMatch match) {
    if (match.id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MatchPage(
          match: MatchEntry(
            time: match.startedAt ?? DateTime.now(),
            delta: match.delta,
            scoreAfter: match.pointsAfter,
            isAdjustment: false,
            matchId: match.id,
            won: match.won,
          ),
          region: _team.region,
          playerName: _team.members.firstOrNull?.riotId ?? '',
          teamNames: [for (final m in _team.members) m.riotId],
          teamLabel: _team.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final team = _team;
    final color = team.primary ?? Game.valorant.glow;
    return Scaffold(
      appBar: AppBar(title: Text(team.label)),
      body: RefreshIndicator(
        color: color,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
          children: [
            _TeamHeader(team: team, color: color),
            const SizedBox(height: 12),
            TrackerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DIVISION', style: AppText.label(color: AppColors.textFaint)),
                  const SizedBox(height: 4),
                  Text((team.division ?? 'Not placed').toUpperCase(), style: AppText.display(24)),
                  const SizedBox(height: 12),
                  ProgressBar(value: team.points / team.pointsGoal, color: color, height: 8),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('${team.points} / ${team.pointsGoal} POINTS', style: AppText.mono(size: 12, color: AppColors.textDim)),
                      const Spacer(),
                      if (team.points < team.pointsGoal)
                        Text('${team.pointsGoal - team.points} TO PLAYOFFS', style: AppText.label(size: 9, color: AppColors.textFaint))
                      else
                        Text('PLAYOFFS', style: AppText.label(size: 9, color: AppColors.gain)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FactGrid(columns: 3, [
                    Fact('Record', '${team.wins}W ${team.losses}L'),
                    Fact('Win rate', team.winRate == null ? '—' : '${team.winRate}%'),
                    Fact('Place', team.place == null ? '—' : '#${team.place}'),
                  ]),
                  if (team.conference != null) ...[
                    const SizedBox(height: 10),
                    Text(team.conference!.toUpperCase(), style: AppText.label(size: 10, color: AppColors.textFaint)),
                  ],
                ],
              ),
            ),
            SectionTitle(team.matches.isEmpty ? 'League Matches' : 'League Matches · ${team.matches.length}'),
            if (team.matches.isEmpty)
              const TrackerCard(
                child: Text('No league matches yet.', style: TextStyle(color: AppColors.textDim)),
              )
            else
              TrackerCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final (i, m) in team.matches.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18, color: AppColors.border),
                      _MatchRow(match: m, onTap: m.id == null ? null : () => _openMatch(m)),
                    ],
                  ],
                ),
              ),
            if (team.members.isNotEmpty) ...[
              SectionTitle('Roster · ${team.members.length}'),
              TrackerCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                // The rows' tap ripple paints on this, not behind the card's background.
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (final (i, m) in team.members.indexed) ...[
                        if (i > 0) const Divider(height: 1, indent: 18, endIndent: 18, color: AppColors.border),
                        ListTile(
                          onTap: () => _openMember(m),
                          title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('#${m.tag}'.toUpperCase(), style: AppText.label(size: 9, color: AppColors.textFaint)),
                          trailing: _opening == m.riotId
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The team's banner art with its name over it, in its own colour.
class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.team, required this.color});

  final PremierTeam team;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 150,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.55), AppColors.surface],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (team.image != null) Image.network(team.image!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black87],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Positioned(
              left: 18,
              right: 18,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PREMIER', style: AppText.label(color: color)),
                  const SizedBox(height: 2),
                  Text(
                    team.label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.display(26, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, this.onTap});

  final PremierMatch match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = match.won == null ? AppColors.textDim : (match.won! ? AppColors.gain : AppColors.loss);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: MatchList.rowHeight - 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  match.won == null ? Icons.remove_rounded : (match.won! ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
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
                    Text(
                      (match.won == null
                              ? 'No result'
                              : match.won!
                              ? 'Win'
                              : 'Loss')
                          .toUpperCase(),
                      style: AppText.display(15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [if (match.startedAt != null) matchDate(match.startedAt!), '${match.pointsAfter} points'].join('  ·  ').toUpperCase(),
                      style: AppText.label(size: 10),
                    ),
                  ],
                ),
              ),
              Text('${signed(match.delta)} PTS', style: AppText.display(17, color: color)),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textFaint, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
