import Flutter
import UIKit
import alarm_kit
import UserNotifications
import flutter_local_notifications

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
    // HIN-103: a notification button acts on the timer in a background engine
    // of its own, without opening the app. That engine needs the plugins and
    // the Live Activity channel too. Widget, Live Activity and control buttons
    // run App Intents instead (HIN-105, `HinataIntentEngine`).
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      AppDelegate.registerBackgroundPlugins(registry)
    }
    // HIN-105: Siri, Shortcuts and the controls run their intents in this
    // process; a request goes to a headless engine, a route to the app's own.
    TimerIntentBridge.perform = { request in await HinataIntentEngine.perform(request) }
    TimerIntentBridge.openRoute = { route in HinataAppIntentsChannel.openRoute(route) }
    TimerIntentBridge.reloadControls = { HinataAppIntentsChannel.reloadControls() }
    // HIN-106: the buttons of an alarm are the same intents, by the keys the
    // Dart side names; they run in this process like the ones above.
    if #available(iOS 17.0, *) {
      AlarmKitIntents.register { key in
        switch key {
        case "stop": return StopTimerIntent()
        case "advancePhase": return AdvancePhaseIntent()
        default: return nil
        }
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

    // Hinata: Siri, Shortcuts und Controls (HIN-105).
    HinataAppIntentsChannel.register(with: engineBridge.applicationRegistrar.messenger())
  }

  /// A notification button that acts in the background (HIN-103) runs its Dart
  /// action in an engine of its own, after flutter_local_notifications has
  /// already told iOS it is done. Without time asked for here, iOS suspends the
  /// app before that action reaches the server. Twenty seconds are plenty for
  /// one request, and the task ends by itself.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier.hasPrefix("timer.") {
      let application = UIApplication.shared
      var task = UIBackgroundTaskIdentifier.invalid
      task = application.beginBackgroundTask(withName: "hinata.timer.action") {
        application.endBackgroundTask(task)
        task = .invalid
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        guard task != .invalid else { return }
        application.endBackgroundTask(task)
        task = .invalid
      }
    }
    super.userNotificationCenter(
      center, didReceive: response, withCompletionHandler: completionHandler)
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
