import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Push notifications about favourite players (rank changes, streaks, session recaps). The
/// worker sends them; this only asks iOS for permission and the phone's push token.
class NotificationService {
  static const _channel = MethodChannel('phamitracker/notifications');

  bool get supported => defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;

  /// Asks for permission (iOS only prompts the first time) and returns the push token, or null
  /// if notifications aren't allowed.
  Future<String?> requestToken() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('requestToken');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
