/// Result of a [downloadBytes] call, so the caller can give the right feedback
/// without ever surfacing an internal file-system path to the user.
enum DownloadOutcome {
  /// Native: the OS share sheet was presented and the user picked a target
  /// (e.g. iOS "Save to Files", Android Downloads) or an action completed.
  shared,

  /// Native: the user dismissed the share sheet without saving. No feedback
  /// needed — it was a deliberate cancel.
  dismissed,

  /// Web: a browser download was triggered (the browser owns the save dialog).
  browser,

  /// Something went wrong writing/sharing the file.
  failed,
}
