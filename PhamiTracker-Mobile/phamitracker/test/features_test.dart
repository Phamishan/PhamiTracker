import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/insights.dart';
import 'package:phamitracker/models/player_query.dart';
import 'package:phamitracker/models/ranks.dart';
import 'package:phamitracker/models/summary.dart';
import 'package:phamitracker/services/app_state.dart';
import 'package:phamitracker/services/live_activity.dart';
import 'package:phamitracker/services/notification_service.dart';
import 'package:phamitracker/services/tracker_api.dart';
import 'package:phamitracker/theme/app_theme.dart';
import 'package:phamitracker/widgets/common.dart';
import 'package:phamitracker/widgets/insight_cards.dart';
import 'package:phamitracker/widgets/rank_hero.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.now().millisecondsSinceEpoch;

MatchEntry _m(DateTime time, int delta, int after, {bool adjust = false}) =>
    MatchEntry(time: time, delta: delta, scoreAfter: after, isAdjustment: adjust);

Map<String, dynamic> _summary({int score = 16_500, int? cutoff = 24_000, List<Map<String, Object?>> matches = const []}) => {
      'player': {'id': 'apex-1', 'game': 'apex', 'name': 'Phami', 'platform': 'PC'},
      'score': score,
      'rankLabel': 'Master',
      'rank': {'name': 'Master'},
      'today': {},
      'history': [],
      'matches': matches,
      'serverTime': _now,
      'predator': cutoff == null ? null : {'cutoff': cutoff, 'masters': 12000},
      'characters': [
        {'name': 'Wraith', 'matches': 4, 'delta': 120, 'wins': 3},
      ],
      'split': {
        'kind': 'split',
        'name': 'Season 31 · Split 1',
        'start': _now - 20 * 86400000,
        'end': _now + 10 * 86400000,
        'games': 30,
        'wins': 18,
        'losses': 12,
        'net': 1500,
        'startScore': 15_000,
        'endScore': 16_500,
        'peak': {'score': 16_700, 'ts': _now - 86400000},
        'streak': {'won': true, 'count': 3},
        'longestWinStreak': 6,
        'daysPlayed': 9,
        'bestDay': {'day': '2026-11-02', 'delta': 340},
        'biggestGain': {'delta': 141},
        'biggestLoss': {'delta': -60},
        'topCharacter': {'name': 'Wraith', 'matches': 4, 'delta': 120, 'wins': 3},
      },
    };

class _FakeLive extends LiveActivityService {
  _FakeLive({this.allow = true});

  final bool allow;
  final calls = <bool>[];

  @override
  Future<bool> supported() async => allow;

  @override
  Future<bool> allowed() async => allow;

  @override
  Future<void> setEnabled(bool enabled) async => calls.add(enabled);
}

class _FakeNotifications extends NotificationService {
  _FakeNotifications(this.token);

  final String? token;

  @override
  Future<String?> requestToken() async => token;
}

Future<AppState> _state(http.Client client, {Map<String, Object> prefs = const {}, LiveActivityService? live, NotificationService? notifications}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState(
    api: TrackerApi(const TrackerConfig(baseUrl: 'https://tracker.test', appKey: 'k'), client: client),
    prefs: await SharedPreferences.getInstance(),
    liveActivities: live,
    notifications: notifications,
  );
}

final _linkedApex = {
  'game': 'apex',
  'account.apex': jsonEncode({'playerId': 'apex-1', 'game': 'apex', 'name': 'Phami', 'platform': 'PC'}),
};

