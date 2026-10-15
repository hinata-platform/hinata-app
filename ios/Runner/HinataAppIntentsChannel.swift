import Flutter
import Foundation
import WidgetKit

/// `hinata/app_intents`: the app's side of Siri, Shortcuts and the controls
/// (HIN-105), in the app's own engine.
///
/// Dart writes the project snapshot (id and name, at most 200) and asks for
/// the controls to reload on every change of the timer; Swift hands over the
/// route of an intent that opens the app, kept until Dart is there to take it.
enum HinataAppIntentsChannel {
  private static let channelName = "hinata/app_intents"
  private static var channel: FlutterMethodChannel?

  /// A route that arrived before Dart listened (a cold start from a control).
  private static var pendingRoute: String?
  private static var listening = false

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "reloadControls":
        reloadControls()
        result(nil)
      case "setProjects":
        setProjects(call.arguments as? [[String: Any]])
        result(nil)
      case "takePendingRoute":
        listening = true
        let route = pendingRoute
        pendingRoute = nil
        result(route)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func openRoute(_ route: String) {
    DispatchQueue.main.async {
      guard listening, let channel else {
        pendingRoute = route
        return
      }
      channel.invokeMethod("openRoute", arguments: route)
    }
  }

  static func reloadControls() {
    if #available(iOS 18.0, *) {
      for kind in TimerControlKind.all {
        ControlCenter.shared.reloadControls(ofKind: kind)
      }
    }
  }

  /// Keeps id and name of each project and nothing else; nil removes the
  /// snapshot (signed out).
  private static func setProjects(_ projects: [[String: Any]]?) {
    let defaults = UserDefaults(suiteName: TimerWidgetRecord.appGroup)
    if let projects {
      let minimal: [[String: String]] = projects.prefix(ProjectSnapshot.limit).compactMap {
        guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
        return ["id": id, "name": name]
      }
      if let data = try? JSONSerialization.data(withJSONObject: minimal),
        let raw = String(data: data, encoding: .utf8)
      {
        defaults?.set(raw, forKey: ProjectSnapshot.key)
      }
    } else {
      defaults?.removeObject(forKey: ProjectSnapshot.key)
    }
    if #available(iOS 17.0, *) {
      HinataAppShortcuts.updateAppShortcutParameters()
    }
  }
}

/// The engine that runs an intent's request in Dart (HIN-105): headless, in
/// the app's process, started on the first request and kept for the next.
///
/// Not home_widget's worker. That one only starts once the app's own engine
/// registered a callback, which a launch in the background for Siri or a
/// control never does, and it cannot answer how the request ended.
@MainActor
enum HinataIntentEngine {
  private static let entrypoint = "appIntentMain"
  private static let library = "package:hinata/core/timer_actions/app_intent_action.dart"

  private static var engine: FlutterEngine?
  private static var channel: FlutterMethodChannel?
  private static var ready = false
  private static var waiting: [CheckedContinuation<Bool, Never>] = []

  /// Longer than a request takes, shorter than the system grants an intent.
  private static let patience: TimeInterval = 25

  static func perform(_ request: TimerIntentRequest) async -> TimerIntentOutcome {
    guard await started(), let channel else { return .failed }
    var arguments: [String: Any] = ["command": request.command.rawValue]
    arguments["description"] = request.description
    arguments["projectId"] = request.projectId
    let raw: String? = await withCheckedContinuation { continuation in
      channel.invokeMethod("perform", arguments: arguments) { result in
        continuation.resume(returning: result as? String)
      }
    }
    return raw.flatMap(TimerIntentOutcome.init(rawValue:)) ?? .failed
  }

  /// Whether the Dart side listens; starts it on the first call.
  private static func started() async -> Bool {
    if ready { return true }
    if engine == nil { launch() }
    return await withCheckedContinuation { continuation in
      waiting.append(continuation)
      DispatchQueue.main.asyncAfter(deadline: .now() + patience) {
        MainActor.assumeIsolated { settle(false) }
      }
    }
  }

  private static func launch() {
    let engine = FlutterEngine(
      name: "hinata_intents", project: nil, allowHeadlessExecution: true)
    engine.run(withEntrypoint: entrypoint, libraryURI: library)
    AppDelegate.registerBackgroundPlugins(engine)
    let channel = FlutterMethodChannel(
      name: "hinata/app_intents/background", binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "ready" {
        MainActor.assumeIsolated {
          ready = true
          settle(true)
        }
      }
      result(nil)
    }
    self.engine = engine
    self.channel = channel
  }

  private static func settle(_ value: Bool) {
    let all = waiting
    waiting = []
    for continuation in all {
      continuation.resume(returning: value)
    }
  }
}
