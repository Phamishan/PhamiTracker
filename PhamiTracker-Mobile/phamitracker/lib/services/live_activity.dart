import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The automatic Live Activity setting. The work happens natively (AppDelegate.swift) and on the
/// worker (live.js): with it on, the worker starts a lock screen / Dynamic Island activity when
/// the player starts playing, updates it after every game and ends it after a 45 minute break.
/// Everything is a no-op off iOS (and in tests).
class LiveActivityService {
  static const _channel = MethodChannel('phamitracker/live_activity');

  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb;

  /// iOS 17.2+ (needed for the worker to start activities by push).
  Future<bool> supported() => _ask('supported');

  /// Live Activities allowed for PhamiTracker in iOS Settings.
  Future<bool> allowed() => _ask('allowed');

  /// Turns it on (registers this phone for the linked players) or fully off (ends any running
  /// activity and unregisters). Call again after linking or unlinking an account.
  Future<void> setEnabled(bool enabled) async {
    if (!_ios) return;
    try {
      await _channel.invokeMethod<void>('setEnabled', enabled);
    } on PlatformException {
      // Nothing to register with; the setting is still saved.
    } on MissingPluginException {
      // Not on iOS.
    }
  }

  Future<bool> _ask(String method) async {
    if (!_ios) return false;
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
