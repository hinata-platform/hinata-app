import AppIntents
import Foundation

// The timer for Siri, the Shortcuts app, Spotlight, the Action button and
// the controls (HIN-105).
//
// Member of the Runner and of HinataWidgets: the controls in the extension
// name these intents, and the system runs every one that acts on the timer
// in the app's process (`LiveActivityIntent`), in the background, where the
// Runner set [TimerIntentBridge]. In the extension the bridge stays empty and
// `perform` never acts. Nothing here talks to the server; the Dart action does,
// with the same requests as the buttons in the app.

/// One request to the Dart side of the app.
struct TimerIntentRequest {
  enum Command: String {
    case start, stop, advancePhase
  }

  var command: Command
  var description: String?
  var projectId: String?
}

/// How a request ended, as the Dart action names it.
enum TimerIntentOutcome: String {
  case done, nothingRunning, alreadyRunning, notPomodoro, locked, signedOut, failed
}

/// What the Runner plugs in at launch. Empty in the widget extension.
enum TimerIntentBridge {
  /// Runs a request in the app's headless engine and answers its outcome.
  static var perform: ((TimerIntentRequest) async -> TimerIntentOutcome)?

  /// Opens an in-app route in the app's own engine, now or once it runs.
  static var openRoute: ((String) -> Void)?

  /// Asks the controls to read the timer again.
  static var reloadControls: (() -> Void)?

  static func run(_ request: TimerIntentRequest) async -> TimerIntentOutcome {
    guard let perform else { return .failed }
    let outcome = await perform(request)
    reloadControls?()
    return outcome
  }
}

/// Strings of the intents, the controls and Siri's answers, in nine languages.
func intentText(_ key: String.LocalizationValue) -> String {
  String(localized: key, table: "AppIntents")
}

@available(iOS 17.0, *)
extension TimerIntentOutcome {
  /// What Siri says after [command].
  func dialog(for command: TimerIntentRequest.Command) -> IntentDialog {
    let text: String
    switch self {
    case .done:
      switch command {
      case .start: text = intentText("result.started")
      case .stop: text = intentText("result.stopped")
      case .advancePhase: text = intentText("result.advanced")
      }
    case .nothingRunning: text = intentText("result.nothingRunning")
    case .alreadyRunning: text = intentText("result.alreadyRunning")
    case .notPomodoro: text = intentText("result.notPomodoro")
    case .locked: text = intentText("result.locked")
    case .signedOut: text = intentText("result.signedOut")
    case .failed: text = intentText("result.failed")
    }
    return IntentDialog(stringLiteral: text)
  }
}

/// Starts a stopwatch, optionally with a description and a project.
@available(iOS 17.0, *)
struct StartTimerIntent: LiveActivityIntent {
  static var title = LocalizedStringResource("intent.start.title", table: "AppIntents")
  static var description = IntentDescription(
    LocalizedStringResource("intent.start.description", table: "AppIntents"))
  static var authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

  @Parameter(title: LocalizedStringResource("intent.param.description", table: "AppIntents"))
  var text: String?

  @Parameter(title: LocalizedStringResource("intent.param.project", table: "AppIntents"))
  var project: ProjectEntity?

  init() {}

  init(project: ProjectEntity?) {
    self.project = project
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let description = text?.trimmingCharacters(in: .whitespacesAndNewlines)
    let outcome = await TimerIntentBridge.run(
      TimerIntentRequest(
        command: .start,
        description: (description?.isEmpty ?? true) ? nil : description,
        projectId: project?.id))
    return .result(dialog: outcome.dialog(for: .start))
  }
}

/// Stops the running timer, or ends the session during a break.
@available(iOS 17.0, *)
struct StopTimerIntent: LiveActivityIntent {
  static var title = LocalizedStringResource("intent.stop.title", table: "AppIntents")
  static var description = IntentDescription(
    LocalizedStringResource("intent.stop.description", table: "AppIntents"))
  static var authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let outcome = await TimerIntentBridge.run(TimerIntentRequest(command: .stop))
    return .result(dialog: outcome.dialog(for: .stop))
  }
}

/// Turns a Pomodoro to its next phase: a break after work, work after a break.
@available(iOS 17.0, *)
struct AdvancePhaseIntent: LiveActivityIntent {
  static var title = LocalizedStringResource("intent.advance.title", table: "AppIntents")
  static var description = IntentDescription(
    LocalizedStringResource("intent.advance.description", table: "AppIntents"))
  static var authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let outcome = await TimerIntentBridge.run(TimerIntentRequest(command: .advancePhase))
    return .result(dialog: outcome.dialog(for: .advancePhase))
  }
}

/// Says how long the timer runs and in which phase, from what the lock screen
/// shows: the record in the App Group, without the network and without the
/// description.
@available(iOS 17.0, *)
struct TimerStatusIntent: AppIntent {
  static var title = LocalizedStringResource("intent.status.title", table: "AppIntents")
  static var description = IntentDescription(
    LocalizedStringResource("intent.status.description", table: "AppIntents"))
  static var authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

  func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
    let text = TimerStatusText.make(record: TimerWidgetRecord.load(), now: Date())
    return .result(value: text, dialog: IntentDialog(stringLiteral: text))
  }
}

