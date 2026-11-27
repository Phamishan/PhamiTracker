import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phamitracker/models/game.dart';
import 'package:phamitracker/models/insights.dart';
import 'package:phamitracker/pages/wrapped_page.dart';

PeriodStats _split({bool withWrapped = true}) => PeriodStats.tryParse({
      'kind': 'split',
      'name': 'Season 31 · Split 1',
      'start': DateTime(2026, 11, 3, 19).millisecondsSinceEpoch,
      'end': DateTime(2026, 12, 15, 19).millisecondsSinceEpoch,
      'games': 141,
      'wins': 80,
      'losses': 61,
      'net': 852,
      'startScore': 8000,
      'endScore': 8852,
      'peak': {'score': 9320, 'ts': DateTime(2026, 11, 20, 21).millisecondsSinceEpoch},
      'longestWinStreak': 7,
      'daysPlayed': 14,
      'bestDay': {'day': '2026-11-09', 'delta': 640},
      'biggestGain': {'delta': 327},
      'biggestLoss': {'delta': -48},
      if (withWrapped)
        'wrapped': {
          'mostPlayed': {'name': 'Crypto', 'matches': 53, 'delta': 2539, 'wins': 35},
          'bestMap': {'map': 'Olympus', 'matches': 40, 'delta': 1210, 'wins': 25},
          'sessions': 18,
          'hours': 51,
          'bestSession': {'net': 712, 'games': 11, 'ts': DateTime(2026, 11, 9, 18).millisecondsSinceEpoch},
          'biggestClimb': {'delta': 1420, 'from': 7900, 'to': 9320},
        },
    })!;

void main() {
  test('Wrapped cards from the split numbers', () {
    final cards = wrappedCards(Game.apex, _split(), 'meeji', finished: true);
    final big = [for (final c in cards) c.big];
    expect(big.first, 'Season 31 · Split 1');
    expect(big, containsAll(['141 games', '+852 RP', 'Crypto', 'Olympus', '7 in a row', '+1,420 RP', '9 November']));
    final played = cards.firstWhere((c) => c.big == '141 games');
    expect(played.lines.first, '≈ 51 hours in 18 sessions');
    final climb = cards.firstWhere((c) => c.big == '+1,420 RP');
    expect(climb.lines.first, 'from Gold I to Platinum III');
    expect(cards.first.title, 'Split Wrapped');
  });

  test('cards without data are left out', () {
    final cards = wrappedCards(Game.apex, _split(withWrapped: false), 'meeji');
    expect(cards.map((c) => c.kicker), isNot(contains('Your main')));
    expect(cards.map((c) => c.kicker), isNot(contains('Your best map')));
    expect(cards.first.title, 'Split Wrapped, so far');
  });

  testWidgets('swipe and tap through the story', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: WrappedPage(game: Game.apex, period: _split(), player: 'meeji', finished: true)));
    expect(find.text('Season 31 · Split 1'), findsOneWidget);
    await tester.tapAt(const Offset(350, 500)); // right side: next card
    await tester.pumpAndSettle();
    expect(find.text('141 games'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('+852 RP'), findsOneWidget);
    await tester.tapAt(const Offset(30, 500)); // left side: back
    await tester.pumpAndSettle();
    expect(find.text('141 games'), findsOneWidget);
  });

  test('VALORANT: act, agents, RR, wins and K/D', () {
    final act = PeriodStats.tryParse({
      'kind': 'act',
      'name': 'V26 · Act 6',
      'games': 27,
      'wins': 15,
      'losses': 12,
      'net': 96,
      'startScore': 1904,
      'endScore': 2000,
      'peak': {'score': 2042},
      'longestWinStreak': 4,
      'daysPlayed': 6,
      'wrapped': {
        'mostPlayed': {'name': 'Jett', 'matches': 14, 'delta': 61, 'wins': 8, 'kills': 280, 'deaths': 200},
        'sessions': 6,
        'hours': 22,
        'biggestClimb': {'delta': 138, 'from': 1904, 'to': 2042},
      },
    })!;
    final cards = wrappedCards(Game.valorant, act, 'meeji', finished: true);
    expect(cards.first.title, 'Act Wrapped');
    final played = cards.firstWhere((c) => c.big == '27 games');
    expect(played.lines.last, '15 wins · 12 losses');
    expect(cards.firstWhere((c) => c.kicker == 'You finished').big, '+96 RR');
    expect(cards.firstWhere((c) => c.kicker == 'You finished').lines, ['Ascendant 2 → Ascendant 3', '2,000 elo']);
    final main = cards.firstWhere((c) => c.kicker == 'Your main agent');
    expect(main.big, 'Jett');
    expect(main.lines, ['14 games · +61 RR', '57% wins', 'K/D 1.40']);
    expect(cards.firstWhere((c) => c.kicker == 'On fire').title, 'longest win streak');
  });
}
