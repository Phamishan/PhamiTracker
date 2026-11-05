int? _int(Object? v) => v is num ? v.toInt() : null;

/// A VALORANT match's full scoreboard (HenrikDev v4 match, via the worker).
class MatchDetail {
  const MatchDetail({
    this.map,
    this.mapImage,
    this.mode,
    this.startedAt,
    this.duration,
    required this.rounds,
    required this.teams,
    required this.players,
  });

  final String? map;
  final String? mapImage;
  final String? mode;
  final DateTime? startedAt;
  final Duration? duration;
  final int rounds;
  final List<MatchTeam> teams;

  /// Everyone in the match, best ACS first.
  final List<MatchPlayer> players;

  List<MatchPlayer> teamPlayers(String? team) => [
    for (final p in players)
      if (p.team == team) p,
  ];

  factory MatchDetail.fromJson(Map<String, dynamic> json) => MatchDetail(
    map: json['map'] as String?,
    mapImage: json['mapImage'] as String?,
    mode: json['mode'] as String?,
    startedAt: _int(json['startedAt']) == null ? null : DateTime.fromMillisecondsSinceEpoch(_int(json['startedAt'])!),
    duration: _int(json['durationMs']) == null ? null : Duration(milliseconds: _int(json['durationMs'])!),
    rounds: _int(json['rounds']) ?? 0,
    teams: [for (final t in (json['teams'] as List? ?? const [])) MatchTeam.fromJson(t as Map<String, dynamic>)],
    players: [for (final p in (json['players'] as List? ?? const [])) MatchPlayer.fromJson(p as Map<String, dynamic>)],
  );
}

class MatchTeam {
  const MatchTeam({required this.id, this.won, this.roundsWon, this.roundsLost});

  final String id;
  final bool? won;
  final int? roundsWon;
  final int? roundsLost;

  factory MatchTeam.fromJson(Map<String, dynamic> json) => MatchTeam(
    id: '${json['id']}',
    won: json['won'] as bool?,
    roundsWon: _int(json['roundsWon']),
    roundsLost: _int(json['roundsLost']),
  );
}

class MatchPlayer {
  const MatchPlayer({
    required this.name,
    this.tag,
    this.team,
    this.agent,
    this.agentIcon,
    this.rank,
    this.rankIcon,
    this.kills = 0,
    this.deaths = 0,
    this.assists = 0,
    this.acs,
    this.adr,
    this.headshotPct,
  });

  final String name;
  final String? tag;
  final String? team;
  final String? agent;
  final String? agentIcon;
  final String? rank;
  final String? rankIcon;
  final int kills;
  final int deaths;
  final int assists;
  final int? acs;
  final int? adr;
  final int? headshotPct;

  String get riotId => tag == null || tag!.isEmpty ? name : '$name#$tag';

  factory MatchPlayer.fromJson(Map<String, dynamic> json) => MatchPlayer(
    name: json['name'] as String? ?? '?',
    tag: json['tag'] as String?,
    team: json['team'] as String?,
    agent: json['agent'] as String?,
    agentIcon: json['agentIcon'] as String?,
    rank: json['rank'] as String?,
    rankIcon: json['rankIcon'] as String?,
    kills: _int(json['kills']) ?? 0,
    deaths: _int(json['deaths']) ?? 0,
    assists: _int(json['assists']) ?? 0,
    acs: _int(json['acs']),
    adr: _int(json['adr']),
    headshotPct: _int(json['headshotPct']),
  );
}
