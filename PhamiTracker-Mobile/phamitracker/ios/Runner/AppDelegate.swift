import ActivityKit
import Flutter
import UIKit
import WidgetKit

/// App Group shared with the widget extension (must match both targets' entitlements).
let phamiTrackerAppGroup = "group.phamishan.phamitracker"

/// A ranked session on the lock screen / Dynamic Island. Declared identically in
/// PhamiTrackerWidget.swift (ActivityKit matches the two by name), and ContentState's keys
/// match live_activity.dart and the worker's live.js, which pushes updates through APNs.
@available(iOS 16.1, *)
struct PhamiSessionAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var score: Int
    var rank: String
    var sessionDelta: Int
    var games: Int
    var wins: Int
    var losses: Int
    var lastDelta: Int
    /// Unix seconds.
    var updatedAt: Int
  }

  var game: String
  var player: String
  var unit: String
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhamiTrackerNative") else { return }
    let channel = FlutterMethodChannel(name: "phamitracker/widgets", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "save":
        // Worker URL, accounts, goals and the latest numbers, as JSON. See widget_bridge.dart.
        guard let defaults = UserDefaults(suiteName: phamiTrackerAppGroup) else {
          result(FlutterError(code: "no_app_group", message: "App Group \(phamiTrackerAppGroup) is not enabled", details: nil))
          return
        }
        defaults.set(call.arguments as? String, forKey: "config")
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let live = FlutterMethodChannel(name: "phamitracker/live_activity", binaryMessenger: registrar.messenger())
    liveChannel = live
    live.setMethodCallHandler { [weak self] call, result in
      guard #available(iOS 16.2, *) else {
        result(false)
        return
      }
      self?.handleLiveActivity(call, result: result)
    }
  }

  private var liveChannel: FlutterMethodChannel?
  private var tokenTask: Task<Void, Never>?

  @available(iOS 16.2, *)
  private func handleLiveActivity(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "enabled":
      result(ActivityAuthorizationInfo().areActivitiesEnabled)
    case "running":
      result(!Activity<PhamiSessionAttributes>.activities.isEmpty)
    case "start":
      guard ActivityAuthorizationInfo().areActivitiesEnabled,
            let args, let state = Self.contentState(args["state"])
      else {
        result(false)
        return
      }
      let attributes = PhamiSessionAttributes(
        game: args["game"] as? String ?? "apex",
        player: args["player"] as? String ?? "",
        unit: args["unit"] as? String ?? "RP"
      )
      Task { @MainActor in
        // One session at a time.
        for old in Activity<PhamiSessionAttributes>.activities {
          await old.end(nil, dismissalPolicy: .immediate)
        }
        do {
          let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(2 * 3600)),
            pushType: .token
          )
          self.watchPushToken(activity)
          result(true)
        } catch {
          result(false)
        }
      }
    case "update":
      guard let state = Self.contentState(call.arguments) else {
        result(nil)
        return
      }
      Task { @MainActor in
        for activity in Activity<PhamiSessionAttributes>.activities {
          await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(2 * 3600)))
        }
        result(nil)
      }
    case "end":
      tokenTask?.cancel()
      Task { @MainActor in
        for activity in Activity<PhamiSessionAttributes>.activities {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Hands each push token to Flutter, which registers it with the worker.
  @available(iOS 16.2, *)
  private func watchPushToken(_ activity: Activity<PhamiSessionAttributes>) {
    tokenTask?.cancel()
    tokenTask = Task { [weak self] in
      for await data in activity.pushTokenUpdates {
        let token = data.map { String(format: "%02x", $0) }.joined()
        await MainActor.run { self?.liveChannel?.invokeMethod("token", arguments: token) }
      }
    }
  }

  @available(iOS 16.2, *)
  private static func contentState(_ value: Any?) -> PhamiSessionAttributes.ContentState? {
    guard let map = value as? [String: Any] else { return nil }
    func int(_ key: String) -> Int { (map[key] as? NSNumber)?.intValue ?? 0 }
    return PhamiSessionAttributes.ContentState(
      score: int("score"),
      rank: map["rank"] as? String ?? "",
      sessionDelta: int("sessionDelta"),
      games: int("games"),
      wins: int("wins"),
      losses: int("losses"),
      lastDelta: int("lastDelta"),
      updatedAt: int("updatedAt")
    )
  }
}
