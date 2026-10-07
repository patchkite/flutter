import Flutter
import UIKit

/// iOS: Apple forbids dynamically loading native (AOT) code, so Flutter OTA updates
/// are not supported. The plugin is still provided so the Dart API is the same on both
/// platforms: `checkForUpdate` always returns null and `sync` → UP_TO_DATE.
public class PatchkitePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "patchkite", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PatchkitePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getConfiguration":
      result([
        "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
        "unsupported": true,
      ])
    case "isFailedUpdate", "isFirstRun":
      result(false)
    default:
      result(nil)
    }
  }
}
