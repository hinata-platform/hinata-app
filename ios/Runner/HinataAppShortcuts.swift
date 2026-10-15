import AppIntents

/// The phrases Siri and Spotlight know for the timer (HIN-105), in
/// `AppShortcuts.xcstrings` in nine languages. Apple extracts the phrases at
/// build time; nothing of the person's goes with them.
@available(iOS 17.0, *)
struct HinataAppShortcuts: AppShortcutsProvider {
  static var shortcutTileColor = ShortcutTileColor.orange

  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartTimerIntent(),
      phrases: [
        "Start a timer in \(.applicationName)",
        "Start the \(.applicationName) timer",
        "Start a timer for \(\.$project) in \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("intent.start.title", table: "AppIntents"),
      systemImageName: "play.fill")
    AppShortcut(
      intent: StopTimerIntent(),
      phrases: [
        "Stop the timer in \(.applicationName)",
        "Stop the \(.applicationName) timer",
      ],
      shortTitle: LocalizedStringResource("intent.stop.title", table: "AppIntents"),
      systemImageName: "stop.fill")
    AppShortcut(
      intent: AdvancePhaseIntent(),
      phrases: [
        "Next phase in \(.applicationName)",
        "Take a break in \(.applicationName)",
      ],
      shortTitle: LocalizedStringResource("intent.advance.title", table: "AppIntents"),
      systemImageName: "cup.and.saucer.fill")
    AppShortcut(
      intent: TimerStatusIntent(),
      phrases: [
        "How long is my \(.applicationName) timer running",
        "\(.applicationName) timer status",
      ],
      shortTitle: LocalizedStringResource("intent.status.title", table: "AppIntents"),
      systemImageName: "timer")
    AppShortcut(
      intent: OpenFocusIntent(),
      phrases: [
        "Open focus in \(.applicationName)"
      ],
      shortTitle: LocalizedStringResource("intent.focus.title", table: "AppIntents"),
      systemImageName: "scope")
  }
}
