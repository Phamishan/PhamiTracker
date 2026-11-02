import 'package:flutter/material.dart';

import 'game.dart';

/// One step on a game's ladder, reached at [minScore] (Apex RP / VALORANT elo).
class RankStep {
  const RankStep(this.label, this.minScore);

  final String label;
  final int minScore;

  String get tier => label.split(' ').first;
}

const _apexDivisions = ['IV', 'III', 'II', 'I'];

/// Apex ranked thresholds (Season 17+ ladder). Predator is top-750, so it isn't an RP goal.
/// If Respawn reshuffles the ladder, this list is the only thing to update.
final List<RankStep> apexLadder = [
  for (final (tier, start, step) in const [
    ('Rookie', 0, 250),
    ('Bronze', 1000, 500),
    ('Silver', 3000, 600),
    ('Gold', 5400, 700),
    ('Platinum', 8200, 800),
    ('Diamond', 11400, 900),
  ])
    for (var i = 0; i < 4; i++) RankStep('$tier ${_apexDivisions[i]}', start + step * i),
  const RankStep('Master', 15000),
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
