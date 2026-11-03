import 'package:flutter_test/flutter_test.dart';
import 'package:phamitracker/models/account.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/ranks.dart';
import 'package:phamitracker/models/summary.dart';

void main() {
  test('apex ladder', () {
    expect(apexLadder.first.label, 'Rookie IV');
    expect(apexLadder.last.label, 'Master');
    expect(rankAt(Game.apex, 11400).label, 'Diamond IV');
    expect(rankAt(Game.apex, 11399).label, 'Platinum I');
    expect(nextRank(Game.apex, 11400)?.label, 'Diamond III');
    expect(nextRank(Game.apex, 20000), isNull);
  });

  test('valorant ladder matches elo = (tier - 3) * 100', () {
    expect(valorantLadder.first, isA<RankStep>().having((r) => r.minScore, 'minScore', 0));
    // Diamond 1 is tier 18.
    expect(rankAt(Game.valorant, (18 - 3) * 100 + 42).label, 'Diamond 1');
    expect(rankAt(Game.valorant, 2100).label, 'Immortal 1');
    expect(rankAt(Game.valorant, 2600).label, 'Radiant');
  });

  test('rank colours accept API names', () {
    expect(rankColor('Apex Predator'), rankColor('Predator'));
    expect(rankColor('Diamond 2'), rankColor('Diamond IV'));
  });

  test('goal progress counts from where the goal was set', () {
    const goal = RankGoal(label: 'Diamond IV', targetScore: 11400, startScore: 10400);
    expect(goal.progress(10400), 0);
    expect(goal.progress(10900), 0.5);
    expect(goal.progress(12000), 1);
    expect(goal.progress(9000), 0);
    expect(goal.remaining(10900), 500);
    expect(goal.remaining(12000), 0);
  });

  test('split pace is what you need per day to make the goal before the reset', () {
    final now = DateTime.utc(2026, 10, 12, 18);
    final season = SeasonInfo(name: 'Season 30 · Marked', split: 2, splitEnd: DateTime.utc(2026, 11, 3, 18));
    expect(season.goalPace(2540, 'RP', now: now), 'Split ends in 22d · ~116 RP/day');
    expect(season.goalPace(0, 'RP', now: now), 'Split ends in 22d');
    expect(season.goalPace(300, 'RP', now: DateTime.utc(2026, 11, 3, 8)), 'Split ends in 10h · ~300 RP/day');
    expect(season.goalPace(300, 'RP', now: DateTime.utc(2026, 11, 4)), isNull);
  });
}
