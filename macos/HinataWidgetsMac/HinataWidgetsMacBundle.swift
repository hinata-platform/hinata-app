import SwiftUI
import WidgetKit

/// The widget extension of Hinata on a Mac (HIN-108): the running timer on
/// the desktop and in Notification Center.
///
/// The views are the iPhone's (`ios/HinataWidgets/TimerHomeWidget.swift`, the
/// record in `ios/Shared/TimerWidgetRecord.swift`), compiled into this target
/// too. No buttons in v1: a tap opens the focus screen. No Flutter in here;
/// the app writes everything the widget says, in the reader's language.
@main
struct HinataWidgetsMacBundle: WidgetBundle {
  var body: some Widget {
    TimerHomeWidget()
  }
}
