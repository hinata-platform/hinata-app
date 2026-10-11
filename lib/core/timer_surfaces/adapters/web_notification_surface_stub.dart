import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// Off the web there is no browser notification; see the web implementation.
class WebNotificationSurface extends TimerSurface {
  @override
  String get id => 'web-notification';

  @override
  TimerSurfaceCapabilities get capabilities => TimerSurfaceCapabilities.none;

  @override
  Future<void> init(TimerSurfaceHost host) async {}

  @override
  Future<void> apply(TimerSurfaceState state) async {}

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}

/// The browser's permission; never granted off the web.
abstract final class WebNotificationPermission {
  static bool get granted => false;
  static bool get denied => false;
  static Future<bool> request() async => false;
}
