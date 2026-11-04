import 'package:flutter/material.dart';

import 'game.dart';
import 'summary.dart' show valorantTierIcon;

/// One step on a game's ladder, reached at [minScore] (Apex RP / VALORANT elo).
class RankStep {
  const RankStep(this.label, this.minScore);

  final String label;
  final int minScore;

  String get tier => label.split(' ').first;
}

/// Apex ranked floors, Season 31 (Master at 16,000 RP; matches what other trackers show).
/// Predator is the top 750 per platform, not an RP number, so it isn't a goal step.
/// Respawn changes these between seasons; this list is the only thing to update.
const List<RankStep> apexLadder = [
  RankStep('Rookie IV', 0),
  RankStep('Rookie III', 250),
  RankStep('Rookie II', 500),
  RankStep('Rookie I', 750),
  RankStep('Bronze IV', 1000),
  RankStep('Bronze III', 1500),
  RankStep('Bronze II', 2000),
  RankStep('Bronze I', 2500),
  RankStep('Silver IV', 3000),
  RankStep('Silver III', 3500),
  RankStep('Silver II', 4000),
  RankStep('Silver I', 4750),
  RankStep('Gold IV', 5500),
  RankStep('Gold III', 6250),
  RankStep('Gold II', 7000),
  RankStep('Gold I', 7750),
  RankStep('Platinum IV', 8500),
  RankStep('Platinum III', 9250),
  RankStep('Platinum II', 10000),
  RankStep('Platinum I', 11000),
  RankStep('Diamond IV', 12000),
  RankStep('Diamond III', 13000),
  RankStep('Diamond II', 14000),
  RankStep('Diamond I', 15000),
  RankStep('Master', 16000),
];

/// VALORANT: 100 RR per division, so elo = (tier - 3) * 100 + RR. Iron 1 is tier 3.
final List<RankStep> valorantLadder = [
  for (final (i, tier) in const [
    'Iron', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Ascendant', 'Immortal',
  ].indexed)
    for (var div = 1; div <= 3; div++) RankStep('$tier $div', (i * 3 + div - 1) * 100),
  const RankStep('Radiant', 2400),
];

List<RankStep> ladderFor(Game game) => game == Game.apex ? apexLadder : valorantLadder;

/// The highest step at or below [score].
RankStep rankAt(Game game, int score) =>
    ladderFor(game).lastWhere((r) => r.minScore <= score, orElse: () => ladderFor(game).first);

/// The next step above [score], or null at the top of the ladder.
RankStep? nextRank(Game game, int score) {
  for (final step in ladderFor(game)) {
    if (step.minScore > score) return step;
  }
  return null;
}

const _tierColors = {
  'rookie': Color(0xFF9AA3B5),
  'iron': Color(0xFF8C8C99),
  'bronze': Color(0xFFE08A4F),
  'silver': Color(0xFFCAD6EA),
  'gold': Color(0xFFFFC93C),
  'platinum': Color(0xFF34E0D2),
  'diamond': Color(0xFF5B8CFF),
  'ascendant': Color(0xFF2EE59D),
  'master': Color(0xFFC04DFF),
  'immortal': Color(0xFFFF4D6D),
  'apex': Color(0xFFFF2E4D), // "Apex Predator"
  'predator': Color(0xFFFF2E4D),
  'radiant': Color(0xFFFFE27A),
};

/// Accent colour for any rank name the APIs return ("Diamond 2", "Apex Predator", ...).
Color rankColor(String? rankName) {
  final tier = (rankName ?? '').trim().split(' ').first.toLowerCase();
  return _tierColors[tier] ?? const Color(0xFF9AA3B5);
}

/// Rank art for a goal: the rank its target score lands in (so custom RP goals get an icon too).
String? goalIconUrl(Game game, int targetScore) {
  if (game == Game.valorant) return valorantTierIcon((targetScore ~/ 100 + 3).clamp(3, 27));
  // Apex art is named like "diamond3.png" / "master.png" on apexlegendsapi.com.
  final [tier, ...division] = rankAt(game, targetScore).label.split(' ');
  final number = division.isEmpty ? '' : '${const {'IV': 4, 'III': 3, 'II': 2, 'I': 1}[division.first]}';
  return 'https://api.mozambiquehe.re/assets/ranks/${tier.toLowerCase()}$number.png';
}
