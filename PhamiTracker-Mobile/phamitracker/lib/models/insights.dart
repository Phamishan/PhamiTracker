import 'game.dart';
import 'summary.dart';

int? _int(Object? v) => v is num ? v.toInt() : null;
DateTime? _time(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

/// Apex Predator cutoff on the player's platform (the RP of the 750th player).
class PredatorInfo {
  const PredatorInfo({required this.cutoff, this.masters, this.updatedAt});

  final int cutoff;

  /// Masters + Predators on the platform.
  final int? masters;
  final DateTime? updatedAt;

  static PredatorInfo? tryParse(Object? json) {
    if (json is! Map<String, dynamic> || _int(json['cutoff']) == null) return null;
    return PredatorInfo(cutoff: _int(json['cutoff'])!, masters: _int(json['masters']), updatedAt: _time(json['updatedAt']));
  }
}

/// A recap of one ranked split (Apex) or act (VALORANT): start → end, the peak and records.
class PeriodStats {
  const PeriodStats({
    required this.kind,
    required this.name,
    this.start,
    this.end,
    this.games = 0,
    this.wins = 0,
    this.losses = 0,
    this.net = 0,
    this.startScore,
    this.endScore,
    this.peak,
    this.peakAt,
    this.streakWon = true,
    this.streak = 0,
    this.longestWinStreak = 0,
    this.daysPlayed = 0,
    this.bestDay,
    this.bestDayDelta,
    this.biggestGain,
    this.biggestLoss,
    this.topCharacter,
  });

  /// 'split', 'act' or 'recent' (last 90 days when the dates aren't known).
  final String kind;
  final String name;
  final DateTime? start;
  final DateTime? end;
  final int games;
  final int wins;
  final int losses;
  final int net;
  final int? startScore;
  final int? endScore;
  final int? peak;
  final DateTime? peakAt;

  /// The current run: [streak] games in a row, won or lost.
  final bool streakWon;
  final int streak;
  final int longestWinStreak;
  final int daysPlayed;
  final DateTime? bestDay;
  final int? bestDayDelta;
  final int? biggestGain;
  final int? biggestLoss;

  /// Best legend/agent by points gained.
  final MapStat? topCharacter;

  /// "Split", "Act", or "90 days" for headings.
  String get noun => switch (kind) { 'split' => 'Split', 'act' => 'Act', _ => '90 Days' };

  static PeriodStats? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final peak = json['peak'] as Map<String, dynamic>?;
    final streak = json['streak'] as Map<String, dynamic>?;
    final bestDay = json['bestDay'] as Map<String, dynamic>?;
    final top = json['topCharacter'];
    return PeriodStats(
      kind: json['kind'] as String? ?? 'recent',
      name: json['name'] as String? ?? '',
      start: _time(json['start']),
      end: _time(json['end']),
      games: _int(json['games']) ?? 0,
      wins: _int(json['wins']) ?? 0,
      losses: _int(json['losses']) ?? 0,
      net: _int(json['net']) ?? 0,
      startScore: _int(json['startScore']),
      endScore: _int(json['endScore']),
      peak: _int(peak?['score']),
      peakAt: _time(peak?['ts']),
      streakWon: streak?['won'] != false,
      streak: _int(streak?['count']) ?? 0,
      longestWinStreak: _int(json['longestWinStreak']) ?? 0,
      daysPlayed: _int(json['daysPlayed']) ?? 0,
      bestDay: bestDay?['day'] is String ? DateTime.tryParse(bestDay!['day'] as String) : null,
      bestDayDelta: _int(bestDay?['delta']),
      biggestGain: _int((json['biggestGain'] as Map?)?['delta']),
      biggestLoss: _int((json['biggestLoss'] as Map?)?['delta']),
      topCharacter: top is Map<String, dynamic> ? MapStat.fromJson(top) : null,
    );
  }
}

/// Games played close together. A gap of [gap] or more starts a new session.
class Session {
  const Session(this.matches, {this.game = Game.apex});

  /// Oldest first.
  final List<MatchEntry> matches;
  final Game game;

  /// How far apart two games' times can be and still be one session. Same as the worker's
  /// sessionGapMs (stats.js), which the Live Activity and Last Session widget use: 45 minutes for
  /// Apex. VALORANT times are when a game *started*, so 75 minutes plus a game's length (~45).
  static Duration gapFor(Game game) =>
      game == Game.valorant ? const Duration(minutes: 75 + 45) : const Duration(minutes: 45);

  DateTime get start => matches.first.time;
  DateTime get end => matches.last.time;
  int get net => matches.fold(0, (sum, m) => sum + m.delta);
  int get wins => matches.where((m) => m.won ?? m.delta > 0).length;
  int get losses => matches.length - wins;
  int get best => matches.map((m) => m.delta).reduce((a, b) => a > b ? a : b);
  int get worst => matches.map((m) => m.delta).reduce((a, b) => a < b ? a : b);
  int get endScore => matches.last.scoreAfter;
  int get startScore => matches.first.scoreAfter - matches.first.delta;

  bool isOver(DateTime now) => now.difference(end) >= gapFor(game);

  /// Every session in a match list, newest first (rank adjustments don't count).
  static List<Session> all(List<MatchEntry> matches, {Game game = Game.apex}) {
    final played = [for (final m in matches) if (!m.isAdjustment) m]..sort((a, b) => a.time.compareTo(b.time));
    final gap = gapFor(game);
    final sessions = <Session>[];
    var end = played.length;
    for (var i = played.length - 1; i >= 0; i--) {
      if (i == 0 || played[i].time.difference(played[i - 1].time) >= gap) {
        sessions.add(Session(played.sublist(i, end), game: game));
        end = i;
      }
    }
    return sessions;
  }

  /// The most recent session.
  static Session? latest(List<MatchEntry> matches, {Game game = Game.apex}) {
    final sessions = all(matches, game: game);
    return sessions.isEmpty ? null : sessions.first;
  }
}
