import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/game.dart';
import '../models/ranks.dart';
import '../models/summary.dart';
import '../theme/app_theme.dart';
import 'common.dart';

final _number = NumberFormat.decimalPattern();

/// The big gradient card at the top: who, what rank, how many points, and whether they're live.
class RankHero extends StatelessWidget {
  const RankHero({super.key, required this.game, required this.summary, required this.accountName});

  final Game game;
  final PlayerSummary? summary;
  final String accountName;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final rankName = s?.rankLabel ?? s?.rank.name ?? '—';
    final color = rankColor(s?.rank.name ?? rankName);
    final live = s != null && (s.status.inGame || s.status.online);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: game.linearGradient,
        boxShadow: [BoxShadow(color: game.glow.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 16))],
      ),
      child: Stack(
        children: [
          // Big faded game glyph for texture.
          Positioned(
            right: -30,
            top: -30,
            child: Icon(game.icon, size: 190, color: Colors.white.withValues(alpha: 0.10)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        accountName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                      ),
                    ),
                    _StatusPill(status: s?.status, live: live),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _RankBadge(color: color, imageUrl: s?.rank.image, label: rankName),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              rankName,
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                height: 1.05,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _scoreLine(s),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.88),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (s?.rank.ladderPos != null) _Tag(Icons.leaderboard_rounded, '#${_number.format(s!.rank.ladderPos)}'),
                    if (s?.rank.peak != null) _Tag(Icons.trending_up_rounded, 'Peak ${s!.rank.peak}'),
                    if (s?.level != null) _Tag(Icons.star_rounded, 'Level ${s!.level}'),
                    if ((s?.rank.gamesNeeded ?? 0) > 0) _Tag(Icons.hourglass_bottom_rounded, '${s!.rank.gamesNeeded} placements left'),
                    _Tag(Icons.sync_rounded, 'Updated ${timeAgo(s?.polledAt)}'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _scoreLine(PlayerSummary? s) {
    if (s?.score == null) return 'Fetching rank…';
    if (game == Game.valorant) {
      return '${s!.rank.rr ?? 0} RR  ·  ${_number.format(s.score)} elo';
    }
    final next = nextRank(game, s!.score!);
    final line = '${_number.format(s.score)} RP';
    return next == null ? line : '$line  ·  ${_number.format(next.minScore - s.score!)} to ${next.label}';
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.color, required this.imageUrl, required this.label});

  final Color color;
  final String? imageUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        label.isEmpty ? '?' : label[0],
        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: color),
      ),
    );
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.28),
        border: Border.all(color: color, width: 3),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 22)],
      ),
      padding: const EdgeInsets.all(8),
      child: imageUrl == null
          ? fallback
          : Image.network(imageUrl!, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.live});

  final PlayerStatus? status;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      PlayerStatus(inGame: true, :final legend) => legend == null ? 'In match' : 'In match · $legend',
      PlayerStatus(online: true, :final text) => text ?? 'Online',
      _ => 'Live tracking',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.28), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiveDot(color: live ? AppColors.live : Colors.white70, size: 7),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}
