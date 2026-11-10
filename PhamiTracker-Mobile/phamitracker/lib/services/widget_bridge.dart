import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/account.dart';
import '../models/game.dart';
import '../models/insights.dart';
import '../models/ranks.dart';
import '../models/summary.dart';
import 'tracker_api.dart';

/// Hands the home-screen widgets what they need through the App Group: where the worker is,
/// which account to show per game, the goal, and the latest numbers as a fallback. The widgets
/// then fetch from the worker on their own, so they stay current without the app being opened.
class WidgetBridge {
  static const _channel = MethodChannel('phamitracker/widgets');

  Future<void> sync({
    required TrackerConfig config,
    required Map<Game, TrackedAccount> accounts,
    required Map<Game, RankGoal> goals,
    required Map<Game, PlayerSummary> summaries,
  }) async {
    final payload = {
      'apiUrl': config.baseUrl,
      'appKey': config.appKey,
      'games': {
        for (final game in Game.values)
          if (accounts[game] case final account?)
            game.id: {
              'playerId': account.playerId,
              'name': account.displayName,
              'unit': game.unit,
              'goal': goals[game] == null
                  ? null
                  : {...goals[game]!.toJson(), 'icon': goalIconUrl(game, goals[game]!.targetScore, label: goals[game]!.label)},
              'snapshot': snapshotJson(summaries[game]),
            },
      },
    };
    try {
      await _channel.invokeMethod('save', jsonEncode(payload));
    } on MissingPluginException {
      // Not on iOS (or in tests): there are no widgets to update.
    } on PlatformException {
      // App Group missing from the signing profile. The app still works, just no widgets.
    }
  }

  /// Same shape as the worker's /widget response, so the widget can read either.
  static Map<String, dynamic>? snapshotJson(PlayerSummary? s) {
    if (s == null) return null;
    return {
      'score': s.score,
      'rankLabel': s.rankLabel,
      'rank': {'name': s.rank.name, 'rr': s.rank.rr},
      'today': {'delta': s.today.delta, 'matches': s.today.matches, 'wins': s.today.wins, 'losses': s.today.losses},
      'status': {'online': s.status.online, 'inGame': s.status.inGame},
      'polledAt': s.polledAt?.millisecondsSinceEpoch,
      if (s.season?.splitEnd != null)
        'season': {'season': s.season!.name, 'split': s.season!.split, 'splitEnd': s.season!.splitEnd!.millisecondsSinceEpoch},
      'history': [
        for (final d in s.history.skip(s.history.length > 7 ? s.history.length - 7 : 0))
          {'day': d.day.toIso8601String().substring(0, 10), 'score': d.score, 'delta': d.delta},
      ],
      if (Session.latest(s.matches, game: s.game) case final session?)
        'session': {
          'games': session.matches.length,
          'wins': session.wins,
          'losses': session.losses,
          'net': session.net,
          'best': session.best,
          'worst': session.worst,
          'start': session.start.millisecondsSinceEpoch,
          'end': session.end.millisecondsSinceEpoch,
          'series': [for (var i = 0, total = 0; i < session.matches.length; i++) total += session.matches[i].delta],
        },
      'matches': [
        for (final m in s.matches.take(5))
          {
            'ts': m.time.millisecondsSinceEpoch,
            'delta': m.delta,
            'kind': m.isAdjustment ? 'adjust' : 'match',
            'map': m.map,
            if (s.game == Game.apex) 'legend': m.character else 'agent': m.character,
          },
      ],
    };
  }
}
