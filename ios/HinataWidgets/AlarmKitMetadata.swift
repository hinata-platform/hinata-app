import AlarmKit

/// The same type as `AlarmKitMetadata` in the alarm_kit plugin, for the widget
/// extension, which cannot link the plugin. ActivityKit matches the two by
/// name and by their encoded form, so keep both exactly like this.
@available(iOS 26.0, *)
struct AlarmKitMetadata: AlarmMetadata {
  var kind: String?

  init(kind: String? = nil) {
    self.kind = kind
  }
}
