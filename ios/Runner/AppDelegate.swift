import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Two plugins answer notifications: firebase_messaging (push) and
    // flutter_local_notifications (timer alerts, HIN-100). Making the
    // FlutterAppDelegate the center's delegate lets it fan every callback out
    // to both plugins, and firebase detects this setup and leaves the delegate
    // alone instead of replacing it. Note firebase also completes the
    // foreground presentation of local notifications, with the options set by
    // setForegroundNotificationPresentationOptions (alert, badge, sound).
    // Must be set before super, so a tap that launched the app is not lost.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Hinata: PDF-Anhänge zeigen ihre Formularfelder erst, wenn wir die
    // Annotationen vorher in die Seiten zeichnen (siehe HinataPdfChannel).
    HinataPdfChannel.register(with: engineBridge.applicationRegistrar.messenger())
  }
}
