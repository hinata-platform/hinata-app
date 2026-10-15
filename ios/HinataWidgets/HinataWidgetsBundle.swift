import SwiftUI
import WidgetKit

/// The widget extension of Hinata (HIN-102): the running timer as a Live
/// Activity and as home and lock screen widgets, and from iOS 18 as three
/// controls (HIN-105).
///
/// No Flutter in here. The app writes everything these views say, in the
/// reader's language; the only strings of the extension are the gallery's and
/// the controls'.
@main
struct HinataWidgetsBundle: WidgetBundle {
  var body: some Widget {
    TimerHomeWidget()
    TimerLiveActivity()
    if #available(iOSApplicationExtension 18.0, *) {
      TimerToggleControl()
      TimerAdvanceControl()
      TimerFocusControl()
    }
  }
}

/// The colours of the app: honey on navy.
enum HinataPalette {
  static let honey = Color(red: 0xD9 / 255, green: 0xA0 / 255, blue: 0x32 / 255)
  static let navy = Color(red: 0x2D / 255, green: 0x2B / 255, blue: 0x55 / 255)
  static let paper = Color(red: 0xF4 / 255, green: 0xF3 / 255, blue: 0xEF / 255)
}

/// Where a tap on any of these surfaces leads: the focus screen. A route
/// only; a link never acts on the timer.
let timerFocusURL = URL(string: "hinata://time/focus")!