void main() {
  test('latest session splits on a 45 minute gap and skips adjustments', () {
    final t = DateTime(2026, 11, 5, 18);
    final matches = [
      _m(t.add(const Duration(minutes: 70)), 40, 1100), // newest first, like the API
      _m(t.add(const Duration(minutes: 40)), -20, 1060),
      _m(t.add(const Duration(minutes: 30)), 0, 1080, adjust: true),
      _m(t.add(const Duration(minutes: 20)), 80, 1080),
      _m(t.subtract(const Duration(hours: 3)), 50, 1000), // an earlier session
    ];
    final s = Session.latest(matches)!;
    expect(s.matches.length, 3);
    expect(s.net, 100);
    expect(s.wins, 2);
    expect(s.best, 80);
    expect(s.worst, -20);
    expect(s.startScore, 1000);
    expect(s.isOver(t.add(const Duration(minutes: 100))), isFalse);
    expect(s.isOver(t.add(const Duration(minutes: 116))), isTrue);
    expect(Session.latest(const []), isNull);
  });

  test("every session, newest first: today's 48-minute break splits the evening in two", () {
    final t = DateTime(2026, 11, 9, 18, 26);
    final matches = [
      _m(t.add(const Duration(minutes: 57)), -18, 1175),
      _m(t.add(const Duration(minutes: 48)), 7, 1193), // 48 minutes after the last game
      _m(t, 186, 1186),
      _m(t.subtract(const Duration(minutes: 23)), -28, 1000),
      _m(t.subtract(const Duration(hours: 26)), 50, 1028), // yesterday
    ];
    final sessions = Session.all(matches);
    expect([for (final s in sessions) s.matches.length], [2, 2, 1]);
    expect(sessions.first.net, -11);
    expect(sessions[1].net, 158);
    expect(Session.latest(matches)!.start, sessions.first.start);
    expect(Session.all(const []), isEmpty);
  });

  testWidgets('the session card swipes back through older sessions', (tester) async {
    final t = DateTime(2026, 11, 9, 18);
    final sessions = Session.all([
      _m(t.add(const Duration(hours: 2)), 40, 1100),
      _m(t, -30, 1060),
      _m(t.subtract(const Duration(days: 1)), 90, 1090),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [SessionsCard(game: Game.apex, sessions: sessions, player: 'Phami', now: t.add(const Duration(hours: 4)))]),
      ),
    ));
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('+40 RP'), findsOneWidget);
    await tester.fling(find.text('+40 RP'), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('-30 RP'), findsOneWidget);
    expect(find.text('EARLIER SESSION'), findsOneWidget);
    await tester.tap(find.byTooltip('Older session'));
    await tester.pumpAndSettle();
    expect(find.text('+90 RP'), findsOneWidget);
    await tester.tap(find.byTooltip('Newer session'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Newer session'));
    await tester.pumpAndSettle();
    expect(find.text('LAST SESSION'), findsOneWidget);
  });

  test('By Legend and By Map: this split comes with the summary, All is fetched once', () async {
    SharedPreferences.setMockInitialValues({
      'account.apex': jsonEncode({'playerId': 'apex-1', 'game': 'apex', 'name': 'Phami', 'platform': 'PC'}),
    });
    final paths = <String>[];
    final state = AppState(
      api: TrackerApi(
        const TrackerConfig(baseUrl: 'https://t.test', appKey: 'k'),
        client: MockClient((r) async {
          paths.add(r.url.path);
          if (r.url.path.endsWith('/breakdown')) {
            return http.Response(jsonEncode({
              'maps': [{'map': 'Olympus', 'matches': 40, 'delta': 900, 'wins': 25}],
              'characters': [{'name': 'Wraith', 'matches': 40, 'delta': 900, 'wins': 25}],
            }), 200);
          }
          if (r.url.path == '/v1/players/apex-1') {
            return http.Response(jsonEncode({
              ..._summary(),
              'maps': [{'map': 'Olympus', 'matches': 4, 'delta': 120, 'wins': 3}],
              'characters': [{'name': 'Wraith', 'matches': 4, 'delta': 120, 'wins': 3}],
            }), 200);
          }
          return http.Response('{}', 200);
        }),
      ),
      prefs: await SharedPreferences.getInstance(),
    );
    await state.refresh();
    expect(state.statsRange(Game.apex), StatsRange.split);
    expect(state.breakdown(Game.apex)!.maps.single.matches, 4);
    expect(paths.where((p) => p.endsWith('/breakdown')), isEmpty);

    await state.setStatsRange(Game.apex, StatsRange.all);
    expect(state.breakdown(Game.apex)!.maps.single.matches, 40);
    expect(state.breakdown(Game.apex)!.characters.single.map, 'Wraith');
    await state.setStatsRange(Game.apex, StatsRange.split);
    await state.setStatsRange(Game.apex, StatsRange.all);
    expect(paths.where((p) => p.endsWith('/breakdown')).length, 1);
    expect(StatsRange.split.label(Game.valorant), 'This act');
  });

  test('VALORANT sessions allow for game length (times are game starts)', () {
    final t = DateTime(2026, 11, 8, 20);
    final matches = [
      _m(t.add(const Duration(minutes: 97)), 18, 1538), // long games: started 50 and 47 minutes apart
      _m(t.add(const Duration(minutes: 50)), -21, 1520),
      _m(t, 17, 1541),
      _m(t.subtract(const Duration(hours: 5)), 20, 1524), // an earlier evening
    ];
    final s = Session.latest(matches, game: Game.valorant)!;
    expect(s.matches.length, 3);
    expect(s.isOver(t.add(const Duration(minutes: 97 + 100))), isFalse);
    expect(s.isOver(t.add(const Duration(minutes: 97 + 120))), isTrue);
    // The same games as Apex (45-minute gaps) would split.
    expect(Session.latest(matches)!.matches.length, 1);
  });

  test('summary parses split, predator and legends', () {
    final s = PlayerSummary.fromJson(jsonDecode(jsonEncode(_summary())) as Map<String, dynamic>);
    expect(s.predator!.cutoff, 24_000);
    expect(s.characters.single.map, 'Wraith');
    expect(s.split!.noun, 'Split');
    expect(s.split!.peak, 16_700);
    expect(s.split!.streak, 3);
    expect(s.split!.bestDay, DateTime(2026, 11, 2));
    expect(s.split!.topCharacter!.map, 'Wraith');
    expect(predatorTag(s), '7,500 RP to Predator');
    expect(predatorTag(PlayerSummary.fromJson(jsonDecode(jsonEncode(_summary(score: 25_000))) as Map<String, dynamic>)), 'Predator cutoff 24,000');
    expect(predatorTag(PlayerSummary.fromJson(jsonDecode(jsonEncode(_summary(score: 12_000))) as Map<String, dynamic>)), isNull);
  });

  test('a Predator goal follows the live cutoff', () async {
    var cutoff = 24_000;
    final state = await _state(
      MockClient((r) async => http.Response(jsonEncode(_summary(cutoff: cutoff)), 200)),
      prefs: _linkedApex,
    );
    await state.refresh();
    await state.setGoal(Game.apex, label: apexPredatorGoal, targetScore: 24_000);
    cutoff = 24_350;
    await state.refresh();
    expect(state.goals[Game.apex]!.targetScore, 24_350);
    expect(state.goals[Game.apex]!.startScore, 16_500);
    expect(goalIconUrl(Game.apex, 24_350, label: apexPredatorGoal), endsWith('/apexpredator1.png'));
  });

  test('recent searches and favourites persist and stay unique', () async {
    final state = await _state(MockClient((r) async => http.Response('{}', 404)));
    PlayerQuery q(String name) => PlayerQuery(game: Game.valorant, name: name, tag: 'EUW', platform: 'pc', region: 'eu');
    for (var i = 0; i < 10; i++) {
      state.addRecentSearch(q('P$i'));
    }
    state.addRecentSearch(q('p3').withDisplayName('P3#EUW')); // same player, different case
    expect(state.recentSearches.length, AppState.maxRecentSearches);
    expect(state.recentSearches.first.label, 'P3#EUW');
    expect(state.recentSearches.where((r) => r.key == q('P3').key).length, 1);

    state.toggleFavorite(q('Rival'));
    expect(state.isFavorite(q('rival')), isTrue);

    final reloaded = await _state(MockClient((r) async => http.Response('{}', 404)),
        prefs: {for (final k in ['search.recent', 'search.favorites']) k: (await SharedPreferences.getInstance()).getString(k)!});
    expect(reloaded.recentSearches.first.label, 'P3#EUW');
    expect(reloaded.favorites.single.name, 'Rival');
    reloaded.toggleFavorite(q('Rival'));
    expect(reloaded.favorites, isEmpty);
  });

  test('live activity is a setting: on, re-registered after linking, fully off', () async {
    final live = _FakeLive();
    final state = await _state(
      MockClient((r) async => r.method == 'POST'
          ? http.Response(jsonEncode({'player': {'id': 'valorant-1', 'game': 'valorant', 'name': 'Phami', 'tag': 'EUW'}}), 201)
          : http.Response(jsonEncode(_summary()), 200)),
      prefs: _linkedApex,
      live: live,
    );
    expect(state.liveActivityEnabled, isFalse);
    expect(await state.setLiveActivityEnabled(true), isTrue);
    expect(live.calls, [true]);

    await state.link(game: Game.valorant, name: 'Phami', tag: 'EUW', platform: 'pc', region: 'eu');
    expect(live.calls, [true, true]); // the new player is registered too

    expect(await state.setLiveActivityEnabled(false), isTrue);
    expect(live.calls.last, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('live.enabled'), isFalse);

    // Not allowed by iOS: stays off and says so.
    final blocked = await _state(MockClient((r) async => http.Response('{}', 404)), live: _FakeLive(allow: false));
    expect(await blocked.setLiveActivityEnabled(true), isFalse);
    expect(blocked.liveActivityEnabled, isFalse);
  });

  test('notifications: on sends favourites, starring re-sends, off unregisters', () async {
    final requests = <String>[];
    final state = await _state(
      MockClient((r) async {
        requests.add('${r.method} ${r.url.path} ${r.body}');
        return http.Response('{"ok":true}', 200);
      }),
      notifications: _FakeNotifications('ab' * 32),
    );
    PlayerQuery q(String name) => PlayerQuery(game: Game.valorant, name: name, tag: 'EUW', platform: 'pc', region: 'eu');
    state.toggleFavorite(q('Rival'));
    expect(requests, isEmpty); // off: nothing sent

    expect(await state.setNotificationsEnabled(true), isTrue);
    expect(requests.last, startsWith('POST /v1/notifications'));
    expect(requests.last, contains('"name":"Rival"'));
    expect(requests.last, contains('"token":"${'ab' * 32}"'));

    state.toggleFavorite(q('Friend'));
    await Future<void>.delayed(Duration.zero);
    expect(requests.last, contains('"name":"Friend"'));

    expect(await state.setNotificationsEnabled(false), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(requests.last, startsWith('DELETE /v1/notifications/${'ab' * 32}'));

    // Not allowed in iOS Settings: stays off.
    final denied = await _state(MockClient((r) async => http.Response('{}', 200)), notifications: _FakeNotifications(null));
    expect(await denied.setNotificationsEnabled(true), isFalse);
    expect(denied.notificationsEnabled, isFalse);
  });

  test('K/D per map and agent', () {
    const jett = MapStat(map: 'Jett', matches: 2, delta: 42, wins: 2, kills: 45, deaths: 22);
    expect(jett.kd!.toStringAsFixed(2), '2.05');
    expect(const MapStat(map: 'Olympus', matches: 1, delta: 50, wins: 1).kd, isNull);
  });

  testWidgets('split recap, records and session cards render', (tester) async {
    final s = PlayerSummary.fromJson(jsonDecode(jsonEncode(_summary())) as Map<String, dynamic>);
    final t = DateTime(2026, 11, 5, 18);
    final session = Session([_m(t, 80, 16_480), _m(t.add(const Duration(minutes: 25)), 20, 16_500)]);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(scaffoldBackgroundColor: AppColors.background),
      home: Scaffold(
        body: ListView(children: [
          SplitRecapCard(game: Game.apex, period: s.split!, player: 'Phami'),
          RecordsCard(game: Game.apex, period: s.split!),
          SessionCard(game: Game.apex, session: session, player: 'Phami', now: t.add(const Duration(hours: 2))),
        ]),
      ),
    ));
    expect(find.text('DIAMOND I'), findsOneWidget); // started the split at 15,000
    expect(find.text('MASTER'), findsWidgets);
    expect(find.text('+1,500'), findsOneWidget);
    expect(find.text('Wraith +120'), findsOneWidget);
    expect(find.text('WIN STREAK'), findsOneWidget);
    expect(find.text('+340'), findsOneWidget);
    expect(find.text('LAST SESSION'), findsOneWidget);
    expect(find.text('+100 RP'), findsOneWidget);
    expect(find.byTooltip('Share'), findsNWidgets(2));
    expect(find.byType(TrackerCard), findsNWidgets(3));
  });
}
