/// The app's type scale: the only font sizes widget code uses (HIN-110).
///
/// A modular scale with φ per two steps (about 1.27 a step), snapped to whole
/// points: 12 · 15 · 20 · 25 · 32 · 41, with [label] and [title] between the
/// first steps because a dense work tool needs a size for rows and buttons
/// that is neither caption nor body. Hierarchy beyond these comes from weight
/// and colour, not from another size.
///
/// [caption] is the floor for anything a person has to read: meta lines,
/// timestamps, chips. Before the scale the app had some twenty sizes, a
/// hundred places below twelve points among them. [badge] is the one
/// exception, for a count or an initial set inside a small shape whose full
/// meaning its semantics label carries.
///
/// Sizes still scale with the reader's text size setting: these are the base
/// the [TextScaler] multiplies, never a cap on it.
abstract final class AppType {
  /// Counts in badges and initials in avatars, never running text.
  static const double badge = 10;

  /// Meta lines, timestamps, chips, helper text: the floor for reading.
  static const double caption = 12;

  /// Dense rows, buttons, field text, menu items.
  static const double label = 13;

  /// Running text: descriptions, comments, sheet bodies.
  static const double body = 15;

  /// Card and section titles.
  static const double title = 17;

  /// Page and dialog headings.
  static const double heading = 20;

  /// Large headings: the greeting, empty-state titles.
  static const double display = 25;

  /// Hero figures and the largest headings.
  static const double hero = 32;

  /// Big numbers on a dashboard tile.
  static const double numeral = 41;

  /// The single largest figure, e.g. a running timer.
  static const double giant = 66;
}
