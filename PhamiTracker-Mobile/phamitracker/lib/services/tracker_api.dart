import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/account.dart';
import '../models/game.dart';
import '../models/summary.dart';

class TrackerApiException implements Exception {
  TrackerApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Where the worker lives. Comes from `.env` (written by Codemagic from the phamitracker_env group).
class TrackerConfig {
  const TrackerConfig({required this.baseUrl, required this.appKey});

  final String baseUrl;
  final String appKey;

  bool get isConfigured => baseUrl.isNotEmpty;

  factory TrackerConfig.fromEnv() {
    String read(String key) => dotenv.isInitialized ? (dotenv.maybeGet(key) ?? '') : '';
    return TrackerConfig(
      baseUrl: read('TRACKER_API_URL').replaceAll(RegExp(r'/+$'), ''),
      appKey: read('TRACKER_APP_KEY'),
    );
  }
}

/// Talks to PhamiTracker-Worker, which does the polling of the game APIs.
class TrackerApi {
  TrackerApi(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final TrackerConfig config;
  final http.Client _client;

  static int get _tzOffset => DateTime.now().timeZoneOffset.inMinutes;

  Future<Map<String, dynamic>> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    if (!config.isConfigured) throw TrackerApiException('TRACKER_API_URL is not set in .env');
    final uri = Uri.parse('${config.baseUrl}$path').replace(queryParameters: query);
    final request = http.Request(method, uri)
      ..headers['x-app-key'] = config.appKey
      ..headers['content-type'] = 'application/json';
    if (body != null) request.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(request).timeout(const Duration(seconds: 25)));
    } catch (_) {
      throw TrackerApiException("Couldn't reach the tracker. Check your connection.");
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final message = decoded is Map ? decoded['error'] as String? : null;
      throw TrackerApiException(message ?? 'Tracker returned ${res.statusCode}', res.statusCode);
    }
    return decoded as Map<String, dynamic>;
  }

  Future<TrackedAccount> link({
    required Game game,
    required String name,
    String? tag,
    required String platform,
    String? region,
  }) async {
    final json = await _send('POST', '/v1/players', body: {
      'game': game.id,
      'name': name,
      'tag': ?tag,
      'platform': platform,
      'region': ?region,
    });
    final player = json['player'] as Map<String, dynamic>;
    return TrackedAccount(
      playerId: player['id'] as String,
      game: game,
      name: player['name'] as String? ?? name,
      tag: player['tag'] as String?,
      platform: platform,
      region: region,
    );
  }

  Future<PlayerSummary> summary(String playerId, {bool refresh = false, int days = 14}) async {
    final json = await _send('GET', '/v1/players/$playerId', query: {
      'tzOffset': '$_tzOffset',
      'days': '$days',
      if (refresh) 'refresh': '1',
    });
    return PlayerSummary.fromJson(json);
  }

  /// Daily scores for the climb chart. `days: 0` = since the account was linked.
  Future<List<DayPoint>> history(String playerId, int days) async {
    final json = await _send('GET', '/v1/players/$playerId/history', query: {'days': '$days', 'tzOffset': '$_tzOffset'});
    return [for (final d in (json['history'] as List? ?? const [])) DayPoint.fromJson(d as Map<String, dynamic>)];
  }

  Future<void> unlink(String playerId) => _send('DELETE', '/v1/players/$playerId');

  Future<MapRotation> apexMaps() async => MapRotation.fromJson(await _send('GET', '/v1/apex/maps'));
}