/// The sentence of [TimerStatusIntent], apart so it can be tested.
enum TimerStatusText {
  static func make(record: TimerWidgetRecord?, now: Date) -> String {
    guard let record, record.isRunning, let start = record.startedAt,
      let validUntil = record.validUntil, validUntil > now
    else { return intentText("status.idle") }
    let title = record.title ?? intentText("intent.toggle.title")
    if let end = record.endsAt {
      guard end > now else { return record.over ?? intentText("status.over") }
      return String(
        format: intentText("status.remaining"), title, duration(end.timeIntervalSince(now)))
    }
    return String(
      format: intentText("status.elapsed"), title, duration(now.timeIntervalSince(start)))
  }

  /// "25 minutes", "1 hour, 5 minutes", in the system's language.
  static func duration(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .full
    formatter.allowedUnits = seconds < 60 ? [.second] : [.hour, .minute]
    formatter.maximumUnitCount = 2
    return formatter.string(from: max(seconds, 0)) ?? ""
  }
}

/// The one place [OpenFocusIntent] leads to.
@available(iOS 17.0, *)
enum TimerScreen: String, AppEnum {
  case focus

  static var typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("enum.screen.type", table: "AppIntents"))
  static var caseDisplayRepresentations: [TimerScreen: DisplayRepresentation] = [
    .focus: DisplayRepresentation(
      title: LocalizedStringResource("enum.screen.focus", table: "AppIntents"))
  ]
}

/// Opens the focus screen. An `OpenIntent`, so the system brings the app to
/// the front first; no `openAppWhenRun`.
@available(iOS 17.0, *)
struct OpenFocusIntent: OpenIntent {
  static var title = LocalizedStringResource("intent.focus.title", table: "AppIntents")
  static var description = IntentDescription(
    LocalizedStringResource("intent.focus.description", table: "AppIntents"))

  @Parameter(title: LocalizedStringResource("enum.screen.type", table: "AppIntents"))
  var target: TimerScreen

  init() {
    target = .focus
  }

  func perform() async throws -> some IntentResult {
    TimerIntentBridge.openRoute?("/time/focus")
    return .result()
  }
}

/// The value of the timer control: on starts a stopwatch, off stops it.
@available(iOS 18.0, *)
struct TimerToggleIntent: SetValueIntent, LiveActivityIntent {
  static var title = LocalizedStringResource("intent.toggle.title", table: "AppIntents")
  static var isDiscoverable = false
  static var authenticationPolicy = IntentAuthenticationPolicy.requiresAuthentication

  @Parameter(title: LocalizedStringResource("intent.toggle.title", table: "AppIntents"))
  var value: Bool

  func perform() async throws -> some IntentResult {
    _ = await TimerIntentBridge.run(TimerIntentRequest(command: value ? .start : .stop))
    return .result()
  }
}

/// The kinds of the three controls in HinataWidgets, which the app reloads.
enum TimerControlKind {
  static let toggle = "HinataTimerToggle"
  static let advance = "HinataTimerAdvance"
  static let focus = "HinataTimerFocus"
  static let all = [toggle, advance, focus]
}

// MARK: - Projects

/// One of the person's projects, from the snapshot the app keeps in the App
/// Group: the id and the name, nothing else.
@available(iOS 17.0, *)
struct ProjectEntity: AppEntity, Identifiable {
  static var typeDisplayRepresentation = TypeDisplayRepresentation(
    name: LocalizedStringResource("entity.project.type", table: "AppIntents"))
  static var defaultQuery = ProjectQuery()

  var id: String
  var name: String

  var displayRepresentation: DisplayRepresentation {
    DisplayRepresentation(title: "\(name)")
  }
}

@available(iOS 17.0, *)
struct ProjectQuery: EntityStringQuery {
  func entities(for identifiers: [ProjectEntity.ID]) async throws -> [ProjectEntity] {
    let wanted = Set(identifiers)
    return ProjectSnapshot.load().filter { wanted.contains($0.id) }
  }

  func entities(matching string: String) async throws -> [ProjectEntity] {
    ProjectSnapshot.search(string)
  }

  func suggestedEntities() async throws -> [ProjectEntity] {
    Array(ProjectSnapshot.load().prefix(ProjectSnapshot.suggested))
  }
}

/// The projects the app last wrote: at most [limit], sorted by name, removed
/// when the person signs out.
enum ProjectSnapshot {
  static let key = "hinata_projects"
  static let limit = 200
  static let suggested = 10

  @available(iOS 17.0, *)
  static func load() -> [ProjectEntity] {
    guard let raw = UserDefaults(suiteName: TimerWidgetRecord.appGroup)?.string(forKey: key)
    else { return [] }
    return parse(raw).map { ProjectEntity(id: $0.id, name: $0.name) }
  }

  @available(iOS 17.0, *)
  static func search(_ text: String) -> [ProjectEntity] {
    let needle = text.trimmingCharacters(in: .whitespaces)
    let all = load()
    guard !needle.isEmpty else { return all }
    return all.filter {
      $0.name.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }

  /// Pairs of id and name; anything else in the record is ignored.
  static func parse(_ raw: String) -> [(id: String, name: String)] {
    guard let data = raw.data(using: .utf8),
      let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    else { return [] }
    return list.prefix(limit).compactMap { item in
      guard let id = item["id"] as? String, let name = item["name"] as? String,
        !id.isEmpty, !name.isEmpty
      else { return nil }
      return (id, name)
    }
  }
}
