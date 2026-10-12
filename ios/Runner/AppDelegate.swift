import Flutter
import UIKit
import UserNotifications
import flutter_local_notifications
import home_widget

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
    // HIN-103: a notification button or a widget button acts on the timer in a
    // background engine of its own, without opening the app. Those engines need
    // the plugins and the Live Activity channel too.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      AppDelegate.registerBackgroundPlugins(registry)
    }
    if #available(iOS 17, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        AppDelegate.registerBackgroundPlugins(registry)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Hinata: PDF-Anhänge zeigen ihre Formularfelder erst, wenn wir die
    // Annotationen vorher in die Seiten zeichnen (siehe HinataPdfChannel).
    HinataPdfChannel.register(with: engineBridge.applicationRegistrar.messenger())

    // Hinata: der laufende Timer als Live Activity (HIN-102).
    HinataLiveActivityChannel.register(with: engineBridge.applicationRegistrar.messenger())
  }

  /// The plugins of a background engine, and the Live Activity channel, so a
  /// background action can draw the activity after it stopped the timer.
  static func registerBackgroundPlugins(_ registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
    if let registrar = registry.registrar(forPlugin: "HinataLiveActivityChannel") {
      HinataLiveActivityChannel.register(with: registrar.messenger(), primary: false)
    }
  }
}
