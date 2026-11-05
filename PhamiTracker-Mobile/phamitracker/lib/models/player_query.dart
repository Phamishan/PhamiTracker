import '../services/tracker_api.dart';
import 'game.dart';
import 'summary.dart';

/// Who to look up in search. Saved for recent searches and favourites.
class PlayerQuery {
  const PlayerQuery({
    required this.game,
    required this.name,
    this.tag,
    required this.platform,
    this.region,
    this.displayName,
  });

  final Game game;
  final String name;
  final String? tag;
  final String platform;
  final String? region;

  /// The name as the API spells it ("Phami#EUW"), once a search has found them.
  final String? displayName;

  String get label => displayName ?? (tag == null || tag!.isEmpty ? name : '$name#$tag');

  /// Same player, however the name was typed.
  String get key => [game.id, platform, region ?? '', name, tag ?? ''].join('|').toLowerCase();

  PlayerQuery withDisplayName(String name) =>
      PlayerQuery(game: game, name: this.name, tag: tag, platform: platform, region: region, displayName: name);

  Future<PlayerSummary> run(TrackerApi api) =>
      api.search(game: game, name: name, tag: tag, platform: platform, region: region);

  Map<String, dynamic> toJson() => {
        'game': game.id,
        'name': name,
        'tag': ?tag,
        'platform': platform,
        'region': ?region,
        'displayName': ?displayName,
      };

  factory PlayerQuery.fromJson(Map<String, dynamic> json) => PlayerQuery(
        game: Game.fromId(json['game'] as String?),
        name: json['name'] as String,
        tag: json['tag'] as String?,
        platform: json['platform'] as String,
        region: json['region'] as String?,
        displayName: json['displayName'] as String?,
      );
}
