import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/ranks.dart';
import 'package:phamitracker/models/summary.dart';
import 'package:phamitracker/pages/games_page.dart';
import 'package:phamitracker/widgets/match_list.dart';
import 'package:phamitracker/widgets/rank_hero.dart';

MatchEntry _m(int hoursAgo, int delta, {String? map, String? character, int? k, int? d}) => MatchEntry(
      time: DateTime(2026, 11, 12, 20).subtract(Duration(hours: hoursAgo)),
      delta: delta,
      scoreAfter: 0,
      isAdjustment: false,
      map: map,
      character: character,
      kills: k,
      deaths: d,
    );

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: ListView(children: [child])));

void main() {
  testWidgets('next rank bar: Apex RP to the next division', (tester) async {
    await tester.pumpWidget(_app(NextRankBar(game: Game.apex, score: 7320, next: nextRank(Game.apex, 7320)!)));
    expect(find.text('7,320 / 7,750 RP'), findsOneWidget);
    expect(find.text('430 TO GOLD I'), findsOneWidget);
  });

  testWidgets('next rank bar: VALORANT RR within the division', (tester) async {
    // Diamond 2 with 62 RR: elo (tier 20 - 3) * 100 + 62.
    await tester.pumpWidget(_app(NextRankBar(game: Game.valorant, score: 1662, next: nextRank(Game.valorant, 1662)!)));
    expect(find.text('62 / 100 RR'), findsOneWidget);
    expect(find.text('38 TO DIAMOND 3'), findsOneWidget);
  });

  test('rank up and rank down come from the score before and after each game', () {
    MatchEntry g(int delta, int after, {bool adjust = false}) =>
        MatchEntry(time: DateTime(2026, 11, 20), delta: delta, scoreAfter: after, isAdjustment: adjust);
    // Apex: Gold II starts at 7,000, Gold I at 7,750.
    final up = rankChangeOf(Game.apex, g(90, 7790))!;
    expect([up.up, up.rank.label], [true, 'Gold I']);
    final down = rankChangeOf(Game.apex, g(-40, 7720))!;
    expect([down.up, down.rank.label], [false, 'Gold II']);
    expect(rankChangeOf(Game.apex, g(50, 7500)), isNull); // stays Gold II
    expect(rankChangeOf(Game.apex, g(-3000, 4000, adjust: true)), isNull); // season reset
    // VALORANT: 100 RR per division, Diamond 2 starts at 1,600 elo.
    final val = rankChangeOf(Game.valorant, g(21, 1611))!;
    expect([val.up, val.rank.label], [true, 'Diamond 2']);
  });

  testWidgets('a game that ranked up says so in the match list', (tester) async {
    await tester.pumpWidget(_app(MatchList(game: Game.apex, matches: [
      MatchEntry(time: DateTime(2026, 11, 20, 20), delta: 90, scoreAfter: 7790, isAdjustment: false, map: 'Olympus'),
      MatchEntry(time: DateTime(2026, 11, 20, 19), delta: 20, scoreAfter: 7700, isAdjustment: false, map: 'Olympus'),
    ])));
    expect(find.text('RANK UP · GOLD I'), findsOneWidget);
    expect(find.textContaining('RANK DOWN'), findsNothing);
  });

  test('no next rank at the top', () {
    expect(nextRank(Game.apex, 16_500), isNull);
    expect(nextRank(Game.valorant, 2450), isNull);
  });

  testWidgets('By Legend lists every legend, five visible and the rest a scroll away', (tester) async {
    final legends = ['Crypto', 'Lifeline', 'Mirage', 'Seer', 'Horizon', 'Pathfinder', 'Axle', 'Wraith'];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MapStatsCard(game: Game.apex, maps: [
          for (final (i, l) in legends.indexed) MapStat(map: l, matches: 50 - i, delta: 100, wins: 10),
        ]),
      ),
    ));
    final list = find.descendant(of: find.byType(MapStatsCard), matching: find.byType(Scrollable));
    expect(tester.getSize(list).height, MapStatsCard.rowHeight * 5);
    expect(find.text('WRAITH'), findsNothing);
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('WRAITH'), findsOneWidget);
  });

  testWidgets('tapping a By Map row opens every game on it', (tester) async {
    const stat = MapStat(map: 'Ascent', matches: 3, delta: 25, wins: 2, kills: 50, deaths: 40);
    final games = [
      _m(1, 20, map: 'Ascent', character: 'Jett', k: 20, d: 12),
      _m(5, -15, map: 'Ascent', character: 'Sova', k: 10, d: 16),
      _m(30, 20, map: 'Ascent', character: 'Jett', k: 20, d: 12),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: MapStatsCard(
            game: Game.valorant,
            maps: const [stat],
            onOpen: (s) => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GamesPage(game: Game.valorant, stat: s, byMap: true, subtitle: 'All', load: () async => games),
            )),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ASCENT'));
    await tester.pumpAndSettle();
    expect(find.text('Ascent'), findsOneWidget); // app bar
    expect(find.text('MAP  ·  ALL'), findsOneWidget);
    expect(find.text('+25 RR'), findsOneWidget);
    expect(find.text('Games · 3'), findsOneWidget);
    expect(find.text('1.25'), findsOneWidget); // K/D 50/40
    expect(find.text('JETT · ASCENT'), findsNWidgets(2));
    expect(find.text('SOVA · ASCENT'), findsOneWidget);
  });
}
