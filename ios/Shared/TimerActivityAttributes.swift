import Foundation

#if canImport(ActivityKit)
  import ActivityKit

  /// The Live Activity of a running timer (HIN-102).
  ///
  /// Member of the Runner (which starts it) and of HinataWidgets (which draws
  /// it); both must agree byte for byte on this type, so it lives once, here.
  ///
  /// Nothing in it names the timer or anything on the server. The attributes
  /// carry an opaque reference the app made up; the state carries the times
  /// and the words, already in the reader's language.
  @available(iOS 16.1, *)
  struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
      /// `stopwatch`, `countdown` or `pomodoro`.
      var mode: String
      /// `work`, `shortBreak` or `longBreak`; nil outside a Pomodoro.
      var phase: String?
      var startedAt: Date
      /// The end of a countdown or a Pomodoro phase; nil for a stopwatch.
      var endsAt: Date?
      /// When the activity goes away by itself at the latest.
      var dismissAt: Date
      /// "Timer running" or "Break".
      var title: String
      /// What the activity says once [endsAt] has passed.
      var staleTitle: String?
      /// The description, only with details on the lock screen switched on.
      var label: String?

      var isBreak: Bool { phase == "shortBreak" || phase == "longBreak" }

      /// The far end of the time on display. A stopwatch counts up into a
      /// range that needs an end; the system ends an activity after 8 hours.
      var displayEnd: Date { endsAt ?? dismissAt }
    }

    /// Made up by the app for each activity; names nothing.
    var activityRef: String
  }
#endif
