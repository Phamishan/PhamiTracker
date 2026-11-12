import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/summary.dart';
import 'package:phamitracker/models/player_query.dart';
import 'package:phamitracker/pages/compare_page.dart';
import 'package:phamitracker/pages/search_page.dart';
import 'package:phamitracker/widgets/common.dart';
import 'package:phamitracker/services/app_state.dart';
import 'package:phamitracker/services/notification_service.dart';
import 'package:phamitracker/services/tracker_api.dart';
import 'package:phamitracker/services/widget_bridge.dart';
import 'package:phamitracker/widgets/celebration.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

Map<String, dynamic> _summary({
  String game = 'valorant',
  String name = 'Phami',
  int score = 1500,
  String rank = 'Diamond 1',
  int today = 0,
  List<Map<String, Object?>> matches = const [],
  List<Map<String, Object?>> characters = const [],
}) =>
    jsonDecode(jsonEncode({
      'player': {'id': '$game-1', 'game': game, 'name': name, 'tag': game == 'valorant' ? 'EUW' : null},
      'score': score,
      'rankLabel': rank,
      'rank': {'name': rank},
      'today': {'delta': today},
      'matches': matches,
      'characters': characters,
      'serverTime': _now,
    })) as Map<String, dynamic>;

Map<String, Object?> _game(int i, int delta, {int? k, int? d, int? a, bool? won}) => {
      'ts': _now - i * 600000,
      'delta': delta,
      'scoreAfter': 0,
      'kind': 'match',
      'kills': ?k,
      'deaths': ?d,
      'assists': ?a,
      'won': ?won,
    };

class _Notifications extends NotificationService {
  @override
  Future<String?> requestToken() async => 'ab' * 32;
}

