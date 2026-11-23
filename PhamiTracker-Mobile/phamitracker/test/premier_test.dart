import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/premier.dart';
import 'package:phamitracker/models/summary.dart';
import 'package:phamitracker/pages/match_page.dart';
import 'package:phamitracker/pages/home_page.dart';
import 'package:phamitracker/pages/search_page.dart';
import 'package:phamitracker/services/app_state.dart';
import 'package:phamitracker/services/tracker_api.dart';
import 'package:phamitracker/widgets/common.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _team = {
  'name': 'PlaceHoldia',
  'tag': 'PLH',
  'division': 'Intermediate 3',
  'points': 300,
  'pointsGoal': 600,
  'place': 12,
  'conference': 'EU Central East',
  'region': 'eu',
  'wins': 2,
  'losses': 1,
  'colors': {'primary': '#ff4655'},
  'members': [
    {'name': 'Phami', 'tag': 'EUW'},
    {'name': 'meeji', 'tag': 'real'},
  ],
  'matches': [
    {'id': 'm1', 'startedAt': DateTime(2026, 11, 20, 20).millisecondsSinceEpoch, 'delta': 100, 'pointsAfter': 300, 'result': 'win'},
    {'id': 'm2', 'startedAt': DateTime(2026, 11, 18, 20).millisecondsSinceEpoch, 'delta': 25, 'pointsAfter': 200, 'result': 'loss'},
  ],
};

void main() {
  test('team colour and results parse', () {
    final team = PremierTeam.fromJson(jsonDecode(jsonEncode(_team)) as Map<String, dynamic>);
    expect(team.primary, const Color(0xFFFF4655));
    expect(team.winRate, 67);
    expect(team.matches.map((m) => m.won), [true, false]);
    expect(parseHexColor('nope'), isNull);
  });

  testWidgets('VALORANT search finds a Premier team and opens its page', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final asked = <Uri>[];
    final state = AppState(
      api: TrackerApi(
        const TrackerConfig(baseUrl: 'https://t.test', appKey: 'k'),
        client: MockClient((r) async {
          asked.add(r.url);
          return r.url.path == '/v1/premier' ? http.Response(jsonEncode(_team), 200) : http.Response('{}', 200);
        }),
      ),
      prefs: await SharedPreferences.getInstance(),
    );
    await tester.pumpWidget(AppScope(state: state, child: const MaterialApp(home: SearchPage(initialGame: Game.valorant))));
    await tester.tap(find.text('PREMIER TEAM'));
    await tester.pump();
    expect(find.text('Team name'), findsOneWidget);
    expect(find.text('Region'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'PlaceHoldia#PLH');
    await tester.ensureVisible(find.byType(GradientButton));
    await tester.tap(find.byType(GradientButton));
    await tester.pumpAndSettle();

    final lookup = asked.firstWhere((u) => u.path == '/v1/premier');
    expect(lookup.queryParameters, {'name': 'PlaceHoldia', 'tag': 'PLH'});
    expect(find.text('PLACEHOLDIA#PLH'), findsOneWidget);
    expect(find.text('INTERMEDIATE 3'), findsOneWidget);
    expect(find.text('300 / 600 POINTS'), findsOneWidget);
    expect(find.text('300 TO PLAYOFFS'), findsOneWidget);
    expect(find.text('2W 1L'), findsOneWidget);
    expect(find.text('#12'), findsOneWidget);
    expect(find.text('+100 PTS'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('meeji'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('meeji'), findsOneWidget);
  });

  testWidgets('every player in a scoreboard opens their profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final searched = <Map<String, String>>[];
    final state = AppState(
      api: TrackerApi(
        const TrackerConfig(baseUrl: 'https://t.test', appKey: 'k'),
        client: MockClient((r) async {
          if (r.url.path.startsWith('/v1/valorant/matches/')) {
            return http.Response(jsonEncode({
              'map': 'Ascent',
              'teams': [
                {'id': 'Red', 'won': true, 'roundsWon': 13, 'roundsLost': 7},
                {'id': 'Blue', 'won': false, 'roundsWon': 7, 'roundsLost': 13},
              ],
              'players': [
                {'name': 'Phami', 'tag': 'EUW', 'team': 'Red', 'kills': 25, 'deaths': 10, 'assists': 3},
                {'name': 'Enemy', 'tag': '1', 'team': 'Blue', 'kills': 8, 'deaths': 15, 'assists': 9},
              ],
            }), 200);
          }
          if (r.url.path == '/v1/search') {
            searched.add(r.url.queryParameters);
            return http.Response(jsonEncode({
              'player': {'id': null, 'game': 'valorant', 'name': 'Enemy', 'tag': '1', 'region': 'eu'},
              'score': 1100,
              'rankLabel': 'Gold 1',
              'rank': {'name': 'Gold 1'},
              'today': {'delta': 0},
              'matches': [],
              'tracked': false,
            }), 200);
          }
          return http.Response('{}', 200);
        }),
      ),
      prefs: await SharedPreferences.getInstance(),
    );
    await tester.pumpWidget(AppScope(
      state: state,
      child: MaterialApp(
        home: MatchPage(
          match: MatchEntry(time: DateTime(2026, 11, 23, 20), delta: 21, scoreAfter: 1542, isAdjustment: false, matchId: 'm-1', map: 'Ascent'),
          region: 'eu',
          playerName: 'Phami#EUW',
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enemy#1'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(searched.single, containsPair('name', 'Enemy'));
    expect(searched.single, containsPair('tag', '1'));
    expect(searched.single, containsPair('region', 'eu'));
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(state.recentSearches.first.name, 'Enemy');
    await tester.pumpWidget(const SizedBox());
  });
}
