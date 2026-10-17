import FlutterMacOS
import Foundation

/// `hinata/widget_commands`: tells Dart that a button of the Mac's widget
/// left a command in the App Group (HIN-108). The extension posts a Darwin
/// notification after writing it; Dart reads, removes and runs it
/// (`MacTimerWidgetStore`). Nothing travels in the notification itself.
enum HinataWidgetCommandChannel {
  private static let notification = "com.ahmadre.hinata.widget-command"
  private static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "hinata/widget_commands", binaryMessenger: messenger)
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), nil,
      { _, _, _, _, _ in
        DispatchQueue.main.async { HinataWidgetCommandChannel.channel?.invokeMethod("command", arguments: nil) }
      },
      notification as CFString, nil, .deliverImmediately)
  }
}
