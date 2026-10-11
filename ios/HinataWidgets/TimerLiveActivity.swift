import ActivityKit
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
      TimerLockScreenView(state: context.state, stale: isStale(context))
        .activityBackgroundTint(HinataPalette.navy.opacity(0.92))
        .activitySystemActionForegroundColor(HinataPalette.honey)
        .widgetURL(timerFocusURL)
    } dynamicIsland: { context in
      let state = context.state
      let stale = isStale(context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          TimerGlyph(state: state)
            .font(.title2)
            .padding(.leading, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          TimerClock(state: state, stale: stale)
            .font(.title2.monospacedDigit().weight(.semibold))
            .foregroundStyle(HinataPalette.honey)
            .frame(maxWidth: 120, alignment: .trailing)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 2) {
            Text(stale ? (state.staleTitle ?? state.title) : state.title)
              .font(.headline)
            if let label = state.label {
              Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } compactLeading: {
        TimerGlyph(state: state)
      } compactTrailing: {
        TimerClock(state: state, stale: stale)
          .monospacedDigit()
          .foregroundStyle(HinataPalette.honey)
          .frame(maxWidth: 56)
      } minimal: {
        TimerGlyph(state: state)
      }
      .widgetURL(timerFocusURL)
      .keylineTint(HinataPalette.honey)
    }
  }

  private func isStale(_ context: ActivityViewContext<TimerActivityAttributes>) -> Bool {
    if #available(iOSApplicationExtension 16.2, *) {
      return context.isStale
    }
    guard let end = context.state.endsAt else { return false }
    return end <= Date()
  }
}

@available(iOS 16.1, *)
struct TimerLockScreenView: View {
  let state: TimerActivityAttributes.ContentState
  let stale: Bool

  var body: some View {
    HStack(spacing: 14) {
      TimerGlyph(state: state)
        .font(.title)
        .frame(width: 44, height: 44)
        .background(HinataPalette.honey.opacity(0.18), in: Circle())
      VStack(alignment: .leading, spacing: 2) {
        Text(stale ? (state.staleTitle ?? state.title) : state.title)
          .font(.headline)
          .foregroundStyle(.white)
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
        .frame(maxWidth: 150, alignment: .trailing)
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

  var body: some View {
    if let end = state.endsAt {
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
