import AppIntents
import AppKit
import Foundation

// The buttons of the Mac's widget (HIN-108), under the names the iPhone's
// widget gives its intents, so `TimerHomeWidget` draws the same buttons here.
//
// macOS runs a widget's intent in the extension, which has neither the
// network nor the person's session. So an intent only hands its command to
// the app: into the App Group, then a Darwin notification the app listens for
// (`HinataWidgetCommandChannel`). When the app is not running, it opens in
// the background and finds the command at launch. Either way the app makes
// the same request as its own button, and redraws the widget.

/// Starts a stopwatch.
struct StartTimerIntent: AppIntent {
  static var title = LocalizedStringResource("intent.start.title", table: "AppIntents")
  static var isDiscoverable = false

  func perform() async throws -> some IntentResult {
    WidgetCommand.send("start")
    return .result()
  }
}

/// Stops the running timer, or ends the session during a break.
struct StopTimerIntent: AppIntent {
  static var title = LocalizedStringResource("intent.stop.title", table: "AppIntents")
  static var isDiscoverable = false

  func perform() async throws -> some IntentResult {
    WidgetCommand.send("stop")
    return .result()
  }
}

/// Turns a Pomodoro to its next phase.
struct AdvancePhaseIntent: AppIntent {
  static var title = LocalizedStringResource("intent.advance.title", table: "AppIntents")
  static var isDiscoverable = false

  func perform() async throws -> some IntentResult {
    WidgetCommand.send("advancePhase")
    return .result()
  }
}

/// The hand-over to the app. The key and the notification are the app's
/// (`timerWidgetCommandKey` in Dart, `HinataWidgetCommandChannel` in Swift).
enum WidgetCommand {
  static let key = "hinata_widget_command"
  static let notification = "com.ahmadre.hinata.widget-command"

  /// The app this extension is embedded in: `Hinata.app/Contents/PlugIns/`.
  private static let appURL = Bundle.main.bundleURL
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

  static func send(_ command: String) {
    let record: [String: Any] = [
      "command": command, "at": Int(Date().timeIntervalSince1970 * 1000),
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: record),
      let raw = String(data: data, encoding: .utf8)
    else { return }
    UserDefaults(suiteName: TimerWidgetRecord.appGroup)?.set(raw, forKey: key)

    let appID = Bundle(url: appURL)?.bundleIdentifier ?? "com.ahmadre.hinata"
    if NSRunningApplication.runningApplications(withBundleIdentifier: appID).isEmpty {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = false
      NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    } else {
      CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(notification as CFString), nil, nil, true)
    }
  }
}
