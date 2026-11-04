import 'game.dart';

int? _int(Object? v) => v is num ? v.toInt() : null;
DateTime? _time(Object? v) => v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

/// What the worker knows about a player: rank, today's numbers, history and recent matches.
class PlayerSummary {
  PlayerSummary({
    required this.game,
    required this.name,
    required this.score,
    required this.rankLabel,
    required this.rank,
    required this.status,
    required this.today,
    required this.history,
    required this.maps,
    required this.matches,
    required this.polledAt,
    required this.serverTime,
    this.level,
    this.error,
    this.season,
    this.tracked = true,
  });

  final Game game;
  final String name;
  final int? score;
  final String? rankLabel;
  final RankInfo rank;
  final PlayerStatus status;
  final TodayStats today;
  final List<DayPoint> history;
  final List<MapStat> maps;
  final List<MatchEntry> matches;
  final DateTime? polledAt;
  final DateTime serverTime;
  final int? level;
  final String? error;

  /// Apex only: current season and ranked split dates.
  final SeasonInfo? season;

  /// Search results: whether anyone tracks this account (so its matches were recorded).
  final bool tracked;

  /// Average points per day over the charted history ("~116 RP/day"), or null without enough data.
  int? get pacePerDay {
    final scores = [for (final d in history) ?d.score];
    if (scores.length < 2) return null;
    return ((scores.last - scores.first) / (scores.length - 1)).round();
  }

  factory PlayerSummary.fromJson(Map<String, dynamic> json) {
    final player = json['player'] as Map<String, dynamic>? ?? const {};
    final game = Game.fromId(player['game'] as String?);
    final tag = player['tag'] as String?;
    return PlayerSummary(
      game: game,
      name: tag == null || tag.isEmpty ? '${player['name']}' : '${player['name']}#$tag',
      score: _int(json['score']),
      rankLabel: json['rankLabel'] as String?,
      rank: RankInfo.fromJson(json['rank'] as Map<String, dynamic>? ?? const {}),
      status: PlayerStatus.fromJson(json['status'] as Map<String, dynamic>? ?? const {}),
      today: TodayStats.fromJson(json['today'] as Map<String, dynamic>? ?? const {}),
      history: [
        for (final d in (json['history'] as List? ?? const [])) DayPoint.fromJson(d as Map<String, dynamic>),
      ],
      maps: [
        for (final m in (json['maps'] as List? ?? const [])) MapStat.fromJson(m as Map<String, dynamic>),
      ],
      matches: [
        for (final m in (json['matches'] as List? ?? const [])) MatchEntry.fromJson(m as Map<String, dynamic>),
      ],
      polledAt: _time(json['polledAt']),
      serverTime: _time(json['serverTime']) ?? DateTime.now(),
      level: _int(json['level']),
      error: json['error'] as String?,
      season: SeasonInfo.tryParse(json['season']),
      tracked: json['tracked'] != false,
    );
  }
}

class RankInfo {
  const RankInfo({this.name, this.image, this.rr, this.ladderPos, this.peak, this.gamesNeeded = 0});

  final String? name;
  final String? image;

  /// VALORANT RR inside the current division.
  final int? rr;
  final int? ladderPos;
  final String? peak;
  final int gamesNeeded;

  factory RankInfo.fromJson(Map<String, dynamic> json) => RankInfo(
        name: json['name'] as String?,
        image: json['image'] as String? ?? valorantTierIcon(_int(json['tier'])),
        rr: _int(json['rr']),
        ladderPos: _int(json['ladderPos']),
        peak: json['peak'] as String?,
        gamesNeeded: _int(json['gamesNeeded']) ?? 0,
      );
}

class PlayerStatus {
  const PlayerStatus({this.online = false, this.inGame = false, this.text, this.legend});

  final bool online;
  final bool inGame;
  final String? text;
  final String? legend;

  factory PlayerStatus.fromJson(Map<String, dynamic> json) => PlayerStatus(
        online: json['online'] == true,
        inGame: json['inGame'] == true,
        text: json['text'] as String?,
        legend: json['legend'] as String?,
      );
}

class TodayStats {
  const TodayStats({
    this.delta = 0,
    this.matches = 0,
    this.wins = 0,
    this.losses = 0,
    this.best,
    this.worst,
    this.series = const [],
  });

  final int delta;
  final int matches;
  final int wins;
  final int losses;
  final int? best;
  final int? worst;

  /// Running total after each of today's games, oldest first.
  final List<int> series;

  factory TodayStats.fromJson(Map<String, dynamic> json) => TodayStats(
        delta: _int(json['delta']) ?? 0,
        matches: _int(json['matches']) ?? 0,
        wins: _int(json['wins']) ?? 0,
        losses: _int(json['losses']) ?? 0,
        best: _int(json['best']),
        worst: _int(json['worst']),
        series: [for (final v in (json['series'] as List? ?? const [])) (v as num).toInt()],
      );
}

class DayPoint {
  const DayPoint({required this.day, required this.score, required this.delta, required this.matches});

  final DateTime day;
  final int? score;
  final int delta;
  final int matches;

  factory DayPoint.fromJson(Map<String, dynamic> json) => DayPoint(
        day: DateTime.parse(json['day'] as String),
        score: _int(json['score']),
        delta: _int(json['delta']) ?? 0,
        matches: _int(json['matches']) ?? 0,
      );
}

