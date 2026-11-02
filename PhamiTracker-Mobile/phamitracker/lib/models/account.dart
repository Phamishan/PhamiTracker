import 'game.dart';

/// A linked game account. [playerId] is the worker's id for it.
class TrackedAccount {
  const TrackedAccount({
    required this.playerId,
    required this.game,
    required this.name,
    required this.platform,
    this.tag,
    this.region,
  });

  final String playerId;
  final Game game;
  final String name;
  final String? tag;
  final String platform;
  final String? region;

  String get displayName => tag == null || tag!.isEmpty ? name : '$name#$tag';

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'game': game.id,
        'name': name,
        'tag': tag,
        'platform': platform,
        'region': region,
      };

  factory TrackedAccount.fromJson(Map<String, dynamic> json) => TrackedAccount(
        playerId: json['playerId'] as String,
        game: Game.fromId(json['game'] as String?),
        name: json['name'] as String,
        tag: json['tag'] as String?,
        platform: json['platform'] as String,
        region: json['region'] as String?,
      );
}

/// The rank a player is grinding towards. Progress is measured from [startScore], the score
/// they had when they set it, so the bar fills as they climb.
class RankGoal {
  const RankGoal({required this.label, required this.targetScore, required this.startScore});

  final String label;
  final int targetScore;
  final int startScore;

  double progress(int score) {
    if (score >= targetScore) return 1;
    final span = targetScore - startScore;
    if (span <= 0) return 0;
    return ((score - startScore) / span).clamp(0.0, 1.0);
  }

  int remaining(int score) => (targetScore - score).clamp(0, 1 << 31);

  Map<String, dynamic> toJson() => {'label': label, 'targetScore': targetScore, 'startScore': startScore};

  factory RankGoal.fromJson(Map<String, dynamic> json) => RankGoal(
        label: json['label'] as String,
        targetScore: (json['targetScore'] as num).toInt(),
        startScore: (json['startScore'] as num).toInt(),
      );
}