void main() {
  test('head to head scores each row and leaves best agent unscored', () {
    final me = PlayerSummary.fromJson(_summary(
      score: 1542,
      today: 40,
      matches: [_game(0, 20, k: 20, d: 10, a: 5, won: true), _game(1, 20, k: 18, d: 12, a: 4, won: true), _game(2, -15, k: 10, d: 15, a: 3, won: false)],
      characters: [{'name': 'Jett', 'matches': 3, 'delta': 25, 'wins': 2}],
    ));
    final them = PlayerSummary.fromJson(_summary(
      name: 'Rival',
      score: 1600,
      today: -10,
      matches: [_game(0, -18, k: 9, d: 16, a: 2, won: false), _game(1, 22, k: 25, d: 8, a: 6, won: true)],
      characters: [{'name': 'Sova', 'matches': 2, 'delta': 4, 'wins': 1}],
    ));
    final rows = {for (final r in compareRows(me, them)) r.label: r};
    expect(rows['Rating (elo)']!.winner, -1);
    expect(rows['Today']!.winner, 1);
    expect(rows['Last 10 games']!.myText, '+25 RR');
    expect(rows['Wins · last 10']!.myText, '2/3');
    expect(rows['Current streak']!.myText, '2W');
    expect(rows['Current streak']!.theirText, '1L');
    expect(rows['Current streak']!.winner, 1);
    expect(rows['K/D']!.myText, '1.30');
    expect(rows['Best agent']!.winner, 0);
    expect(rows['Best agent']!.myText, 'Jett +25');
  });

  testWidgets('head to head page shows the running score', (tester) async {
    final me = PlayerSummary.fromJson(_summary(score: 1542, today: 40));
    final them = PlayerSummary.fromJson(_summary(name: 'Rival', score: 1600, today: -10));
    await tester.pumpWidget(MaterialApp(home: ComparePage(me: me, myName: 'Phami#EUW', them: them)));
    expect(find.text('1 – 1'), findsOneWidget);
    expect(find.text('DEAD EVEN'), findsOneWidget);
  });

  group('celebration', () {
    Future<AppState> state(List<Map<String, dynamic>> responses, {Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues({
        'game': 'apex',
        'account.apex': jsonEncode({'playerId': 'apex-1', 'game': 'apex', 'name': 'Phami', 'platform': 'PC'}),
        ...prefs,
      });
      var i = 0;
      return AppState(
        api: TrackerApi(
          const TrackerConfig(baseUrl: 'https://t.test', appKey: 'k'),
          client: MockClient((r) async => r.url.path.startsWith('/v1/players/')
              ? http.Response(jsonEncode(responses[i < responses.length - 1 ? i++ : i]), 200)
              : http.Response('{}', 200)),
        ),
        prefs: await SharedPreferences.getInstance(),
      );
    }

    test('rank up after the first load, not on it, not when dropping', () async {
      final s = await state([
        _summary(game: 'apex', score: 7190, rank: 'Gold II'),
        _summary(game: 'apex', score: 7760, rank: 'Gold I'),
        _summary(game: 'apex', score: 7700, rank: 'Gold II'),
      ]);
      await s.refresh();
      expect(s.celebration, isNull); // first load just remembers
      await s.refresh();
      expect(s.celebration?.title, 'Rank up');
      expect(s.celebration?.rank, 'Gold I');
      s.dismissCelebration();
      await s.refresh();
      expect(s.celebration, isNull);
    });

    test('goal reached beats rank up; season resets never celebrate', () async {
      final s = await state([
        _summary(game: 'apex', score: 7190, rank: 'Gold II'),
        _summary(game: 'apex', score: 7760, rank: 'Gold I'),
      ], prefs: {'goal.apex': jsonEncode({'label': 'Gold I', 'targetScore': 7750, 'startScore': 7000})});
      await s.refresh();
      await s.refresh();
      expect(s.celebration?.title, 'Goal reached');

      final reset = await state([
        _summary(game: 'apex', score: 4000, rank: 'Silver I'),
        _summary(game: 'apex', score: 4100, rank: 'Silver I', matches: [
          {'ts': _now, 'delta': 100, 'scoreAfter': 4100, 'kind': 'adjust'},
        ]),
      ]);
      await reset.refresh();
      await reset.refresh();
      expect(reset.celebration, isNull);
    });

    test('goals are sent with the notification registration', () async {
      final bodies = <String>[];
      SharedPreferences.setMockInitialValues({
        'account.apex': jsonEncode({'playerId': 'apex-1', 'game': 'apex', 'name': 'Phami', 'platform': 'PC'}),
      });
      final s = AppState(
        api: TrackerApi(const TrackerConfig(baseUrl: 'https://t.test', appKey: 'k'), client: MockClient((r) async {
          bodies.add(r.body);
          return http.Response('{}', 200);
        })),
        prefs: await SharedPreferences.getInstance(),
        notifications: _Notifications(),
      );
      await s.setNotificationsEnabled(true);
      await s.setGoal(Game.apex, label: 'Platinum IV', targetScore: 8500);
      await Future<void>.delayed(Duration.zero);
      expect(bodies.last, contains('"goals":[{"playerId":"apex-1","label":"Platinum IV","targetScore":8500}]'));
    });
  });

  testWidgets('celebration screen shows the rank and closes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showCelebration(context, const Celebration(game: Game.apex, title: 'Rank up', rank: 'Gold I')),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('RANK UP'), findsOneWidget);
    expect(find.text('GOLD I'), findsOneWidget);
    await tester.tap(find.text("LET'S GO"));
    await tester.pumpAndSettle();
    expect(find.text('RANK UP'), findsNothing);
  });

  testWidgets("a searched player's page shows their last session", (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
      api: TrackerApi(const TrackerConfig(baseUrl: 'https://t.test', appKey: 'k'), client: MockClient((r) async => http.Response('{}', 200))),
      prefs: await SharedPreferences.getInstance(),
    );
    final them = PlayerSummary.fromJson(_summary(name: 'Rival', matches: [_game(0, 21, won: true), _game(1, -15, won: false), _game(2, 18, won: true)]));
    const query = PlayerQuery(game: Game.valorant, name: 'Rival', tag: 'EUW', platform: 'pc', region: 'eu');
    await tester.pumpWidget(AppScope(state: state, child: MaterialApp(home: PlayerPage(query: query, initial: them))));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('+24 RR'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('SESSION'), findsWidgets);
    expect(find.text('+24 RR'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('the widget fallback snapshot carries the last session', () {
    final s = PlayerSummary.fromJson(_summary(matches: [_game(0, 21, won: true), _game(1, -15, won: false), _game(2, 18, won: true)]));
    final session = WidgetBridge.snapshotJson(s)!['session'] as Map<String, Object?>;
    expect(session['games'], 3);
    expect(session['net'], 24);
    expect(session['wins'], 2);
    expect(session['series'], [18, 3, 24]);
  });
}