class MapStat {
  const MapStat({required this.map, required this.matches, required this.delta, required this.wins});

  final String map;
  final int matches;
  final int delta;
  final int wins;

  factory MapStat.fromJson(Map<String, dynamic> json) => MapStat(
        map: json['map'] as String,
        matches: _int(json['matches']) ?? 0,
        delta: _int(json['delta']) ?? 0,
        wins: _int(json['wins']) ?? 0,
      );
}

class MatchEntry {
  const MatchEntry({
    required this.time,
    required this.delta,
    required this.scoreAfter,
    required this.isAdjustment,
    this.map,
    this.character,
    this.rank,
    this.kills,
    this.deaths,
    this.assists,
    this.won,
    this.roundsWon,
    this.roundsLost,
  });

  final DateTime time;
  final int delta;
  final int scoreAfter;

  /// Season resets / corrections rather than a played game.
  final bool isAdjustment;
  final String? map;

  /// Apex legend or VALORANT agent.
  final String? character;
  final String? rank;
  final int? kills;
  final int? deaths;
  final int? assists;
  final bool? won;
  final int? roundsWon;
  final int? roundsLost;

  factory MatchEntry.fromJson(Map<String, dynamic> json) => MatchEntry(
        time: _time(json['ts']) ?? DateTime.now(),
        delta: _int(json['delta']) ?? 0,
        scoreAfter: _int(json['scoreAfter']) ?? 0,
        isAdjustment: json['kind'] == 'adjust',
        map: json['map'] as String?,
        character: (json['legend'] ?? json['agent']) as String?,
        rank: json['rank'] as String?,
        kills: _int(json['kills']),
        deaths: _int(json['deaths']),
        assists: _int(json['assists']),
        won: json['won'] as bool?,
        roundsWon: _int(json['roundsWon']),
        roundsLost: _int(json['roundsLost']),
      );
}

/// Current Apex season and ranked split (from apexseasons.online, via the worker).
class SeasonInfo {
  const SeasonInfo({this.name, this.split, this.splitEnd, this.estimated = true});

  final String? name;
  final int? split;
  final DateTime? splitEnd;
  final bool estimated;

  static SeasonInfo? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return SeasonInfo(
      name: json['season'] as String?,
      split: _int(json['split']),
      splitEnd: _time(json['splitEnd']),
      estimated: json['estimated'] != false,
    );
  }

  /// "Split ends in 22d · ~116 RP/day": the daily pace needed to reach [remaining] before the reset.
  String? goalPace(int remaining, String unit, {DateTime? now}) {
    final end = splitEnd;
    if (end == null) return null;
    final left = end.difference(now ?? DateTime.now());
    if (left.isNegative) return null;
    final ends = left.inHours < 24 ? 'Split ends in ${left.inHours}h' : 'Split ends in ${left.inDays}d';
    if (remaining <= 0) return ends;
    final days = left.inHours < 24 ? 1 : left.inDays;
    return '$ends · ~${(remaining / days).ceil()} $unit/day';
  }
}

/// Official VALORANT rank art (valorant-api.com) for a competitive tier id.
String? valorantTierIcon(int? tier) => tier == null || tier <= 0
    ? null
    : 'https://media.valorant-api.com/competitivetiers/03621f52-342b-cf4e-4f86-9350a49c6d04/$tier/largeicon.png';

/// Apex map rotation.
class MapRotation {
  const MapRotation({this.battleRoyale, this.ranked, this.ltm});

  final RotationPair? battleRoyale;
  final RotationPair? ranked;
  final RotationPair? ltm;

  factory MapRotation.fromJson(Map<String, dynamic> json) => MapRotation(
        battleRoyale: RotationPair.tryParse(json['battleRoyale']),
        ranked: RotationPair.tryParse(json['ranked']),
        ltm: RotationPair.tryParse(json['ltm']),
      );
}

class RotationPair {
  const RotationPair({this.current, this.next});

  final RotationSlot? current;
  final RotationSlot? next;

  static RotationPair? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return RotationPair(current: RotationSlot.tryParse(json['current']), next: RotationSlot.tryParse(json['next']));
  }
}

class RotationSlot {
  const RotationSlot({required this.map, this.mode, this.image, this.start, this.end});

  final String map;
  final String? mode;
  final String? image;
  final DateTime? start;
  final DateTime? end;

  static RotationSlot? tryParse(Object? json) {
    if (json is! Map<String, dynamic> || json['map'] == null) return null;
    return RotationSlot(
      map: json['map'] as String,
      mode: json['mode'] as String?,
      image: json['image'] as String?,
      start: _time(json['start']),
      end: _time(json['end']),
    );
  }
}

/// Ranges for the climb chart. [days] 0 means everything since the account was linked.
enum ClimbRange {
  allTime('All', 0),
  threeMonths('3M', 90),
  month('1M', 30),
  twoWeeks('14D', 14),
  week('7D', 7);

  const ClimbRange(this.label, this.days);

  final String label;
  final int days;

  static ClimbRange fromName(String? name) =>
      ClimbRange.values.firstWhere((r) => r.name == name, orElse: () => ClimbRange.twoWeeks);
}
