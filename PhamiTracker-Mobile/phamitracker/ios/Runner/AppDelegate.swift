import ActivityKit
import Flutter
import UIKit
import UserNotifications
import WidgetKit

/// App Group shared with the widget extension (must match both targets' entitlements).
let phamiTrackerAppGroup = "group.phamishan.phamitracker"

/// A ranked session on the lock screen / Dynamic Island. Declared identically in
/// PhamiTrackerWidget.swift (ActivityKit matches the two by name). The worker's live.js starts,
/// updates and ends it through APNs, so its keys must match sessionAttributes / sessionState there.
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
  /// The worker's id for the player, so the app can hand back this activity's push token.
  var playerId: String
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // So notifications about favourites also show while the app is open.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Waiting for iOS to hand over the push token (see the phamitracker/notifications channel).
  private var pendingPushToken: FlutterResult?

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    pendingPushToken?(deviceToken.map { String(format: "%02x", $0) }.joined())
    pendingPushToken = nil
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    pendingPushToken?(FlutterError(code: "register_failed", message: error.localizedDescription, details: nil))
    pendingPushToken = nil
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
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

    // Push notifications about favourites: asks permission, then returns the APNs token (hex),
    // or nil if the user said no. Flutter registers it with the worker.
    let notifications = FlutterMethodChannel(name: "phamitracker/notifications", binaryMessenger: registrar.messenger())
    notifications.setMethodCallHandler { [weak self] call, result in
      guard call.method == "requestToken" else {
        result(FlutterMethodNotImplemented)
        return
      }
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
        DispatchQueue.main.async {
          guard granted else {
            result(nil)
            return
          }
          self?.pendingPushToken = result
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }

    let live = FlutterMethodChannel(name: "phamitracker/live_activity", binaryMessenger: registrar.messenger())
    live.setMethodCallHandler { call, result in
      switch call.method {
      case "supported":
        if #available(iOS 17.2, *) { result(true) } else { result(false) }
      case "allowed":
        if #available(iOS 16.2, *) { result(ActivityAuthorizationInfo().areActivitiesEnabled) } else { result(false) }
      case "setEnabled":
        let enabled = (call.arguments as? Bool) ?? false
        if #available(iOS 17.2, *) {
          Task { @MainActor in
            await LiveSessions.shared.setEnabled(enabled)
            result(nil)
          }
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    // Also runs when iOS wakes the app in the background for a push-started activity, so the
    // new activity's push token still reaches the worker.
    if #available(iOS 17.2, *) {
      Task { @MainActor in LiveSessions.shared.resume() }
    }
  }
}

/// Automatic Live Activities. With the setting on, this hands the worker the app's push-to-start
/// token for the linked players; the worker then starts an activity when they start playing and
/// pushes each game to it. Everything here talks to the worker directly (not through Flutter),
/// because iOS may only wake the app briefly in the background.
@available(iOS 17.2, *)
@MainActor
final class LiveSessions {
  static let shared = LiveSessions()

  private let defaults = UserDefaults(suiteName: phamiTrackerAppGroup)
  private var tasks: [Task<Void, Never>] = []
  private var watched = Set<String>()

  #if DEBUG
  private let sandbox = true
  #else
  private let sandbox = false
  #endif

  private var enabled: Bool { defaults?.bool(forKey: "liveEnabled") ?? false }

  func setEnabled(_ on: Bool) async {
    defaults?.set(on, forKey: "liveEnabled")
    if on {
      // Linked accounts may have changed: send the token again with the current players.
      defaults?.removeObject(forKey: "liveSubscribed")
      resume()
      await subscribe()
    } else {
      await disable()
    }
  }

  /// Starts listening for tokens and new activities (no-op when the setting is off).
  func resume() {
    guard enabled, tasks.isEmpty else { return }
    tasks.append(Task { [weak self] in
      for await data in Activity<PhamiSessionAttributes>.pushToStartTokenUpdates {
        self?.defaults?.set(Self.hex(data), forKey: "liveStartToken")
        await self?.subscribe()
      }
    })
    tasks.append(Task { [weak self] in
      for await activity in Activity<PhamiSessionAttributes>.activityUpdates {
        self?.watch(activity)
      }
    })
    for activity in Activity<PhamiSessionAttributes>.activities { watch(activity) }
  }

  /// Hands each activity's own push token to the worker, which pushes every game to it.
  private func watch(_ activity: Activity<PhamiSessionAttributes>) {
    guard !watched.contains(activity.id) else { return }
    watched.insert(activity.id)
    tasks.append(Task { [weak self] in
      for await data in activity.pushTokenUpdates {
        guard let self else { return }
        let token = Self.hex(data)
        var known = self.defaults?.dictionary(forKey: "liveActivityTokens") as? [String: String] ?? [:]
        known[token] = activity.attributes.playerId
        self.defaults?.set(known, forKey: "liveActivityTokens")
        await self.request("POST", "/v1/players/\(activity.attributes.playerId)/live-activity",
                           body: ["token": token, "sandbox": self.sandbox])
      }
    })
  }

  private func subscribe() async {
    guard enabled, let token = defaults?.string(forKey: "liveStartToken") else { return }
    let players = linkedPlayers()
    let signature = "\(token)|\(players.sorted().joined(separator: ","))"
    guard defaults?.string(forKey: "liveSubscribed") != signature else { return }
    if await request("POST", "/v1/live/subscribe", body: ["token": token, "sandbox": sandbox, "players": players]) {
      defaults?.set(signature, forKey: "liveSubscribed")
    }
  }

  /// Turned off: stop listening, close any running activity and tell the worker to forget us.
  private func disable() async {
    tasks.forEach { $0.cancel() }
    tasks.removeAll()
    watched.removeAll()
    for activity in Activity<PhamiSessionAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    if let token = defaults?.string(forKey: "liveStartToken") {
      await request("DELETE", "/v1/live/subscribe/\(token)")
    }
    let known = defaults?.dictionary(forKey: "liveActivityTokens") as? [String: String] ?? [:]
    for (token, playerId) in known {
      await request("DELETE", "/v1/players/\(playerId)/live-activity/\(token)")
    }
    for key in ["liveActivityTokens", "liveSubscribed"] { defaults?.removeObject(forKey: key) }
  }

  // MARK: Worker

  private struct Config: Decodable {
    struct Game: Decodable { let playerId: String }
    let apiUrl: String
    let appKey: String
    let games: [String: Game]
  }

  /// Worker URL, app key and linked players, as the app saved them for the widgets.
  private func config() -> Config? {
    guard let json = defaults?.string(forKey: "config"), let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(Config.self, from: data)
  }

  private func linkedPlayers() -> [String] { config()?.games.values.map(\.playerId) ?? [] }

  @discardableResult
  private func request(_ method: String, _ path: String, body: [String: Any]? = nil) async -> Bool {
    guard let config = config(), let url = URL(string: config.apiUrl + path) else { return false }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.httpMethod = method
    request.setValue(config.appKey, forHTTPHeaderField: "x-app-key")
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    if let body { request.httpBody = try? JSONSerialization.data(withJSONObject: body) }
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      return ((response as? HTTPURLResponse)?.statusCode ?? 500) < 400
    } catch {
      return false
    }
  }

  private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
