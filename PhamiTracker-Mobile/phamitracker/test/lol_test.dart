import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/ranks.dart';
import 'package:phamitracker/models/summary.dart';
import 'package:phamitracker/pages/home_page.dart';
import 'package:phamitracker/pages/match_page.dart';
import 'package:phamitracker/pages/search_page.dart';
import 'package:phamitracker/services/app_state.dart';
import 'package:phamitracker/services/tracker_api.dart';
import 'package:phamitracker/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> _state(Future<http.Response> Function(http.Request r) handler) async {
  SharedPreferences.setMockInitialValues({});
  return AppState(
    api: TrackerApi(const TrackerConfig(baseUrl: 'https://t.test', appKey: 'k'), client: MockClient(handler)),
    prefs: await SharedPreferences.getInstance(),
  );
}

void main() {
  test('LOL is a third game with its own wording', () {
    expect(Game.values, contains(Game.lol));
    expect(Game.lol.title, 'LOL');
    expect(Game.lol.unit, 'LP');
    expect(Game.lol.characterNoun, 'Champion');
    expect(Game.lol.mapNoun, 'Role');
    expect(Game.lol.platformLabel, 'Queue');
    expect(Game.lol.platforms, {'solo': 'Solo/Duo', 'flex': 'Flex'});
    expect(Game.lol.regions!.keys.first, 'euw1');
    expect(Game.lol.defaultRegion('DK'), 'euw1');
    expect(Game.lol.defaultRegion('US'), 'na1');
    expect(Game.lol.hasWins, isTrue);
    expect(Game.fromId('lol'), Game.lol);
  });

  test('LOL ranks: 100 per division, Master on LP (same scale as the worker)', () {
    expect(rankAt(Game.lol, 1450).label, 'Gold II'); // Gold II 50 LP
    expect(scoreText(Game.lol, 1450), 'Gold II · 50 LP');
    expect(rankAt(Game.lol, 2375).label, 'Emerald I'); // Pray: Emerald I 75 LP
    expect(nextRank(Game.lol, 2375)!.label, 'Diamond IV');
    expect(scoreText(Game.lol, 2920), 'Master · 120 LP');
    expect(nextRank(Game.lol, 2920), isNull);
    expect(goalIconUrl(Game.lol, 2400), endsWith('emblem-diamond.png'));
  });

  testWidgets('searching LOL: Riot ID, queue and server (EUW first)', (tester) async {
    // A Danish phone: the server starts on EUW (a US one starts on NA).
    tester.platformDispatcher.localeTestValue = const Locale('da', 'DK');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final asked = <Uri>[];
    final state = await _state((r) async {
      asked.add(r.url);
      if (r.url.path == '/v1/search') {
        return http.Response(jsonEncode({
          'player': {'id': null, 'game': 'lol', 'name': 'Pray', 'tag': '1551', 'region': 'euw1', 'platform': 'solo'},
          'score': 2375,
          'rankLabel': 'Emerald I',
          'rank': {'name': 'Emerald I'},
          'today': {'delta': 0},
          'matches': [],
          'tracked': false,
        }), 200);
      }
      return http.Response('{}', 200);
    });
    await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: SearchPage(initialGame: Game.lol))));
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Premier team'), findsNothing);
    await tester.tap(find.text('Flex'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Pray#1551');
    await tester.ensureVisible(find.byType(GradientButton));
    await tester.tap(find.byType(GradientButton));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final search = asked.firstWhere((u) => u.path == '/v1/search').queryParameters;
    expect(search, containsPair('game', 'lol'));
    expect(search, containsPair('name', 'Pray'));
    expect(search, containsPair('tag', '1551'));
    expect(search, containsPair('platform', 'flex'));
    expect(search, containsPair('region', 'euw1'));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(find.text('75 LP'), findsOneWidget); // LP within Emerald I
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a LOL scoreboard: champions, roles, CS and damage', (tester) async {
    final state = await _state((r) async {
      expect(r.url.path, '/v1/lol/matches/EUW1_8041163108');
      expect(r.url.queryParameters['server'], 'euw1');
      return http.Response(jsonEncode({
        'map': "Summoner's Rift",
        'mode': 'Ranked Flex',
        'teams': [
          {'id': 'Blue', 'won': false, 'roundsWon': 20, 'roundsLost': 24},
          {'id': 'Red', 'won': true, 'roundsWon': 24, 'roundsLost': 20},
        ],
        'players': [
          {'name': 'Pray', 'tag': '1551', 'team': 'Red', 'agent': 'Tristana', 'role': 'Mid', 'kills': 7, 'deaths': 2, 'assists': 5, 'cs': 186, 'damage': 24300},
          {'name': 'michaelsen207', 'tag': '207', 'team': 'Blue', 'agent': 'Vladimir', 'role': 'Top', 'kills': 3, 'deaths': 5, 'assists': 2, 'cs': 170, 'damage': 15100},
        ],
      }), 200);
    });
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
        home: MatchPage(
          game: Game.lol,
          match: MatchEntry(time: DateTime(2026, 11, 9, 19), delta: 22, scoreAfter: 2192, isAdjustment: false, matchId: 'EUW1_8041163108'),
          region: 'euw1',
          playerName: 'Pray#1551',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('CS'), findsWidgets);
    expect(find.text('186'), findsOneWidget);
    expect(find.text('MID  ·  24.3K DMG'), findsOneWidget);
    expect(find.text('Your Team'), findsOneWidget);
  });
}
