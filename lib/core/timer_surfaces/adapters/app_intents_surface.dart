import 'package:flutter/services.dart';

import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// One project as Siri and the Shortcuts app may offer it: the id and the
/// name, nothing else.
typedef IntentProject = ({String id, String name});

/// The native side of Siri, Shortcuts and the controls (HIN-105), behind one
/// seam so tests hand a fake.
///
/// `hinata/app_intents` in the iOS runner (`HinataAppIntentsChannel`).
class AppIntentsChannel {
  const AppIntentsChannel([
    this._channel = const MethodChannel('hinata/app_intents'),
  ]);

  final MethodChannel _channel;

  /// Asks Control Center, the lock screen and the Action button to read the
  /// timer again.
  Future<void> reloadControls() =>
      _channel.invokeMethod<void>('reloadControls');

  /// Keeps [projects] for the intents' project parameter; null removes them.
  Future<void> setProjects(List<IntentProject>? projects) =>
      _channel.invokeMethod<void>(
        'setProjects',
        projects
            ?.map((project) => {'id': project.id, 'name': project.name})
            .toList(),
      );

  /// The route an intent opened before this engine listened, once.
  Future<String?> takePendingRoute() =>
      _channel.invokeMethod<String>('takePendingRoute');

  /// Hands every route an intent opens from now on to [handler].
  void onOpenRoute(void Function(String route) handler) {
    _channel.setMethodCallHandler((call) async {
      final route = call.arguments;
      if (call.method == 'openRoute' && route is String) handler(route);
    });
  }
}

/// The timer for Siri, the Shortcuts app, Spotlight and the controls (iOS).
///
/// It draws nothing itself: the controls read the record the widgets read, so
/// this surface only asks them to read it again after it changed, and opens
/// the route of an intent that brought the app to the front. The intents act
/// on the timer in a headless engine of their own (`appIntentMain`).
class AppIntentsSurface extends TimerSurface {
  AppIntentsSurface({AppIntentsChannel channel = const AppIntentsChannel()})
    : _channel = channel;

  final AppIntentsChannel _channel;

  /// Whether the controls last showed a running timer; null before the first
  /// state.
  bool? _running;

  @override
  String get id => 'app-intents';

  @override
  TimerSurfaceCapabilities get capabilities => TimerSurfaceCapabilities.none;

  @override
  Future<void> init(TimerSurfaceHost host) async {
    _channel.onOpenRoute(host.openRoute);
    final pending = await _channel.takePendingRoute();
    if (pending != null) host.openRoute(pending);
  }

  /// Applied after the widgets wrote their record, so the controls read the
  /// new one. Only a start or a stop changes what they show.
  @override
  Future<void> apply(TimerSurfaceState state) async {
    final running = state.running && state.runningSurface;
    if (running == _running) return;
    _running = running;
    await _channel.reloadControls();
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  /// Signed out, or the local copies deleted: the projects go, and the
  /// controls show nothing running.
  @override
  Future<void> clear() async {
    _running = null;
    await _channel.setProjects(null);
    await _channel.reloadControls();
  }

  @override
  Future<void> dispose() async {}
}
