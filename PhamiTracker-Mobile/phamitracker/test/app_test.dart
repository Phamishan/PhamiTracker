import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phamitracker/main.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/summary.dart';
import 'package:phamitracker/services/app_state.dart';
import 'package:phamitracker/services/changelog_service.dart';
import 'package:phamitracker/services/tracker_api.dart';
import 'package:phamitracker/widgets/match_list.dart';
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
      if (path == '/v1/search') {
        if (request.url.queryParameters['name'] != 'Rival') return http.Response('{"error":"Player not found"}', 404);
        return http.Response(
          jsonEncode({
            ...apexSummary(),
            'player': {'id': null, 'game': 'apex', 'name': 'Rival', 'platform': 'PC'},
            'rankLabel': 'Diamond III',
            'score': 13460,
            'matches': [],
            'history': [],
            'maps': [],
            'tracked': false,
          }),
          200,
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
    expect(find.text('SET A RANK GOAL'), findsOneWidget);
    expect(find.text('CURRENT RANK'), findsOneWidget);
    expect(find.text('Welcome back, Phami'), findsOneWidget);
    expect(find.text('IN MATCH · WRAITH'), findsOneWidget);
    expect(find.text('7D'), findsOneWidget);
    expect(find.text('Recent Matches · 2'), findsOneWidget);

    await tester.tap(find.text('VALORANT'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('TRACK YOUR VALORANT RANK'), findsOneWidget);

    // Unmount so the live-refresh timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  test('match dates', () {
    final now = DateTime(2026, 11, 3, 15);
    expect(matchDate(DateTime(2026, 11, 3, 13, 48), now: now), 'Today, 13:48');
    expect(matchDate(DateTime(2026, 11, 2, 21, 2), now: now), 'Yesterday, 21:02');
    expect(matchDate(DateTime(2026, 11, 1, 18, 30), now: now), 'Sun 1 Nov, 18:30');
    expect(matchDate(DateTime(2025, 12, 24, 9, 5), now: now), '24 Dec 2025, 09:05');
  });

  test('rotation end times are Danish 24-hour time', () {
    expect(danishClock(DateTime.utc(2026, 11, 4, 17, 30)), '18:30'); // CET, UTC+1
    expect(danishClock(DateTime.utc(2026, 7, 1, 21, 5)), '23:05'); // CEST, UTC+2
    // 2026 switches on 29 March and 25 October at 01:00 UTC.
    expect(danishClock(DateTime.utc(2026, 3, 29, 0, 59)), '01:59');
    expect(danishClock(DateTime.utc(2026, 3, 29, 1)), '03:00');
    expect(danishClock(DateTime.utc(2026, 10, 25, 0, 59)), '02:59');
    expect(danishClock(DateTime.utc(2026, 10, 25, 1)), '02:00');
  });

  testWidgets('searching a player opens their page without tracking them', (tester) async {
    final log = <String>[];
    final state = await makeState(prefs: {'game': 'apex'}, log: log);
    await tester.pumpWidget(PhamiTrackerApp(state: state));
    await tester.pump();
    // The rotation countdown ticks forever, so pump for fixed times instead of settling.
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.byTooltip('Search player'));
    await settle();
    await tester.enterText(find.byType(TextField).first, 'Nobody');
    await tester.tap(find.text('SEARCH'));
    await settle();
    expect(find.textContaining("Couldn't find that player"), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Rival');
    await tester.tap(find.text('SEARCH'));
    await settle();
    expect(find.text('DIAMOND III'), findsOneWidget);
    expect(find.text('13,460 RP'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining("Apex doesn't share match history"), 200);
    expect(find.textContaining("Apex doesn't share match history"), findsOneWidget);
    expect(log.where((l) => l.startsWith('POST')), isEmpty);
    expect(state.accounts, isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('match list shows five rows and scrolls to the rest', (tester) async {
    final matches = [
      for (var i = 0; i < 12; i++)
        MatchEntry(time: DateTime(2026, 11, 3, 12).subtract(Duration(hours: i)), delta: i.isEven ? 20 : -15, scoreAfter: 1000, isAdjustment: false, map: 'Map $i'),
    ];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MatchList(game: Game.apex, matches: matches)))));
    expect(tester.getSize(find.byType(MatchList)).height, closeTo(MatchList.rowHeight * 5 + 8, 2));
    expect(find.text('MAP 11'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('MAP 11'), findsOneWidget);
  });

  test('changelog parses the README version history, newest first', () {
    const readme = '''
# PhamiTracker

## Features:

```
🪂 - Apex Legends tracking
```

## Version History

- 1.0.0 - 02/11/2026
  - Initial Release
- 1.0.1 - 03/11/2026
  - Added a Climb widget
  - New app icon
''';
    final entries = ChangelogService.parse(readme);
    expect(entries.map((e) => e.version), ['1.0.1', '1.0.0']);
    expect(entries.first.date, '03/11/2026');
    expect(entries.first.changes, ['Added a Climb widget', 'New app icon']);
  });
}
