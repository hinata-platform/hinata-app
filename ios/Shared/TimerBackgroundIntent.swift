import AppIntents
import Foundation

#if canImport(home_widget)
  import home_widget
#endif

/// A button on the timer widget (HIN-103): stops the timer or turns its
/// phase without opening the app.
///
/// A `LiveActivityIntent`, so the system runs it in the app's process, in the
/// background, where home_widget hands the link to the Dart action
/// (`timerSurfaceBackgroundAction`). The widget extension only declares it;
/// there `home_widget` is not linked and `perform` never runs. From a locked
/// phone the system asks for the unlock first.
@available(iOS 17.0, *)
struct TimerBackgroundIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "widget.name"
  static var isDiscoverable = false
  static var authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

  @Parameter(title: "widget.name")
  var command: String

  init() {
    command = ""
  }

  init(command: String) {
    self.command = command
  }

  func perform() async throws -> some IntentResult {
    #if canImport(home_widget)
      if ["stop", "advancePhase"].contains(command) {
        await HomeWidgetBackgroundWorker.run(
          url: URL(string: "hinata://timer/\(command)"),
          appGroup: "group.com.ahmadre.hinata")
      }
    #endif
    return .result()
  }
}
