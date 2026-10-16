import SwiftUI

/// The colours of the app: honey on navy. Both widget extensions (iOS and,
/// from HIN-108, macOS) compile this file.
enum HinataPalette {
  static let honey = Color(red: 0xD9 / 255, green: 0xA0 / 255, blue: 0x32 / 255)
  static let navy = Color(red: 0x2D / 255, green: 0x2B / 255, blue: 0x55 / 255)
  static let paper = Color(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xEF / 255)
}

/// Where a tap on any of these surfaces leads: the focus screen. A route
/// only; a link never acts on the timer.
let timerFocusURL = URL(string: "hinata://time/focus")!
