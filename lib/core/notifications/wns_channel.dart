import 'dart:async';

import 'package:windows_push/windows_push.dart';

/// Windows Push Notification Services, through our `windows_push` plugin.
///
/// Firebase Cloud Messaging has no Windows implementation, so the Windows build
/// registers a WNS *channel URI* where Android/iOS/macOS register an FCM token.
/// This class keeps Hinata's own rules on top of the plugin: which app
/// registration the channel belongs to, that only in-app routes are followed,
/// and that the timer's toasts live in their own group.
///
/// Everything degrades to `null` or `false` rather than throwing: WNS needs
/// package identity, so a plain `flutter run` (unpackaged) legitimately has no
/// channel, and that must not look like an error.
class WnsChannel {
  const WnsChannel();

  /// Entra "Managed application in local directory" object id of the app
  /// registration the gateway pushes with, the value the runner always used.
  /// Not a secret: it is the app's public identity, and WNS refuses any other.
  /// The manifest's push activator uses the client id instead
  /// (AZURE_APP_ID in windows/fastlane/Fastfile); that pair is what works.
  static const String remoteId = '33fa840e-5c3b-4cc0-8308-227acbecdf0d';

  /// Group of the timer's toasts, the same one the runner used before the
  /// plugin, so a toast scheduled by an older build can still be cancelled.
  static const String _toastGroup = 'timer';

  static StreamSubscription<String>? _links;

  WindowsPush get _push => WindowsPush.instance;

  /// Routes a notification the user clicked.
  ///
  /// Two paths, because a click either activates the running app or launches
  /// it: while running, the link arrives here; on a cold start it is buffered
  /// natively until [initialDeepLink] drains it. Same split as the FCM side
  /// (`onMessageOpenedApp` vs `getInitialMessage`).
  void listenForDeepLinks(void Function(String link) onLink) {
    unawaited(_links?.cancel());
    _links = _push.onNotificationClick.listen((link) {
      // Only in-app routes are navigable, same guard as the FCM path, so a
      // stray payload cannot throw "no routes for location".
      if (_isRoute(link)) onLink(link);
    });
  }

  /// The link of a notification whose click launched the app, if any.
  Future<String?> initialDeepLink() async {
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
      group: _toastGroup,
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
      group: _toastGroup,
      expiresAfter: Duration(minutes: expireMinutes),
    );
  }

  /// Removes the toast [tag], whether still scheduled or already shown.
  Future<void> cancelToast(String tag) =>
      _push.cancelToast(tag, group: _toastGroup);

  /// The device's channel URI, or null when unavailable.
  ///
  /// Microsoft rotates these and they expire after 30 days, so the app asks for
  /// a fresh one on every start rather than caching it. The plugin only hands
  /// out `https://*.notify.windows.com` URIs; the gateway enforces that too.
  Future<String?> getChannelUri() => _push.getChannelUri(remoteId: remoteId);

  static bool _isRoute(String link) => link.startsWith('/') && link.length > 1;
}
