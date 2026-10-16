import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The running timer on the lock screen, in StandBy and in the Dynamic Island.
///
/// The time ticks by itself (`Text(timerInterval:)`) without one update from
/// the app. Once the stretch is over, `staleDate` makes the system draw it
/// again with `isStale`, and the activity says the stretch is over.
@available(iOS 16.1, *)
struct TimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TimerActivityAttributes.self) { context in
      TimerLockScreenView(state: drawn(context), stale: isStale(context))
        .activityBackgroundTint(HinataPalette.navy.opacity(0.92))
        .activitySystemActionForegroundColor(HinataPalette.honey)
        .widgetURL(timerFocusURL)
    } dynamicIsland: { context in
      let state = drawn(context)
      let stale = isStale(context)
      return DynamicIsland {
        // Leading and trailing share one line: what runs on the left, the
        // time on the right, both centred on the same height.
        // The glyph left and the time right share one line around the camera;
        // the words go below, where they have the full width.
        DynamicIslandExpandedRegion(.leading) {
          TimerGlyph(state: state)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(HinataPalette.honey.opacity(0.18), in: Circle())
            .padding(.leading, 6)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        DynamicIslandExpandedRegion(.trailing) {
          TimerClock(state: state, stale: stale)
            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(HinataPalette.honey)
            .multilineTextAlignment(.trailing)
            .frame(width: TimerClock.width(state, size: .large), alignment: .trailing)
            .padding(.trailing, 6)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        DynamicIslandExpandedRegion(.bottom) {
          TimerIslandFooter(state: state, stale: stale)
            .padding(.horizontal, 6)
        }
      } compactLeading: {
        TimerGlyph(state: state)
          .font(.system(size: 14, weight: .semibold))
          .padding(.leading, 2)
      } compactTrailing: {
        TimerClock(state: state, stale: stale)
          .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(HinataPalette.honey)
          .multilineTextAlignment(.trailing)
          .frame(width: TimerClock.width(state, size: .compact), alignment: .trailing)
      } minimal: {
        TimerGlyph(state: state)
          .font(.system(size: 14, weight: .semibold))
      }
      .widgetURL(timerFocusURL)
      .keylineTint(HinataPalette.honey)
    }
  }

  /// The state to draw: a sealed one from the server opened with this
  /// activity's key (HIN-103), or the widget's name without times when it
  /// cannot be.
  private func drawn(
    _ context: ActivityViewContext<TimerActivityAttributes>
  ) -> TimerActivityAttributes.ContentState {
    context.state.resolved(ref: context.attributes.activityRef)
  }

  private func isStale(_ context: ActivityViewContext<TimerActivityAttributes>) -> Bool {
    if #available(iOSApplicationExtension 16.2, *) {
      return context.isStale
    }
    guard let end = drawn(context).endsAt else { return false }
    return end <= Date()
  }
}

/// Under the expanded island: what runs, the description if allowed, and how
/// far a countdown or a phase has come.
@available(iOS 16.1, *)
struct TimerIslandFooter: View {
  let state: TimerActivityAttributes.ContentState
  let stale: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(stale ? (state.staleTitle ?? state.title) : state.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .layoutPriority(1)
        if let label = state.label {
          Text(label)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.65))
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      HStack(spacing: 10) {
        TimerProgress(state: state, stale: stale)
        Spacer(minLength: 0)
        TimerActivityButtons(state: state, size: 36)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Stop, and for a Pomodoro the next phase, right on the activity: in the
/// expanded island, on the lock screen and in Notification Center (HIN-105,
/// iOS 17), like the timer of the Clock app. The intents run in the app's
/// process without opening it; a locked phone asks for the unlock first.
@available(iOS 16.1, *)
struct TimerActivityButtons: View {
  let state: TimerActivityAttributes.ContentState
  let size: CGFloat

  var body: some View {
    if #available(iOSApplicationExtension 17.0, *), !state.hidesTime {
      HStack(spacing: 10) {
        if state.mode == "pomodoro" {
          TimerActivityButton(
            title: intentText("intent.advance.title"),
            symbol: state.isBreak ? "play.fill" : "cup.and.saucer.fill",
            size: size, prominent: false, intent: AdvancePhaseIntent())
        }
        TimerActivityButton(
          title: intentText("intent.stop.title"), symbol: "stop.fill",
          size: size, prominent: true, intent: StopTimerIntent())
      }
    }
  }
}

/// One round button of the activity; the word is its accessible name.
@available(iOSApplicationExtension 17.0, *)
struct TimerActivityButton<Intent: AppIntent>: View {
  let title: String
  let symbol: String
  let size: CGFloat
  let prominent: Bool
  let intent: Intent

