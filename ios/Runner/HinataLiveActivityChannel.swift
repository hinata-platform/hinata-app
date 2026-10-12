import ActivityKit
import Flutter
import Foundation

/// `hinata/live_activity`: the Live Activity of a running timer (HIN-102).
///
/// The app starts, updates and ends the activity while it runs; the system
/// ticks the time. Keeps at most one activity: `start` adopts one an earlier
/// run left behind and ends any extra, so a relaunch neither duplicates nor
/// blinks.
///
/// With `push` (HIN-103) a new activity is requested for server updates: a
/// fresh key goes into the shared Keychain with the words the extension needs,
/// and every push token iOS issues for it is handed to Dart (`pushToken`) with
/// that key, to register with the server. The server then sends sealed states
/// the extension opens; the key and the words go with the activity's end.
///
/// A request the system refuses (switched off, or the app is not in front to
/// ask) answers nil instead of an error: the Dart side asks again with the
/// next state, and an error would count against the surface.
enum HinataLiveActivityChannel {
  private static let channelName = "hinata/live_activity"

  /// The channel of the app's own engine, which hears about push tokens.
  /// Background engines (a notification or widget action) only draw.
  private static var primary: FlutterMethodChannel?

  /// The activities whose push tokens are already watched in this process.
  private static var watched = Set<String>()

  static func register(with messenger: FlutterBinaryMessenger, primary isPrimary: Bool = true) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    if isPrimary { primary = channel }
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.2, *) else {
        result(call.method == "areActivitiesEnabled" ? false : nil)
        return
      }
      handle(call, result: result)
    }
    if isPrimary, #available(iOS 16.2, *) {
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
      let push = (args["push"] as? Bool) ?? false
      Task { result(await start(state, push: push, words: words(args))) }
    case "update":
      guard let ref = args["ref"] as? String, let state = contentState(args) else {
        return result(false)
      }
      Task { result(await update(ref: ref, state: state, words: words(args))) }
    case "end":
      let ref = args["ref"] as? String
      Task {
        for activity in Activity<TimerActivityAttributes>.activities
        where ref == nil || activity.attributes.activityRef == ref {
          await end(activity)
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
  private static func start(
    _ state: TimerActivityAttributes.ContentState, push: Bool, words: [String: String]
  ) async -> String? {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
    let held = Activity<TimerActivityAttributes>.activities
    if let first = held.first {
      for extra in held.dropFirst() {
        await end(extra)
      }
      keep(first.attributes.activityRef, words: words, label: state.label)
      await first.update(content(state))
      watch(first)
      return first.attributes.activityRef
    }
    let ref = UUID().uuidString
    if push {
      let record = TimerActivityRecord(
        key: TimerActivityCrypto.newKey(), words: words, label: state.label)
      guard TimerActivityKeychain.save(record, ref: ref) else { return nil }
    }
    do {
      let activity = try Activity.request(
        attributes: TimerActivityAttributes(activityRef: ref),
        content: content(state),
        pushType: push ? .token : nil
      )
      watch(activity)
      return activity.attributes.activityRef
    } catch {
      TimerActivityKeychain.delete(ref: ref)
      return nil
    }
  }

  /// False when the activity is gone (swiped away, ended by the system).
  @available(iOS 16.2, *)
  private static func update(
    ref: String, state: TimerActivityAttributes.ContentState, words: [String: String]
  ) async -> Bool {
    guard let activity = Activity<TimerActivityAttributes>.activities
      .first(where: { $0.attributes.activityRef == ref }),
      activity.activityState == .active || activity.activityState == .stale
    else {
      TimerActivityKeychain.delete(ref: ref)
      return false
    }
    keep(ref, words: words, label: state.label)
    await activity.update(content(state))
    return true
  }

  /// Refreshes the words and the label of an activity that takes server
  /// updates: the language may have changed, the person may have switched the
  /// description off. Nothing for an activity without a key.
  private static func keep(_ ref: String, words: [String: String], label: String?) {
    guard var record = TimerActivityKeychain.load(ref: ref) else { return }
    let next = TimerActivityRecord(
      key: record.key, words: words.isEmpty ? record.words : words, label: label)
    guard next != record else { return }
    record = next
    TimerActivityKeychain.save(record, ref: ref)
  }

  /// Hands each push token of [activity] to Dart with its key, the first and
  /// every rotation. Only in the app's own engine, once per activity.
  @available(iOS 16.2, *)
  private static func watch(_ activity: Activity<TimerActivityAttributes>) {
    let ref = activity.attributes.activityRef
    guard primary != nil, !watched.contains(ref),
      TimerActivityKeychain.load(ref: ref) != nil
    else { return }
    watched.insert(ref)
    Task {
      for await token in activity.pushTokenUpdates {
        guard let record = TimerActivityKeychain.load(ref: ref) else { break }
        let hex = token.map { String(format: "%02x", $0) }.joined()
        await MainActor.run {
          primary?.invokeMethod(
            "pushToken",
            arguments: ["ref": ref, "token": hex, "key": record.key.base64EncodedString()])
        }
      }
      watched.remove(ref)
    }
  }

  @available(iOS 16.2, *)
  private static func end(_ activity: Activity<TimerActivityAttributes>) async {
    await activity.end(nil, dismissalPolicy: .immediate)
    TimerActivityKeychain.delete(ref: activity.attributes.activityRef)
  }

  @available(iOS 16.2, *)
  private static func endAll() async {
    for activity in Activity<TimerActivityAttributes>.activities {
      await end(activity)
    }
    TimerActivityKeychain.deleteAll()
  }

  /// Ends what is past its moment. A state the server sealed is opened first;
  /// one that cannot be opened any more has nothing left to show.
  @available(iOS 16.2, *)
  private static func endExpired() async {
    let now = Date()
    let held = Activity<TimerActivityAttributes>.activities
    for activity in held {
      let state = activity.content.state.resolved(ref: activity.attributes.activityRef)
      if state.hidesTime || state.dismissAt <= now {
        await end(activity)
      }
    }
    if held.isEmpty { TimerActivityKeychain.deleteAll() }
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

  /// The words the extension draws once a sealed state arrives.
  private static func words(_ args: [String: Any]) -> [String: String] {
    (args["words"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
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
