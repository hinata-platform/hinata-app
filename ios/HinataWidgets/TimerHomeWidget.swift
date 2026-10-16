import AppIntents
import SwiftUI
import WidgetKit

/// The running timer on the home screen and the lock screen.
///
/// The app writes one record when the timer changes and asks for a reload;
/// in between nothing reloads. The time ticks by itself, and the timeline
/// already holds the moments the widget changes on its own: the end of the
/// stretch, and the expiry of the copy, after which it shows idle.
struct TimerHomeWidget: Widget {
  static let kind = "HinataTimerWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: Self.kind, provider: TimerWidgetProvider()) { entry in
      TimerWidgetView(entry: entry)
        .widgetURL(timerFocusURL)
        .modifier(WidgetBackground())
    }
    .configurationDisplayName(Text("widget.name", bundle: .main))
    .description(Text("widget.description", bundle: .main))
    .supportedFamilies([
      .systemSmall, .systemMedium,
      .accessoryCircular, .accessoryRectangular, .accessoryInline,
    ])
  }
}

struct TimerWidgetEntry: TimelineEntry {
  let date: Date
  let record: TimerWidgetRecord?
  /// Whether the stretch on display is over at [date].
  var over = false
}

struct TimerWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> TimerWidgetEntry {
    TimerWidgetEntry(
      date: Date(),
      record: TimerWidgetRecord(
        startedAt: Date().addingTimeInterval(-25 * 60),
        validUntil: Date().addingTimeInterval(3600),
        title: nil
      )
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (TimerWidgetEntry) -> Void) {
    completion(context.isPreview && TimerWidgetRecord.load() == nil
      ? placeholder(in: context)
      : entries(now: Date()).first!)
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<TimerWidgetEntry>) -> Void) {
    completion(Timeline(entries: entries(now: Date()), policy: .never))
  }

  /// Now, the end of the stretch and the expiry of the copy, whichever of them
  /// are still ahead.
  func entries(now: Date) -> [TimerWidgetEntry] {
    guard let record = TimerWidgetRecord.load() else {
      return [TimerWidgetEntry(date: now, record: nil)]
    }
    guard record.isRunning, let validUntil = record.validUntil, validUntil > now else {
      return [TimerWidgetEntry(date: now, record: record.idleOnly)]
    }
    var entries = [TimerWidgetEntry(date: now, record: record, over: (record.endsAt ?? .distantFuture) <= now)]
    if let end = record.endsAt, end > now, end < validUntil {
      entries.append(TimerWidgetEntry(date: end, record: record, over: true))
    }
    entries.append(TimerWidgetEntry(date: validUntil, record: record.idleOnly))
    return entries
  }
}

