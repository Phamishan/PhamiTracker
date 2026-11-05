import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the lock screen / Dynamic Island shows. Keys match ContentState in AppDelegate.swift,
/// PhamiTrackerWidget.swift and the worker's live.js.
class LiveSessionState {
  const LiveSessionState({
    required this.score,
    required this.rank,
    required this.sessionDelta,
    required this.games,
    required this.wins,
    required this.losses,
    required this.lastDelta,
    required this.updatedAt,
  });

  final int score;
  final String rank;
  final int sessionDelta;
  final int games;
  final int wins;
  final int losses;
  final int lastDelta;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
        'score': score,
        'rank': rank,
        'sessionDelta': sessionDelta,
        'games': games,
        'wins': wins,
        'losses': losses,
        'lastDelta': lastDelta,
        'updatedAt': updatedAt.millisecondsSinceEpoch ~/ 1000,
      };
}

/// Talks to ActivityKit through AppDelegate.swift. Everything is a no-op off iOS (and in tests).
class LiveActivityService {
  LiveActivityService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'token') onToken?.call(call.arguments as String);
    });
  }

  static const _channel = MethodChannel('phamitracker/live_activity');

  /// The activity's push token; the worker uses it to update the activity with the app closed.
  ValueChanged<String>? onToken;

  bool get supported => defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;

  /// Whether the user allows Live Activities (Settings › PhamiTracker) on iOS 16.2+.
  Future<bool> enabled() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('enabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> start({required String game, required String player, required String unit, required LiveSessionState state}) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('start', {
            'game': game,
            'player': player,
            'unit': unit,
            'state': state.toJson(),
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> update(LiveSessionState state) => _call('update', state.toJson());

  Future<void> end() => _call('end');

  /// True if an activity is still running (it survives app restarts, iOS ends it after 8 hours).
  Future<bool> isRunning() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('running') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _call(String method, [Object? args]) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException {
      // Activity already gone; nothing to do.
    } on MissingPluginException {
      // Not on iOS.
    }
  }
}
