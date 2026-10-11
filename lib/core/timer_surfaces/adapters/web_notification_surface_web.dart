import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import '../phase_end_schedule.dart';
import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// The end of an interval as a browser notification, and the app badge while a
/// timer runs.
///
/// A browser cannot plan anything ahead, so the notification is shown when the
/// app notices the end while its tab is in the background. In front, the toast
/// is the only announcement.
class WebNotificationSurface extends TimerSurface {
  static const String _tag = 'hinata-timer';

  TimerSurfaceHost? _host;
  web.Notification? _shown;
  Timer? _expiry;
  bool _badged = false;

  @override
  String get id => 'web-notification';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(SurfacePlatform.web);

  @override
  Future<void> init(TimerSurfaceHost host) async => _host = host;

  @override
  Future<void> apply(TimerSurfaceState state) async {
    final badge = state.running && state.runningSurface;
    if (badge == _badged) return;
    _badged = badge;
    _badge(badge);
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {
    if (foreground && !web.document.hidden) return;
    if (!state.phaseEndNotification || !WebNotificationPermission.granted) {
      return;
    }
    _close();
    final notification = web.Notification(
      state.texts.appName,
      web.NotificationOptions(
        body: state.endText,
        tag: _tag,
        requireInteraction: false,
      ),
    );
    notification.onclick = ((web.Event _) {
      web.window.focus();
      _host?.openFocus();
      _close();
    }).toJS;
    _shown = notification;
    _expiry = Timer(PhaseEndSchedule.expiry, _close);
  }

  void _close() {
    _expiry?.cancel();
    _expiry = null;
    _shown?.close();
    _shown = null;
  }

  /// The PWA badge, where the browser has one.
  void _badge(bool on) {
    final navigator = web.window.navigator as JSObject;
    final method = on ? 'setAppBadge' : 'clearAppBadge';
    if (!navigator.has(method)) return;
    try {
      navigator.callMethod<JSPromise<JSAny?>>(method.toJS);
    } catch (_) {
      // Not installed as an app, or refused: nothing to show.
    }
  }

  @override
  Future<void> clear() async {
    _close();
    if (_badged) _badge(false);
    _badged = false;
  }

  @override
  Future<void> dispose() async => _close();
}

/// The browser's permission for notifications. Asked only after a gesture of
/// the person, never on load.
abstract final class WebNotificationPermission {
  static bool get granted => web.Notification.permission == 'granted';
  static bool get denied => web.Notification.permission == 'denied';

  static Future<bool> request() async {
    try {
      final answer = await web.Notification.requestPermission().toDart;
      return answer.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }
}
