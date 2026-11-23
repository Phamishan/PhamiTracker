import 'package:flutter/painting.dart';

/// A VALORANT Premier team (GET /v1/premier): division, points, place, record, roster, matches.
class PremierTeam {
  const PremierTeam({
    required this.name,
    required this.tag,
    required this.points,
    required this.pointsGoal,
    required this.wins,
    required this.losses,
    required this.region,
    this.division,
    this.place,
    this.conference,
    this.image,
    this.primary,
    this.members = const [],
    this.matches = const [],
  });

  final String name;
  final String tag;

  /// "Intermediate 3" (Open 1 ... Elite 5, Contender).
  final String? division;
  final int points;

  /// Points for the playoffs (600, like PhamiBot's bar).
  final int pointsGoal;
  final int? place;

  /// "EU Central East".
  final String? conference;

  /// Where its matches are played (eu, na, ...), for scoreboards and roster lookups.
  final String region;
  final int wins;
  final int losses;
  final String? image;

  /// The team's own colour.
  final Color? primary;
  final List<PremierMember> members;

  /// Newest first.
  final List<PremierMatch> matches;

  String get label => '$name#$tag';
  int get games => wins + losses;
  int? get winRate => games == 0 ? null : (wins * 100 / games).round();

  factory PremierTeam.fromJson(Map<String, dynamic> json) => PremierTeam(
        name: json['name'] as String? ?? '',
        tag: json['tag'] as String? ?? '',
        division: json['division'] as String?,
        points: (json['points'] as num?)?.toInt() ?? 0,
        pointsGoal: (json['pointsGoal'] as num?)?.toInt() ?? 600,
        place: (json['place'] as num?)?.toInt(),
        conference: json['conference'] as String?,
        region: json['region'] as String? ?? 'eu',
        wins: (json['wins'] as num?)?.toInt() ?? 0,
        losses: (json['losses'] as num?)?.toInt() ?? 0,
        image: json['image'] as String?,
        primary: parseHexColor((json['colors'] as Map?)?['primary'] as String?),
        members: [
          for (final m in (json['members'] as List? ?? const [])) PremierMember.fromJson(m as Map<String, dynamic>),
        ],
        matches: [
          for (final m in (json['matches'] as List? ?? const [])) PremierMatch.fromJson(m as Map<String, dynamic>),
        ],
      );
}

class PremierMember {
  const PremierMember({required this.name, required this.tag});

  final String name;
  final String tag;

  String get riotId => '$name#$tag';

  factory PremierMember.fromJson(Map<String, dynamic> json) =>
      PremierMember(name: json['name'] as String? ?? '', tag: json['tag'] as String? ?? '');
}

/// One league match: points before and after (50+ points is a win).
class PremierMatch {
  const PremierMatch({required this.delta, required this.pointsAfter, this.id, this.startedAt, this.won});

  final String? id;
  final DateTime? startedAt;
  final int delta;
  final int pointsAfter;

  /// Null when it gave no points (no result yet).
  final bool? won;

  factory PremierMatch.fromJson(Map<String, dynamic> json) => PremierMatch(
        id: json['id'] as String?,
        startedAt: json['startedAt'] is num ? DateTime.fromMillisecondsSinceEpoch((json['startedAt'] as num).toInt()) : null,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        pointsAfter: (json['pointsAfter'] as num?)?.toInt() ?? 0,
        won: switch (json['result']) { 'win' => true, 'loss' => false, _ => null },
      );
}

/// "#ff4655" or "ff4655" -> Color (null if it isn't a hex colour).
Color? parseHexColor(String? hex) {
  final digits = (hex ?? '').replaceFirst('#', '');
  if (!RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(digits)) return null;
  final rgb = int.parse(digits.substring(0, 6), radix: 16);
  return Color(0xFF000000 | rgb);
}
