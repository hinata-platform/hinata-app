import 'package:flutter/foundation.dart';
import 'package:windows_push/windows_push.dart';

/// Windows Push Notification Services channel.
///
/// Firebase Cloud Messaging has no Windows implementation, so the Windows build
/// registers a WNS *channel URI* where Android/iOS/macOS register an FCM token.
/// The platform part lives in the `windows_push` plugin; this adds what is
/// Hinata's: which Entra identity asks for the channel, that only in-app paths
/// are routed, and the toast group the timer has always used.
///
/// Everything here degrades to `null` rather than throwing: WNS needs package
/// identity, so a plain `flutter run` (unpackaged) legitimately has no channel,
/// and that must not look like an error.
class WnsChannel {
  const WnsChannel();

  /// Object ID of the hinata-wns service principal ("Managed application in
  /// local directory" in Entra). Not a secret — it is the app's public
  /// identity, and WNS refuses any other. Not the Application (client) ID
  /// either: that one goes into the package manifest (windows/fastlane).
  /// See release/WINDOWS_PUSH_PFN_MAPPING.md.
  static const String remoteId = '33fa840e-5c3b-4cc0-8308-227acbecdf0d';

  /// Scheduled timer toasts live in this group, so a tag only has to be unique
  /// within the timer's own notifications. Kept from the runner days so a
  /// toast scheduled by an older build can still be cancelled.
  static const String toastGroup = 'timer';

  static WindowsPush get _push => WindowsPush.instance;

  static bool get _onWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Only in-app routes are navigable — same guard as the FCM path, so a stray
  /// payload cannot throw "no routes for location".
  static bool _isRoute(String link) => link.startsWith('/') && link.length > 1;

  /// Routes a notification the user clicked.
  ///
  /// Two paths, because a click either activates the running app or launches
  /// it: while running, the plugin streams it; on a cold start the click is
  /// buffered natively until [initialDeepLink] reads it. Same split as the FCM
  /// side (`onMessageOpenedApp` vs `getInitialMessage`).
  void listenForDeepLinks(void Function(String link) onLink) {
    if (!_onWindows) return;
    _push.onNotificationClick.where(_isRoute).listen(onLink);
  }

  /// The link of a notification whose click launched the app, if any.
  Future<String?> initialDeepLink() async {
    if (!_onWindows) return null;
    final link = await _push.getInitialNotificationClick();
    return link != null && _isRoute(link) ? link : null;
  }

  /// Schedules a local toast for [at] (the end of a timer interval, HIN-100).
  ///
  /// Replaces a pending toast with the same [tag]. Clicking it routes [launch]
  /// (an in-app path such as `/time/focus`) through [listenForDeepLinks] like a
  /// push. The toast leaves Action Center [expireMinutes] after [at]. Returns
  /// false off Windows, without package identity, or when Windows refused.
  Future<bool> scheduleToast({
    required String tag,
    required DateTime at,
    required String title,
    required String body,
    required String launch,
    int expireMinutes = 10,
  }) {
    return _push.scheduleToast(
      tag: tag,
      at: at,
      title: title,
      body: body,
      argument: launch,
      group: toastGroup,
      expiresAfter: Duration(minutes: expireMinutes),
    );
  }

  /// Shows a local toast right away; same contract as [scheduleToast].
  Future<bool> showToast({
    required String tag,
    required String title,
    required String body,
    required String launch,
    int expireMinutes = 10,
  }) {
    return _push.showToast(
      tag: tag,
      title: title,
      body: body,
      argument: launch,
      group: toastGroup,
      expiresAfter: Duration(minutes: expireMinutes),
    );
  }

  /// Removes the toast [tag], whether still scheduled or already shown.
  Future<void> cancelToast(String tag) =>
      _push.cancelToast(tag, group: toastGroup);

  /// The device's channel URI, or null when unavailable.
  ///
  /// Microsoft rotates these and they expire after 30 days, so the app asks for
  /// a fresh one on every start rather than caching it. The plugin only ever
  /// returns an `https://*.notify.windows.com` URI.
  Future<String?> getChannelUri() async {
    if (!_onWindows) return null;
    final uri = await _push.getChannelUri(remoteId: remoteId);
    // Whether a channel could be minted is the single most useful datum when
    // Windows push does not work — but the URI is a device-specific endpoint,
    // so it stays out of release logs (same rule as the FCM token).
    if (kDebugMode) debugPrint('WNS channel: ${uri ?? "none"}');
    return uri;
  }
}