  var body: some View {
    Button(intent: intent) {
      Image(systemName: symbol)
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(prominent ? HinataPalette.navy : HinataPalette.honey)
        .frame(width: size, height: size)
        .background(
          prominent ? HinataPalette.honey : HinataPalette.honey.opacity(0.18), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

/// A thin bar from the start to the end of a countdown or a phase. It runs by
/// itself like the clock; the expanded island and the lock screen can carry it,
/// the compact and minimal ones cannot (known to be unstable there).
@available(iOS 16.1, *)
struct TimerProgress: View {
  let state: TimerActivityAttributes.ContentState
  let stale: Bool

  var body: some View {
    if let end = state.endsAt, end > state.startedAt {
      Group {
        if stale {
          ProgressView(value: 1)
        } else {
          ProgressView(timerInterval: state.startedAt...end, countsDown: false) {
            EmptyView()
          } currentValueLabel: {
            EmptyView()
          }
        }
      }
      .progressViewStyle(.linear)
      .tint(HinataPalette.honey)
      .labelsHidden()
    }
  }
}

@available(iOS 16.1, *)
struct TimerLockScreenView: View {
  let state: TimerActivityAttributes.ContentState
  let stale: Bool

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 14) {
        TimerGlyph(state: state)
          .font(.title2.weight(.semibold))
          .frame(width: 44, height: 44)
          .background(HinataPalette.honey.opacity(0.18), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(stale ? (state.staleTitle ?? state.title) : state.title)
            .font(.headline)
            .foregroundStyle(.white)
            .lineLimit(2)
          if let label = state.label {
            Text(label)
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.75))
              .lineLimit(1)
          }
        }
        Spacer(minLength: 8)
        TimerClock(state: state, stale: stale)
          .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(HinataPalette.honey)
          .multilineTextAlignment(.trailing)
          .frame(width: TimerClock.width(state, size: .large) + 16, alignment: .trailing)
      }
      HStack(spacing: 12) {
        TimerProgress(state: state, stale: stale)
        Spacer(minLength: 0)
        TimerActivityButtons(state: state, size: 40)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }
}

/// The running time. Up for a stopwatch, down for a countdown or a phase;
/// past the end of a stretch it rests at zero.
@available(iOS 16.1, *)
struct TimerClock: View {
  let state: TimerActivityAttributes.ContentState
  let stale: Bool

  enum Size { case compact, large }

  /// `Text(timerInterval:)` claims the room of the longest time it could show,
  /// which blew the compact island up to full width. A fixed width per size:
  /// room for hours only where the stretch can reach them.
  static func width(_ state: TimerActivityAttributes.ContentState, size: Size) -> CGFloat {
    let hours = state.endsAt.map { $0.timeIntervalSince(state.startedAt) >= 3600 } ?? true
    switch size {
    case .compact: return hours ? 66 : 52
    case .large: return hours ? 124 : 88
    }
  }

  var body: some View {
    if state.hidesTime {
      EmptyView()
    } else if let end = state.endsAt {
      if stale || end <= state.startedAt {
        Text(verbatim: "0:00")
      } else {
        Text(timerInterval: state.startedAt...end, countsDown: true)
      }
    } else {
      Text(timerInterval: state.startedAt...state.displayEnd, countsDown: false)
    }
  }
}

@available(iOS 16.1, *)
struct TimerGlyph: View {
  let state: TimerActivityAttributes.ContentState

  var body: some View {
    Image(systemName: symbol)
      .foregroundStyle(HinataPalette.honey)
      .accessibilityHidden(true)
  }

  private var symbol: String {
    if state.isBreak { return "cup.and.saucer.fill" }
    switch state.mode {
    case "countdown": return "hourglass"
    case "pomodoro": return "circle.circle.fill"
    default: return "timer"
    }
  }
}
