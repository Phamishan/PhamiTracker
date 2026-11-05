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
  final updates = <LiveSessionState>[];
  bool started = false;
  bool ended = false;

  @override
  bool get supported => true;

  @override
  Future<bool> start({required String game, required String player, required String unit, required LiveSessionState state}) async {
    started = true;
    return true;
  }

  @override
  Future<void> update(LiveSessionState state) async => updates.add(state);

  @override
  Future<void> end() async => ended = true;

  @override
  Future<bool> isRunning() async => started && !ended;
}

Future<AppState> _state(http.Client client, {Map<String, Object> prefs = const {}, LiveActivityService? live}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return AppState(
    api: TrackerApi(const TrackerConfig(baseUrl: 'https://tracker.test', appKey: 'k'), client: client),
    prefs: await SharedPreferences.getInstance(),
    liveActivities: live,
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

  test('live activity: session numbers, token registration and stop', () async {
    final requests = <String>[];
    var score = 16_500;
    final matches = <Map<String, Object?>>[];
    final live = _FakeLive();
    final state = await _state(
      MockClient((r) async {
        requests.add('${r.method} ${r.url.path} ${r.body}');
        return http.Response(jsonEncode(_summary(score: score, matches: matches)), 200);
      }),
      prefs: _linkedApex,
      live: live,
    );
    await state.refresh();
    expect(await state.startLiveActivity(Game.apex), isTrue);
    expect(state.liveGame, Game.apex);

    live.onToken!('ab' * 32);
    await Future<void>.delayed(Duration.zero);
    expect(requests.last, contains('POST /v1/players/apex-1/live-activity'));
    expect(requests.last, contains('"startScore":16500'));

    score = 16_590;
    matches.add({'ts': DateTime.now().millisecondsSinceEpoch + 1000, 'delta': 90, 'scoreAfter': 16_590, 'kind': 'match'});
    await state.refresh();
    expect(live.updates.last.sessionDelta, 90);
    expect(live.updates.last.games, 1);
    expect(live.updates.last.wins, 1);

    await state.stopLiveActivity();
    await Future<void>.delayed(Duration.zero);
    expect(live.ended, isTrue);
    expect(state.liveGame, isNull);
    expect(requests.last, startsWith('DELETE /v1/players/apex-1/live-activity/${'ab' * 32}'));
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
