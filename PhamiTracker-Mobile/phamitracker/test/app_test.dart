import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phamitracker/main.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/summary.dart';
import 'package:phamitracker/services/app_state.dart';
import 'package:phamitracker/services/tracker_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> apexSummary() => {
      'player': {'id': 'apex-1', 'game': 'apex', 'name': 'Phami', 'tag': null, 'platform': 'PC'},
      'score': 10900,
      'rankLabel': 'Platinum I',
      'rank': {'name': 'Platinum', 'div': 1},
      'status': {'online': true, 'inGame': true, 'legend': 'Wraith'},
      'today': {'delta': 184, 'matches': 3, 'wins': 2, 'losses': 1, 'best': 141, 'worst': -35, 'series': [78, 43, 184]},
      'history': [
        {'day': '2026-11-01', 'score': 10716, 'delta': 0, 'matches': 0},
        {'day': '2026-11-02', 'score': 10900, 'delta': 184, 'matches': 3},
      ],
      'maps': [
        {'map': 'Olympus', 'matches': 3, 'delta': 184, 'wins': 2},
      ],
      'matches': [
        {'ts': _now - 60000, 'delta': 141, 'scoreAfter': 10900, 'kind': 'match', 'legend': 'Wraith', 'map': 'Olympus'},
        {'ts': _now - 3600000, 'delta': -35, 'scoreAfter': 10759, 'kind': 'match', 'legend': 'Wraith', 'map': 'Olympus'},
      ],
      'polledAt': _now - 20000,
      'serverTime': _now,
    };

http.Client fakeWorker({List<String>? log}) => MockClient((request) async {
      log?.add('${request.method} ${request.url.path}');
      if (request.headers['x-app-key'] != 'test-key') return http.Response('{"error":"Bad app key"}', 401);
      final path = request.url.path;
      if (path == '/v1/apex/maps') {
        return http.Response(
          jsonEncode({
            'ranked': {
              'current': {'map': 'Olympus', 'end': _now + 3600000},
              'next': {'map': 'Storm Point'},
            },
          }),
          200,
        );
      }
      if (path == '/v1/players' && request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'player': {'id': '${body['game']}-1', 'game': body['game'], 'name': body['name'], 'tag': body['tag']},
          }),
          201,
        );
      }
      if (path == '/v1/players/apex-1') return http.Response(jsonEncode(apexSummary()), 200);
      return http.Response('{"error":"Unknown player"}', 404);
    });

Future<AppState> makeState({Map<String, Object> prefs = const {}, List<String>? log}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState(
    api: TrackerApi(const TrackerConfig(baseUrl: 'https://tracker.test', appKey: 'test-key'), client: fakeWorker(log: log)),
    prefs: await SharedPreferences.getInstance(),
  );
}

void main() {
  test('summary parsing', () {
    final s = PlayerSummary.fromJson(apexSummary());
    expect(s.game, Game.apex);
    expect(s.today.delta, 184);
    expect(s.matches.first.character, 'Wraith');
    expect(s.history.last.score, 10900);
    expect(s.status.inGame, isTrue);
  });

  test('linking an account selects its game and loads the summary', () async {
    final log = <String>[];
    final state = await makeState(log: log);
    await state.link(game: Game.apex, name: 'Phami', platform: 'PC');
    expect(state.game, Game.apex);
    expect(state.account?.playerId, 'apex-1');
    expect(state.summary?.score, 10900);
    expect(log, contains('GET /v1/players/apex-1'));
  });

  test('a goal starts from the current score', () async {
    final state = await makeState();
    await state.link(game: Game.apex, name: 'Phami', platform: 'PC');
    await state.setGoal(Game.apex, label: 'Diamond IV', targetScore: 11400);
    expect(state.goal?.startScore, 10900);
    expect(state.goal?.progress(10900), 0);
  });

  testWidgets('dashboard shows rank, today and goal; switching game shows link prompt', (tester) async {
    final state = await makeState(prefs: {
      'game': 'apex',
      'account.apex': jsonEncode({'playerId': 'apex-1', 'game': 'apex', 'name': 'Phami', 'platform': 'PC'}),
    });
    await tester.pumpWidget(PhamiTrackerApp(state: state));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('PLATINUM I'), findsOneWidget);
    expect(find.text('10,900 RP'), findsOneWidget);
    // Rank card's today line, Today tile, the chart's total and the Olympus row.
    expect(find.textContaining('+184', findRichText: true), findsNWidgets(4));
    expect(find.text('SET A GOAL'), findsOneWidget);
    expect(find.text('IN MATCH · WRAITH'), findsOneWidget);
    expect(find.text('2W'), findsOneWidget);

    await tester.tap(find.text('VALORANT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('TRACK YOUR VALORANT RANK'), findsOneWidget);

    // Unmount so the live-refresh timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });
}
