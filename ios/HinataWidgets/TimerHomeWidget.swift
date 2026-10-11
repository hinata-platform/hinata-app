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
      if running {
        Label { clock } icon: { glyph }
      } else {
        Label(heading, systemImage: "timer")
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
        Label { Text(heading).font(.headline).lineLimit(1) } icon: { glyph }
        if running {
          clock.font(.system(.title3, design: .rounded).monospacedDigit().weight(.semibold))
          if let label = record?.label {
            Text(label).font(.caption).lineLimit(1).foregroundStyle(.secondary)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    case .systemMedium:
      HStack(spacing: 16) {
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
      }
    default:
      VStack(alignment: .leading, spacing: 6) {
        glyph.font(.title2)
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
