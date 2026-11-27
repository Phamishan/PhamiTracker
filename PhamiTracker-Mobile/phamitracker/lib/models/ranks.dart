import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

/// LOL: 100 per division from Iron IV (the worker's lolScore), Master and above on LP from 2,800.
/// Grandmaster and Challenger depend on the server's ladder, so Master is the top step.
final List<RankStep> lolLadder = [
  for (final (i, tier) in const ['Iron', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Emerald', 'Diamond'].indexed)
    for (final (d, division) in const ['IV', 'III', 'II', 'I'].indexed) RankStep('$tier $division', (i * 4 + d) * 100),
  const RankStep('Master', 2800),
];

List<RankStep> ladderFor(Game game) => switch (game) { Game.apex => apexLadder, Game.valorant => valorantLadder, Game.lol => lolLadder };

/// A score in the game's own terms: "8,852 RP", "2,000 elo", or LOL's "Gold II · 50 LP".
String scoreText(Game game, int score) {
  final formatted = NumberFormat.decimalPattern().format(score);
  return switch (game) {
    Game.apex => '$formatted RP',
    Game.valorant => '$formatted elo',
    Game.lol => '${rankAt(game, score).label} · ${score - rankAt(game, score).minScore} LP',
  };
}

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
  'emerald': Color(0xFF2ED47A),
  'grandmaster': Color(0xFFFF5C5C),
  'challenger': Color(0xFFF4C874),
};

/// Accent colour for any rank name the APIs return ("Diamond 2", "Apex Predator", ...).
Color rankColor(String? rankName) {
  final tier = (rankName ?? '').trim().split(' ').first.toLowerCase();
  return _tierColors[tier] ?? const Color(0xFF9AA3B5);
}

/// Label of the Apex goal that follows the live Predator cutoff.
const apexPredatorGoal = 'Apex Predator';

/// Rank art for a goal: the rank its target score lands in (so custom RP goals get an icon too).
String? goalIconUrl(Game game, int targetScore, {String? label}) {
  if (game == Game.apex && label == apexPredatorGoal) return 'https://api.mozambiquehe.re/assets/ranks/apexpredator1.png';
  if (game == Game.valorant) return valorantTierIcon((targetScore ~/ 100 + 3).clamp(3, 27));
  if (game == Game.lol) {
    final tier = rankAt(game, targetScore).label.split(' ').first.toLowerCase();
    return 'https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/images/ranked-emblem/emblem-$tier.png';
  }
  // Apex art is named like "diamond3.png" / "master.png" on apexlegendsapi.com.
  final [tier, ...division] = rankAt(game, targetScore).label.split(' ');
  final number = division.isEmpty ? '' : '${const {'IV': 4, 'III': 3, 'II': 2, 'I': 1}[division.first]}';
  return 'https://api.mozambiquehe.re/assets/ranks/${tier.toLowerCase()}$number.png';
}
