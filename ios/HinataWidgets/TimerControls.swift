import AppIntents
import SwiftUI
import WidgetKit

// The timer in Control Center, on the lock screen and on the Action button
// (HIN-105, iOS 18).
//
// Every control acts through an intent the system runs in the app's process,
// so the app does not open; the intents ask for the unlock on a locked phone.
// The app reloads the controls on every change of the timer.

/// On while a timer runs; on starts a stopwatch, off stops the timer.
@available(iOSApplicationExtension 18.0, *)
struct TimerToggleControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: TimerControlKind.toggle, provider: TimerControlValue()) {
      running in
      ControlWidgetToggle(isOn: running, action: TimerToggleIntent()) {
        Label(intentText("intent.toggle.title"), systemImage: "timer")
      } valueLabel: { isOn in
        Label(
          intentText(isOn ? "control.toggle.on" : "control.toggle.off"),
          systemImage: isOn ? "stop.fill" : "play.fill")
      }
      .tint(HinataPalette.honey)
    }
    .displayName(LocalizedStringResource("intent.toggle.title", table: "AppIntents"))
    .description(LocalizedStringResource("control.toggle.description", table: "AppIntents"))
  }
}

/// Whether a timer runs, from the record the app wrote for the widgets.
@available(iOSApplicationExtension 18.0, *)
struct TimerControlValue: ControlValueProvider {
  var previewValue: Bool { false }

  func currentValue() async throws -> Bool {
    guard let record = TimerWidgetRecord.load(), record.isRunning,
      let validUntil = record.validUntil
    else { return false }
    return validUntil > Date()
  }
}

/// A break after work, work after a break.
@available(iOSApplicationExtension 18.0, *)
struct TimerAdvanceControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: TimerControlKind.advance) {
      ControlWidgetButton(action: AdvancePhaseIntent()) {
        Label(intentText("intent.advance.title"), systemImage: "cup.and.saucer.fill")
      }
      .tint(HinataPalette.honey)
    }
    .displayName(LocalizedStringResource("intent.advance.title", table: "AppIntents"))
    .description(LocalizedStringResource("intent.advance.description", table: "AppIntents"))
  }
}

/// Opens the focus screen.
@available(iOSApplicationExtension 18.0, *)
struct TimerFocusControl: ControlWidget {
  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: TimerControlKind.focus) {
      ControlWidgetButton(action: OpenFocusIntent()) {
        Label(intentText("enum.screen.focus"), systemImage: "scope")
      }
      .tint(HinataPalette.honey)
    }
    .displayName(LocalizedStringResource("intent.focus.title", table: "AppIntents"))
    .description(LocalizedStringResource("intent.focus.description", table: "AppIntents"))
  }
}
