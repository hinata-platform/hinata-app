import SwiftUI
import WidgetKit

/// The widget extension of Hinata (HIN-102): the running timer as a Live
/// Activity and as home and lock screen widgets, from iOS 18 as three
/// controls (HIN-105), and from iOS 26 as the countdown of an alarm (HIN-106).
///
/// No Flutter in here. The app writes everything these views say, in the
/// reader's language; the only strings of the extension are the gallery's and
/// the controls'.
@main
struct HinataWidgetsBundle: WidgetBundle {
  var body: some Widget {
    TimerHomeWidget()
    TimerLiveActivity()
    // The countdown of an interval that ends in an alarm (HIN-106).
    if #available(iOSApplicationExtension 26.0, *) {
      TimerAlarmActivity()
    }
    if #available(iOSApplicationExtension 18.0, *) {
      TimerToggleControl()
      TimerAdvanceControl()
      TimerFocusControl()
    }
  }
}
