import Cocoa
import FlutterMacOS
import UserNotifications
import app_links

@main
class AppDelegate: FlutterAppDelegate {
  /// Strong reference: `UNUserNotificationCenter.delegate` is weak.
  private var notificationGuard: NotificationCompletionGuard?
  private var launchObserver: NSObjectProtocol?

  override func awakeFromNib() {
    super.awakeFromNib()
    // awakeFromNib can run once per nib that references this object.
    guard launchObserver == nil else { return }
    // firebase_messaging installs its delegate when launching finishes (see
    // NotificationCompletionGuard for why it needs wrapping). The async hop
    // runs after every observer of that notification, firebase's included.
    launchObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: nil
    ) { [weak self] _ in
      DispatchQueue.main.async { self?.installNotificationGuard() }
    }
  }

  private func installNotificationGuard() {
    if let observer = launchObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    let center = UNUserNotificationCenter.current()
    guard notificationGuard == nil, let inner = center.delegate else { return }
    let wrapper = NotificationCompletionGuard(wrapping: inner)
    notificationGuard = wrapper
    center.delegate = wrapper
  }

  /// Set over "hinata/window" while a running timer keeps the app in the menu
  /// bar (HIN-101). AppKit asks the question below also when the last window
  /// is only *hidden*, and a plain `true` then quits the app the moment the
  /// close button hides the window into the menu bar.
  static var keepsRunningInMenuBar = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !AppDelegate.keepsRunningInMenuBar
  }

  /// A click on the Dock icon brings the window back when "keep running when
  /// closed" hid it into the menu bar (HIN-101). The app still quits when its
  /// window really closes; a hidden window is not a closed one.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      for window in sender.windows where window is MainFlutterWindow {
        window.makeKeyAndOrderFront(self)
      }
      sender.activate(ignoringOtherApps: true)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Universal Links (`https://connect.hinata.ahmadre.com/l/…` aus einer E-Mail).
  ///
  /// app_links 6.4.1 hat seine macOS-Implementierung dieser Methode auskommentiert
  /// (siehe `AppLinksMacosPlugin.swift`) — auf dem Mac kam ein Universal Link
  /// deshalb NIE in Dart an, weder beim Kaltstart noch bei laufender App. Nur das
  /// eigene Schema `hinata://` funktionierte, das geht über den AppleEvent-Handler
  /// des Plugins.
  ///
  /// Wir nehmen den Link also selbst entgegen und geben ihn an das Plugin weiter.
  /// `handleLink` ist genau dafür öffentlich: läuft die App schon, feuert es das
  /// Stream-Event; beim Kaltstart (noch kein EventSink) merkt es sich den Link als
  /// `initialLink`, den Dart dann über `getInitialLink()` abholt.
  ///
  /// Seit Flutter 3.47 deklariert `FlutterAppDelegate` diese Methode selbst,
  /// also `override` — und alles, was kein Web-Link ist, geht an `super`, damit
  /// die Weiterleitung der Basisklasse erhalten bleibt (ohne `override` bricht
  /// der Build: "overriding declaration requires an 'override' keyword").
  override func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
  ) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else {
      return super.application(
        application, continue: userActivity, restorationHandler: restorationHandler)
    }
    AppLinks.shared.handleLink(link: url.absoluteString)
    return true
  }
}

/// Makes sure every notification callback is completed exactly once.
///
/// On macOS flutter_local_notifications makes itself the notification center's
/// delegate when it registers; firebase_messaging then replaces it at launch and
/// forwards every callback to it as the "original" delegate. That forwarding
/// skips firebase's own completion, and the local-notifications plugin returns
/// without completing anything that is not its own notification. A push that
/// arrives while the app is in front would therefore never be presented, and
/// its tap response never completed.
///
/// This wrapper sits in front of that chain. It passes everything through and
/// only steps in when nobody completed the call synchronously: a foreground
/// push is then presented with the options Dart set through
/// `setForegroundNotificationPresentationOptions` (firebase keeps them in
/// UserDefaults), exactly as firebase would have done without the forwarding.
final class NotificationCompletionGuard: NSObject, UNUserNotificationCenterDelegate {
  private let inner: UNUserNotificationCenterDelegate

  /// Written by firebase_messaging (`kMessagingPresentationOptionsUserDefaults`).
  private static let firebasePresentationOptionsKey =
    "flutter_firebase_messaging_presentation_options"

  init(wrapping inner: UNUserNotificationCenterDelegate) {
    self.inner = inner
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let once = Once()
    let complete: (UNNotificationPresentationOptions) -> Void = { options in
      if once.claim() { completionHandler(options) }
    }
    inner.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: complete)
    if !once.claimed {
      complete(Self.firebasePresentationOptions())
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let once = Once()
    let complete: () -> Void = {
      if once.claim() { completionHandler() }
    }
    inner.userNotificationCenter?(center, didReceive: response, withCompletionHandler: complete)
    if !once.claimed {
      complete()
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    openSettingsFor notification: UNNotification?
  ) {
    inner.userNotificationCenter?(center, openSettingsFor: notification)
  }

  private static func firebasePresentationOptions() -> UNNotificationPresentationOptions {
    guard let stored = UserDefaults.standard.dictionary(forKey: firebasePresentationOptionsKey)
    else { return [] }
    var options: UNNotificationPresentationOptions = []
    if stored["alert"] as? Bool == true { options.formUnion([.banner, .list]) }
    if stored["badge"] as? Bool == true { options.insert(.badge) }
    if stored["sound"] as? Bool == true { options.insert(.sound) }
    return options
  }

  /// A completion handler may be called once; later calls are dropped.
  private final class Once {
    private(set) var claimed = false

    func claim() -> Bool {
      if claimed { return false }
      claimed = true
      return true
    }
  }
}