struct TimerWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: TimerWidgetEntry

  private var record: TimerWidgetRecord? { entry.record }
  private var running: Bool { record?.isRunning ?? false }

  /// What the widget says on top: the stretch, its end, or idle.
  private var heading: String {
    guard let record, running else {
      return record?.idle ?? String(localized: "widget.name")
    }
    if entry.over, let over = record.over { return over }
    return record.title ?? ""
  }

  var body: some View {
    switch family {
    case .accessoryInline:
      // One line: the time while it runs, the words once it is over.
      if running && !entry.over {
        Label { clock } icon: { glyph }
      } else {
        Label { Text(heading) } icon: { glyph }
      }
    case .accessoryCircular:
      ZStack {
        AccessoryWidgetBackground()
        VStack(spacing: 0) {
          glyph.font(.caption)
          if running {
            clock
              .font(.system(.caption, design: .rounded).monospacedDigit().weight(.semibold))
              .multilineTextAlignment(.center)
              .minimumScaleFactor(0.6)
          } else {
            Text(verbatim: "–").font(.caption)
          }
        }
        .padding(4)
      }
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 1) {
        // Over, the sentence takes the room of the clock that rests at zero.
        Label { Text(heading).font(.headline).lineLimit(entry.over ? 3 : 1) } icon: { glyph }
        if running && !entry.over {
          clock.font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
          if let label = record?.label {
            Text(label).font(.caption).lineLimit(1).foregroundStyle(.secondary)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .systemMedium:
      HStack(spacing: 12) {
        glyph
          .font(.largeTitle)
          .frame(width: 64, height: 64)
          .background(HinataPalette.honey.opacity(0.18), in: Circle())
        VStack(alignment: .leading, spacing: 4) {
          Text(heading).font(.headline).foregroundStyle(.white).lineLimit(2)
          if running {
            clock
              .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
              .foregroundStyle(HinataPalette.honey)
            if let label = record?.label {
              Text(label).font(.subheadline).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
            }
          }
        }
        Spacer(minLength: 0)
        actions(axis: .vertical)
      }
    default:
      VStack(alignment: .leading, spacing: 6) {
        HStack(alignment: .top, spacing: 6) {
          glyph.font(.title2)
          Spacer(minLength: 0)
          actions(axis: .horizontal)
        }
        Spacer(minLength: 0)
        Text(heading).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
        if running {
          clock
            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(HinataPalette.honey)
            .minimumScaleFactor(0.6)
          if let label = record?.label {
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
  }

  /// Stop, and for a Pomodoro the next phase, without opening the app
  /// (HIN-103, iOS 17). Only while the stretch runs; over, a tap on the widget
  /// opens the focus screen as before. Idle, a start button starts a stopwatch
  /// (HIN-105).
  @ViewBuilder private func actions(axis: Axis) -> some View {
    if #available(iOSApplicationExtension 17.0, *), let record {
      let layout = axis == .vertical
        ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 6))
      if running, !entry.over, let stop = record.stop {
        layout {
          if let advance = record.advance {
            TimerWidgetButton(
              title: advance, symbol: record.isBreak ? "play.fill" : "cup.and.saucer.fill",
              intent: AdvancePhaseIntent())
          }
          TimerWidgetButton(title: stop, symbol: "stop.fill", intent: StopTimerIntent())
        }
      } else if !running, let start = record.start {
        TimerWidgetButton(title: start, symbol: "play.fill", intent: StartTimerIntent())
      }
    }
  }

  private var glyph: some View {
    Image(systemName: symbol)
      .foregroundStyle(HinataPalette.honey)
      .widgetAccentable()
      .accessibilityHidden(true)
  }

  private var symbol: String {
    guard running, let record else { return "timer" }
    if record.isBreak { return "cup.and.saucer.fill" }
    return record.countsDown ? "hourglass" : "timer"
  }

  /// Ticks by itself, without a reload.
  @ViewBuilder private var clock: some View {
    if let record, let start = record.startedAt {
      if let end = record.endsAt {
        if entry.over || end <= start {
          Text(verbatim: "0:00")
        } else {
          Text(timerInterval: start...end, countsDown: true)
        }
      } else {
        Text(timerInterval: start...(record.validUntil ?? start.addingTimeInterval(86_400)),
          countsDown: false)
      }
    }
  }
}

/// One round button of the widget. The word is its accessible name; the
/// glyph alone is drawn, so it fits the small widget in every language.
@available(iOSApplicationExtension 17.0, *)
private struct TimerWidgetButton<Intent: AppIntent>: View {
  let title: String
  let symbol: String
  let intent: Intent

  var body: some View {
    Button(intent: intent) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(HinataPalette.navy)
        .frame(width: 36, height: 36)
        .background(HinataPalette.honey, in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}

/// The navy card of the home screen widgets; the lock screen draws its own.
private struct WidgetBackground: ViewModifier {
  @Environment(\.widgetFamily) private var family

  func body(content: Content) -> some View {
    let accessory = [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family)
    if #available(iOSApplicationExtension 17.0, *) {
      content.containerBackground(for: .widget) {
        if accessory { Color.clear } else { HinataPalette.navy }
      }
    } else if accessory {
      content
    } else {
      content.padding().background(HinataPalette.navy)
    }
  }
}
