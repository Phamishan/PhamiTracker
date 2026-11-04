import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/game.dart';
import '../models/summary.dart';
import 'tracker_api.dart';
import 'widget_bridge.dart';

/// App-wide state: which game is showing, linked accounts, goals and the latest summaries.
class AppState extends ChangeNotifier {
  AppState({required this.api, required this._prefs, WidgetBridge? widgets})
    : _widgets = widgets ?? WidgetBridge() {
    _load();
  }

  /// How often the open app re-asks the worker. The worker polls the game APIs every minute
  /// regardless; this just keeps the screen in step with it.
  static const liveInterval = Duration(seconds: 30);

  final TrackerApi api;
  final SharedPreferences _prefs;
  final WidgetBridge _widgets;

  Game _game = Game.apex;
  final Map<Game, TrackedAccount> accounts = {};
  final Map<Game, RankGoal> goals = {};
  final Map<Game, PlayerSummary> summaries = {};
  final Map<Game, String> errors = {};
  final Set<Game> _loading = {};
  MapRotation? apexMaps;
  Timer? _timer;
  final Map<Game, ClimbRange> _climbRange = {};
  final Map<(Game, ClimbRange), List<DayPoint>> _climb = {};

  Game get game => _game;
  TrackedAccount? get account => accounts[_game];
  PlayerSummary? get summary => summaries[_game];
  RankGoal? get goal => goals[_game];
  String? get error => errors[_game];
  bool isLoading(Game game) => _loading.contains(game);

  ClimbRange climbRange(Game game) => _climbRange[game] ?? ClimbRange.twoWeeks;

  /// Points for the climb chart in the chosen range (null while loading). 14 days comes with
  /// the summary; other ranges are fetched on demand.
  List<DayPoint>? climb(Game game) {
    final range = climbRange(game);
    return range == ClimbRange.twoWeeks
        ? summaries[game]?.history
        : _climb[(game, range)];
  }

  Future<void> setClimbRange(Game game, ClimbRange range) async {
    _climbRange[game] = range;
    await _prefs.setString('climb.${game.id}', range.name);
    notifyListeners();
    await _loadClimb(game);
  }

  Future<void> _loadClimb(Game game, {bool force = false}) async {
    final range = climbRange(game);
    final account = accounts[game];
    if (account == null || range == ClimbRange.twoWeeks) return;
    if (!force && _climb.containsKey((game, range))) return;
    try {
      _climb[(game, range)] = await api.history(account.playerId, range.days);
      notifyListeners();
    } on TrackerApiException {
      // Keep whatever we had; the chart shows a loading state if there's nothing.
    }
  }

  void _load() {
    _game = Game.fromId(_prefs.getString('game'));
    for (final game in Game.values) {
      final account = _prefs.getString('account.${game.id}');
      if (account != null)
        accounts[game] = TrackedAccount.fromJson(
          jsonDecode(account) as Map<String, dynamic>,
        );
      _climbRange[game] = ClimbRange.fromName(
        _prefs.getString('climb.${game.id}'),
      );
      final goal = _prefs.getString('goal.${game.id}');
      if (goal != null)
        goals[game] = RankGoal.fromJson(
          jsonDecode(goal) as Map<String, dynamic>,
        );
    }
  }

  /// Starts the live refresh loop (call while the app is in the foreground).
  void startLive() {
    _timer?.cancel();
    refresh();
    _timer = Timer.periodic(liveInterval, (_) => refresh());
  }

  void stopLive() {
    _timer?.cancel();
    _timer = null;
  }

  void selectGame(Game game) {
    if (game == _game) return;
    _game = game;
    _prefs.setString('game', game.id);
    notifyListeners();
    refresh();
  }

  Future<void> refresh([Game? which]) async {
    final game = which ?? _game;
    final account = accounts[game];
    final loads = <Future<void>>[];
    if (game == Game.apex) loads.add(_loadApexMaps());
    if (account != null && !_loading.contains(game)) {
      _loading.add(game);
      notifyListeners();
      loads.add(() async {
        try {
          summaries[game] = await api.summary(account.playerId, refresh: true);
          errors.remove(game);
        } on TrackerApiException catch (e) {
          errors[game] = e.message;
        } finally {
          _loading.remove(game);
        }
      }());
    }
    await Future.wait(loads);
    // Longer chart ranges barely move minute to minute: load them once here, and again only
    // on pull-to-refresh ([refreshAll]).
    if (account != null) unawaited(_loadClimb(game));
    notifyListeners();
    _syncWidgets();
  }

  /// Pull-to-refresh: everything, including the selected chart range.
  Future<void> refreshAll() async {
    await Future.wait([refresh(), _loadClimb(_game, force: true)]);
  }

  Future<void> _loadApexMaps() async {
    try {
      apexMaps = await api.apexMaps();
    } on TrackerApiException {
      // The rotation is a nice-to-have; keep showing the last one.
    }
  }

  Future<void> link({
    required Game game,
    required String name,
    String? tag,
    required String platform,
    String? region,
  }) async {
    final account = await api.link(
      game: game,
      name: name,
      tag: tag,
      platform: platform,
      region: region,
    );
    final previous = accounts[game];
    accounts[game] = account;
    summaries.remove(game);
    _climb.removeWhere((key, _) => key.$1 == game);
    errors.remove(game);
    if (previous?.playerId != account.playerId) {
      goals.remove(game);
      await _prefs.remove('goal.${game.id}');
    }
    await _prefs.setString('account.${game.id}', jsonEncode(account.toJson()));
    _game = game;
    await _prefs.setString('game', game.id);
    notifyListeners();
    await refresh(game);
  }

  Future<void> unlink(Game game) async {
    final account = accounts.remove(game);
    summaries.remove(game);
    _climb.removeWhere((key, _) => key.$1 == game);
    goals.remove(game);
    errors.remove(game);
    await _prefs.remove('account.${game.id}');
    await _prefs.remove('goal.${game.id}');
    notifyListeners();
    _syncWidgets();
    if (account != null) {
      // Lets the worker stop polling it. Not fatal if it fails: it goes idle after a few weeks.
      unawaited(api.unlink(account.playerId).catchError((Object _) {}));
    }
  }

  Future<void> setGoal(
    Game game, {
    required String label,
    required int targetScore,
  }) async {
    final current = summaries[game]?.score ?? 0;
    final goal = RankGoal(
      label: label,
      targetScore: targetScore,
      startScore: current.clamp(0, targetScore),
    );
    goals[game] = goal;
    await _prefs.setString('goal.${game.id}', jsonEncode(goal.toJson()));
    notifyListeners();
    _syncWidgets();
  }

  Future<void> clearGoal(Game game) async {
    goals.remove(game);
    await _prefs.remove('goal.${game.id}');
    notifyListeners();
    _syncWidgets();
  }

  void _syncWidgets() {
    unawaited(
      _widgets.sync(
        config: api.config,
        accounts: accounts,
        goals: goals,
        summaries: summaries,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
