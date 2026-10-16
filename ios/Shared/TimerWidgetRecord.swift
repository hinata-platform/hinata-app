import Foundation

/// The one record the app writes for the widgets (HIN-102), read from the App
/// Group. Written by `HomeWidgetSurface` in Dart; no ids, and it expires by
/// itself at [validUntil] without the app or the network.
struct TimerWidgetRecord: Equatable {
  static let appGroup = "group.com.ahmadre.hinata"
  static let key = "hinata_timer"

  var startedAt: Date?
  var endsAt: Date?
  var countsDown = false
  var isBreak = false
  var validUntil: Date?
  var label: String?
  var title: String?
  var over: String?
  var idle: String?
  /// The words of the buttons (HIN-103); nil hides a button.
  var stop: String?
  var advance: String?
  /// The word of the start button on the idle widget (HIN-105).
  var start: String?

  var isRunning: Bool { startedAt != nil && validUntil != nil }

  /// The record in the App Group, or nil when the app removed it (signed out,
  /// local copies deleted) or never wrote one.
  static func load() -> TimerWidgetRecord? {
    guard let raw = UserDefaults(suiteName: appGroup)?.string(forKey: key) else { return nil }
    return parse(raw)
  }

  static func parse(_ raw: String) -> TimerWidgetRecord? {
    guard let data = raw.data(using: .utf8),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return nil }
    func date(_ key: String) -> Date? {
      guard let ms = json[key] as? NSNumber else { return nil }
      return Date(timeIntervalSince1970: ms.doubleValue / 1000)
    }
    func text(_ key: String) -> String? {
      guard let value = json[key] as? String, !value.isEmpty else { return nil }
      return value
    }
    return TimerWidgetRecord(
      startedAt: date("startedAt"),
      endsAt: date("endsAt"),
      countsDown: (json["countsDown"] as? Bool) ?? false,
      isBreak: (json["phaseKind"] as? String) == "break",
      validUntil: date("validUntil"),
      label: text("label"),
      title: text("title"),
      over: text("over"),
      idle: text("idle"),
      stop: text("stop"),
      advance: text("advance"),
      start: text("start")
    )
  }

  /// The same record with nothing running: what it shows after [validUntil].
  var idleOnly: TimerWidgetRecord { TimerWidgetRecord(idle: idle, start: start) }
}
