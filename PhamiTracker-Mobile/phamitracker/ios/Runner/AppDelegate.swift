import Flutter
import UIKit
import WidgetKit

/// App Group shared with the widget extension (must match both targets' entitlements).
let phamiTrackerAppGroup = "group.phamishan.phamitracker"

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
  }
}
