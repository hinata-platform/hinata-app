import AppIntents
import SwiftUI

/// One round button of the activity and the widgets; the word is its
/// accessible name. On a Mac (HIN-108) the widget's buttons only.
@available(iOSApplicationExtension 17.0, macOS 14.0, *)
struct TimerActivityButton<Intent: AppIntent>: View {
  let title: String
  let symbol: String
  let size: CGFloat
  let prominent: Bool
  let intent: Intent

  var body: some View {
    Button(intent: intent) {
      Image(systemName: symbol)
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(prominent ? HinataPalette.navy : HinataPalette.honey)
        .frame(width: size, height: size)
        .background(
          prominent ? HinataPalette.honey : HinataPalette.honey.opacity(0.18), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
  }
}
