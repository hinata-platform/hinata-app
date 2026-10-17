import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

/// The countdown of an interval that ends in an alarm (HIN-106), on the lock
/// screen, in StandBy and in the Dynamic Island. The system draws the ringing
/// alarm itself; this draws the time until then, in the look of the timer's
/// own Live Activity, which steps back for it.
///
/// What it knows comes from the alarm: a generic title, the times and one
/// word (`AlarmKitMetadata.kind`). Stop and the next phase are the app's
/// intents, like on the timer's activity.
@available(iOS 26.0, *)
struct TimerAlarmActivity: Widget {
  typealias Context = ActivityViewContext<AlarmAttributes<AlarmKitMetadata>>

  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlarmAttributes<AlarmKitMetadata>.self) { context in
      AlarmLockScreenView(context: context)
        .activityBackgroundTint(HinataPalette.navy.opacity(0.92))
        .activitySystemActionForegroundColor(HinataPalette.honey)
        .widgetURL(timerFocusURL)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          AlarmGlyph(kind: context.attributes.metadata?.kind)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 40, height: 40)
            .background(HinataPalette.honey.opacity(0.18), in: Circle())
            .padding(.leading, 6)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        DynamicIslandExpandedRegion(.trailing) {
          AlarmClock(state: context.state)
            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(HinataPalette.honey)
            .multilineTextAlignment(.trailing)
            .frame(width: AlarmClock.width(context.state, size: .large), alignment: .trailing)
            .padding(.trailing, 6)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 8) {
            Text(AlarmTitle.of(context))
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white)
              .lineLimit(1)
            HStack(spacing: 10) {
              AlarmProgress(state: context.state)
              Spacer(minLength: 0)
              AlarmButtons(kind: context.attributes.metadata?.kind, size: 36)
            }
          }
          .padding(.horizontal, 6)
        }
      } compactLeading: {
        AlarmGlyph(kind: context.attributes.metadata?.kind)
          .font(.system(size: 14, weight: .semibold))
          .padding(.leading, 2)
      } compactTrailing: {
        AlarmClock(state: context.state)
          .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(HinataPalette.honey)
          .multilineTextAlignment(.trailing)
          .frame(width: AlarmClock.width(context.state, size: .compact), alignment: .trailing)
      } minimal: {
        AlarmGlyph(kind: context.attributes.metadata?.kind)
          .font(.system(size: 14, weight: .semibold))
      }
      .widgetURL(timerFocusURL)
      .keylineTint(HinataPalette.honey)
    }
  }
}

@available(iOS 26.0, *)
private struct AlarmLockScreenView: View {
  let context: TimerAlarmActivity.Context

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 14) {
        AlarmGlyph(kind: context.attributes.metadata?.kind)
          .font(.title2.weight(.semibold))
          .frame(width: 44, height: 44)
          .background(HinataPalette.honey.opacity(0.18), in: Circle())
        Text(AlarmTitle.of(context))
          .font(.headline)
          .foregroundStyle(.white)
          .lineLimit(2)
        Spacer(minLength: 8)
        AlarmClock(state: context.state)
          .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
          .foregroundStyle(HinataPalette.honey)
          .multilineTextAlignment(.trailing)
          .frame(width: AlarmClock.width(context.state, size: .large) + 16, alignment: .trailing)
      }
      HStack(spacing: 12) {
        AlarmProgress(state: context.state)
        Spacer(minLength: 0)
        AlarmButtons(kind: context.attributes.metadata?.kind, size: 40)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
  }
}

/// The countdown's title while it runs, the alarm's once it rings.
@available(iOS 26.0, *)
enum AlarmTitle {
  static func of(_ context: TimerAlarmActivity.Context) -> LocalizedStringResource {
    let presentation = context.attributes.presentation
    switch context.state.mode {
    case .countdown: return presentation.countdown?.title ?? presentation.alert.title
    case .paused: return presentation.paused?.title ?? presentation.alert.title
    default: return presentation.alert.title
    }
  }
}

/// The time left; at rest once the alarm rings.
@available(iOS 26.0, *)
struct AlarmClock: View {
  let state: AlarmPresentationState

  enum Size { case compact, large }

  static func width(_ state: AlarmPresentationState, size: Size) -> CGFloat {
    let hours: Bool
    switch state.mode {
    case .countdown(let countdown): hours = countdown.totalCountdownDuration >= 3600
    case .paused(let paused): hours = paused.totalCountdownDuration >= 3600
    default: hours = false
    }
    return timerClockWidth(hours: hours, large: size == .large)
  }

  var body: some View {
    switch state.mode {
    case .countdown(let countdown):
      Text(timerInterval: Date.now...max(countdown.fireDate, Date.now), countsDown: true)
    case .paused(let paused):
      Text(
        Duration.seconds(max(paused.totalCountdownDuration - paused.previouslyElapsedDuration, 0)),
        format: .time(pattern: .minuteSecond))
    default:
      Text(verbatim: "0:00")
    }
  }
}

/// How far the interval has come, running by itself like the clock.
@available(iOS 26.0, *)
private struct AlarmProgress: View {
  let state: AlarmPresentationState

  var body: some View {
    Group {
      switch state.mode {
      case .countdown(let countdown):
        let start = countdown.fireDate.addingTimeInterval(-countdown.totalCountdownDuration)
        if countdown.fireDate > start {
          ProgressView(timerInterval: start...countdown.fireDate, countsDown: false) {
            EmptyView()
          } currentValueLabel: {
            EmptyView()
          }
        }
      case .paused(let paused):
        ProgressView(
          value: min(paused.previouslyElapsedDuration / max(paused.totalCountdownDuration, 1), 1))
      default:
        ProgressView(value: 1)
      }
    }
    .progressViewStyle(.linear)
    .tint(HinataPalette.honey)
    .labelsHidden()
  }
}

/// Stop, and in a Pomodoro the next phase: the same intents as on the timer's
/// own activity, so the person never loses the stop button to the alarm.
@available(iOS 26.0, *)
private struct AlarmButtons: View {
  let kind: String?
  let size: CGFloat

  var body: some View {
    HStack(spacing: 10) {
      if kind == "work" || kind == "break" {
        TimerActivityButton(
          title: intentText("intent.advance.title"),
          symbol: kind == "break" ? "play.fill" : "cup.and.saucer.fill",
          size: size, prominent: false, intent: AdvancePhaseIntent())
      }
      TimerActivityButton(
        title: intentText("intent.stop.title"), symbol: "stop.fill",
        size: size, prominent: true, intent: StopTimerIntent())
    }
  }
}

@available(iOS 26.0, *)
private struct AlarmGlyph: View {
  let kind: String?

  var body: some View {
    Image(systemName: symbol)
      .foregroundStyle(HinataPalette.honey)
      .accessibilityHidden(true)
  }

  private var symbol: String {
    switch kind {
    case "work": return "circle.circle.fill"
    case "break": return "cup.and.saucer.fill"
    default: return "hourglass"
    }
  }
}
