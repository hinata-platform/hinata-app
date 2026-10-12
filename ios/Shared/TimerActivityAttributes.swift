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
      /// A state from the server, still sealed (HIN-103); every field above is
      /// a placeholder until [resolved] opens it.
      var sealed: Sealed?
      /// Draws the widget's name and no time: a sealed state this phone cannot
      /// open.
      var hidesTime = false

      struct Sealed: Codable, Hashable {
        var v: Int
        var n: String
        var c: String
      }

      init(
        mode: String, phase: String?, startedAt: Date, endsAt: Date?, dismissAt: Date,
        title: String, staleTitle: String?, label: String?
      ) {
        self.mode = mode
        self.phase = phase
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.dismissAt = dismissAt
        self.title = title
        self.staleTitle = staleTitle
        self.label = label
      }

      /// The widget's name ("Timer" in the reader's language), without a time
      /// or a word of the person's.
      static var opaque: Self {
        var state = Self(
          mode: "stopwatch", phase: nil, startedAt: Date(), endsAt: nil,
          dismissAt: Date().addingTimeInterval(3600), title: String(localized: "widget.name"),
          staleTitle: nil, label: nil)
        state.hidesTime = true
        return state
      }

      private enum CodingKeys: String, CodingKey {
        case mode, phase, startedAt, endsAt, dismissAt, title, staleTitle, label
        case v, n, c
      }

      /// The app's own state, or the server's sealed one: `{v, n, c}` and
      /// nothing else (HIN-103).
      init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let cipher = try container.decodeIfPresent(String.self, forKey: .c) {
          self = .opaque
          hidesTime = false
          sealed = Sealed(
            v: try container.decodeIfPresent(Int.self, forKey: .v) ?? 0,
            n: try container.decode(String.self, forKey: .n),
            c: cipher)
          return
        }
        mode = try container.decode(String.self, forKey: .mode)
        phase = try container.decodeIfPresent(String.self, forKey: .phase)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endsAt = try container.decodeIfPresent(Date.self, forKey: .endsAt)
        dismissAt = try container.decode(Date.self, forKey: .dismissAt)
        title = try container.decode(String.self, forKey: .title)
        staleTitle = try container.decodeIfPresent(String.self, forKey: .staleTitle)
        label = try container.decodeIfPresent(String.self, forKey: .label)
      }

      func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let sealed {
          try container.encode(sealed.v, forKey: .v)
          try container.encode(sealed.n, forKey: .n)
          try container.encode(sealed.c, forKey: .c)
          return
        }
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(phase, forKey: .phase)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endsAt, forKey: .endsAt)
        try container.encode(dismissAt, forKey: .dismissAt)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(staleTitle, forKey: .staleTitle)
        try container.encodeIfPresent(label, forKey: .label)
      }

      var isBreak: Bool { phase == "shortBreak" || phase == "longBreak" }

      /// The far end of the time on display. A stopwatch counts up into a
      /// range that needs an end; the system ends an activity after 8 hours.
      var displayEnd: Date { endsAt ?? dismissAt }
    }

    /// Made up by the app for each activity; names nothing.
    var activityRef: String
  }
#endif
