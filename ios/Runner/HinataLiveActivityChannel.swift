import ActivityKit
import Flutter
import Foundation

/// `hinata/live_activity`: the Live Activity of a running timer (HIN-102).
///
/// Local only. The app starts, updates and ends the activity while it runs;
/// the system ticks the time. Keeps at most one activity: `start` adopts one
/// an earlier run left behind and ends any extra, so a relaunch neither
/// duplicates nor blinks.
///
/// A request the system refuses (switched off, or the app is not in front to
/// ask) answers nil instead of an error: the Dart side asks again with the
/// next state, and an error would count against the surface.
enum HinataLiveActivityChannel {
  private static let channelName = "hinata/live_activity"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result(call.method == "areActivitiesEnabled" ? false : nil)
        return
      }
      handle(call, result: result)
    }
    if #available(iOS 16.2, *) {
      // An activity outlived its moment while the app was not running: take
      // it down at the next launch, whatever Dart does after.
      Task { await endExpired() }
    }
  }

  @available(iOS 16.2, *)
  private static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "areActivitiesEnabled":
      result(ActivityAuthorizationInfo().areActivitiesEnabled)
    case "start":
      guard let state = contentState(args) else { return result(nil) }
      Task { result(await start(state)) }
    case "update":
      guard let ref = args["ref"] as? String, let state = contentState(args) else {
        return result(false)
      }
      Task { result(await update(ref: ref, state: state)) }
    case "end":
      let ref = args["ref"] as? String
      Task {
        for activity in Activity<TimerActivityAttributes>.activities
        where ref == nil || activity.attributes.activityRef == ref {
          await activity.end(nil, dismissalPolicy: .immediate)
        }
        result(nil)
      }
    case "endAll":
      Task {
        await endAll()
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 16.2, *)
  private static func start(_ state: TimerActivityAttributes.ContentState) async -> String? {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
    let held = Activity<TimerActivityAttributes>.activities
    if let first = held.first {
      for extra in held.dropFirst() {
        await extra.end(nil, dismissalPolicy: .immediate)
      }
      await first.update(content(state))
      return first.attributes.activityRef
    }
    do {
      let activity = try Activity.request(
        attributes: TimerActivityAttributes(activityRef: UUID().uuidString),
        content: content(state),
        pushType: nil
      )
      return activity.attributes.activityRef
    } catch {
      return nil
    }
  }

  /// False when the activity is gone (swiped away, ended by the system).
  @available(iOS 16.2, *)
  private static func update(ref: String, state: TimerActivityAttributes.ContentState) async -> Bool {
    guard let activity = Activity<TimerActivityAttributes>.activities
      .first(where: { $0.attributes.activityRef == ref }),
      activity.activityState == .active || activity.activityState == .stale
    else { return false }
    await activity.update(content(state))
    return true
  }

  @available(iOS 16.2, *)
  private static func endAll() async {
    for activity in Activity<TimerActivityAttributes>.activities {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  @available(iOS 16.2, *)
  private static func endExpired() async {
    let now = Date()
    for activity in Activity<TimerActivityAttributes>.activities
    where activity.content.state.dismissAt <= now {
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  /// Stale at the end of the stretch, or at the dismissal for a stopwatch, so
  /// the system draws it again at that moment without the app.
  @available(iOS 16.2, *)
  private static func content(
    _ state: TimerActivityAttributes.ContentState
  ) -> ActivityContent<TimerActivityAttributes.ContentState> {
    let stale = min(state.endsAt ?? state.dismissAt, state.dismissAt)
    return ActivityContent(state: state, staleDate: stale, relevanceScore: 100)
  }

  @available(iOS 16.1, *)
  private static func contentState(_ args: [String: Any]) -> TimerActivityAttributes.ContentState? {
    func date(_ key: String) -> Date? {
      guard let ms = args[key] as? NSNumber else { return nil }
      return Date(timeIntervalSince1970: ms.doubleValue / 1000)
    }
    func text(_ key: String) -> String? {
      guard let value = args[key] as? String, !value.isEmpty else { return nil }
      return value
    }
    guard let startedAt = date("startedAt"), let dismissAt = date("dismissAt") else { return nil }
    return TimerActivityAttributes.ContentState(
      mode: text("mode") ?? "stopwatch",
      phase: text("phase"),
      startedAt: startedAt,
      endsAt: date("endsAt"),
      dismissAt: dismissAt,
      title: text("title") ?? "",
      staleTitle: text("staleTitle"),
      label: text("label").map { String($0.prefix(120)) }
    )
  }
}
