import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/account.dart';
import '../models/game.dart';
import '../models/player_query.dart';
import '../models/ranks.dart';
import '../models/summary.dart';
import 'live_activity.dart';
import 'tracker_api.dart';
import 'widget_bridge.dart';

/// App-wide state: which game is showing, linked accounts, goals and the latest summaries.
class AppState extends ChangeNotifier {
  AppState({required this.api, required this._prefs, WidgetBridge? widgets, LiveActivityService? liveActivities})
    : _widgets = widgets ?? WidgetBridge(),
      liveActivities = liveActivities ?? LiveActivityService() {
    this.liveActivities.onToken = _onLiveToken;
    _load();
  }

  /// How often the open app re-asks the worker. The worker polls the game APIs every minute
  /// regardless; this just keeps the screen in step with it.
  static const liveInterval = Duration(seconds: 30);

  final TrackerApi api;
  final SharedPreferences _prefs;
  final WidgetBridge _widgets;
  final LiveActivityService liveActivities;

  /// Search: the last few players looked up, and starred ones. Newest first.
  final List<PlayerQuery> recentSearches = [];
  final List<PlayerQuery> favorites = [];
  static const maxRecentSearches = 8;

  /// The game with a Live Activity running, when the session started and the score it started at.
  Game? liveGame;
  DateTime? liveStartedAt;
  int? liveStartScore;
  String? _liveToken;

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
    List<PlayerQuery> queries(String key) => [
          for (final q in jsonDecode(_prefs.getString(key) ?? '[]') as List) PlayerQuery.fromJson(q as Map<String, dynamic>),
        ];
    recentSearches.addAll(queries('search.recent'));
    favorites.addAll(queries('search.favorites'));

    final live = _prefs.getString('live');
    if (live != null) {
      final json = jsonDecode(live) as Map<String, dynamic>;
      liveGame = Game.fromId(json['game'] as String?);
      liveStartedAt = DateTime.fromMillisecondsSinceEpoch((json['startedAt'] as num).toInt());
      liveStartScore = (json['startScore'] as num?)?.toInt();
      _liveToken = json['token'] as String?;
      // iOS ends activities on its own (after 8 hours, or when swiped away); forget ours if so.
      unawaited(liveActivities.isRunning().then((running) {
        if (!running && liveGame != null) _clearLive();
      }));
    }
  }

  // MARK: Search history

  void addRecentSearch(PlayerQuery query) {
    recentSearches
      ..removeWhere((q) => q.key == query.key)
      ..insert(0, query);
    if (recentSearches.length > maxRecentSearches) recentSearches.removeRange(maxRecentSearches, recentSearches.length);
    // Keep a favourite's name in step with how the API spells it.
    final fav = favorites.indexWhere((q) => q.key == query.key);
    if (fav >= 0) favorites[fav] = query;
    _saveSearches();
  }

  void removeRecentSearch(PlayerQuery query) {
    recentSearches.removeWhere((q) => q.key == query.key);
    _saveSearches();
  }

  void clearRecentSearches() {
    recentSearches.clear();
    _saveSearches();
  }

  bool isFavorite(PlayerQuery query) => favorites.any((q) => q.key == query.key);

  void toggleFavorite(PlayerQuery query) {
    if (isFavorite(query)) {
      favorites.removeWhere((q) => q.key == query.key);
    } else {
      favorites.insert(0, query);
    }
    _saveSearches();
  }

  void _saveSearches() {
    _prefs.setString('search.recent', jsonEncode([for (final q in recentSearches) q.toJson()]));
    _prefs.setString('search.favorites', jsonEncode([for (final q in favorites) q.toJson()]));
    notifyListeners();
  }

  // MARK: Live Activity

  /// Shows this session on the lock screen and in the Dynamic Island. The worker pushes each new
  /// game to it, so it keeps updating with the app closed.
  Future<bool> startLiveActivity(Game game) async {
    final account = accounts[game];
    final summary = summaries[game];
    if (account == null || summary == null) return false;
    if (liveGame != null) await stopLiveActivity();
    liveGame = game;
    liveStartedAt = DateTime.now();
    liveStartScore = summary.score ?? 0;
    final started = await liveActivities.start(
      game: game.id,
      player: account.displayName,
      unit: game.unit,
      state: liveState(game)!,
    );
    if (!started) {
      _clearLive();
      return false;
    }
    _saveLive();
    notifyListeners();
    return true;
  }

  Future<void> stopLiveActivity() async {
    final game = liveGame;
    final token = _liveToken;
    await liveActivities.end();
    final account = game == null ? null : accounts[game];
    if (account != null && token != null) {
      unawaited(api.endLiveActivity(account.playerId, token).catchError((Object _) {}));
    }
    _clearLive();
  }

  /// The session so far, for the Live Activity.
  LiveSessionState? liveState(Game game) {
    final summary = summaries[game];
    final since = liveStartedAt;
    if (summary == null || since == null) return null;
    final games = [
      for (final m in summary.matches)
        if (!m.isAdjustment && !m.time.isBefore(since)) m,
    ];
    final wins = games.where((m) => m.won ?? m.delta > 0).length;
    final score = summary.score ?? 0;
    return LiveSessionState(
      score: score,
      rank: summary.rankLabel ?? summary.rank.name ?? '',
      sessionDelta: score - (liveStartScore ?? score),
      games: games.length,
      wins: wins,
      losses: games.length - wins,
      lastDelta: games.isEmpty ? 0 : games.first.delta,
      updatedAt: DateTime.now(),
    );
  }

  void _onLiveToken(String token) {
    _liveToken = token;
    _saveLive();
    final account = liveGame == null ? null : accounts[liveGame!];
    if (account == null) return;
    unawaited(api
        .registerLiveActivity(account.playerId, token: token, sandbox: !kReleaseMode, startScore: liveStartScore)
        .catchError((Object _) {}));
  }

  void _saveLive() {
    _prefs.setString(
      'live',
      jsonEncode({
        'game': liveGame?.id,
        'startedAt': liveStartedAt?.millisecondsSinceEpoch,
        'startScore': liveStartScore,
        'token': ?_liveToken,
      }),
    );
  }

  void _clearLive() {
    liveGame = null;
    liveStartedAt = null;
    liveStartScore = null;
    _liveToken = null;
    _prefs.remove('live');
    notifyListeners();
  }

  /// A Predator goal follows the live cutoff, which moves all split.
  void _followPredatorCutoff(Game game) {
    final goal = goals[game];
    final cutoff = summaries[game]?.predator?.cutoff;
    if (goal == null || goal.label != apexPredatorGoal || cutoff == null || cutoff == goal.targetScore) return;
    final updated = RankGoal(label: goal.label, targetScore: cutoff, startScore: goal.startScore.clamp(0, cutoff));
    goals[game] = updated;
    _prefs.setString('goal.${game.id}', jsonEncode(updated.toJson()));
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
          _followPredatorCutoff(game);
          // Foreground updates; the worker pushes the rest while the app is closed.
          if (liveGame == game) {
            final live = liveState(game);
            if (live != null) unawaited(liveActivities.update(live));
          }
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
    if (liveGame == game) await stopLiveActivity();
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
