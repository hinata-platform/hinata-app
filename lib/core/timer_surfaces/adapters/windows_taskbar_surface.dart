import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';
import 'running_tooltip.dart';

/// The timer on the Windows taskbar button: the progress of a countdown or a
/// Pomodoro phase, a small "running" overlay, and two buttons in the window's
/// thumbnail — start or stop, and the focus view.
///
/// Drawn by the runner itself (`windows/runner/taskbar_channel.cpp`, on
/// `ITaskbarList3`), not by a package. Like the tray, it looks the same for
/// work and a break: the overlay says "running", the thumbnail tooltip says
/// the time, and the progress is the share of the interval behind.
class WindowsTaskbarSurface extends TimerSurface {
  WindowsTaskbarSurface({MethodChannel? channel, DateTime Function()? now})
    : _channel = channel ?? const MethodChannel('hinata/taskbar'),
      _now = now ?? DateTime.now;

  final MethodChannel _channel;
  final DateTime Function() _now;

  TimerSurfaceHost? _host;
  TimerSurfaceState _state = TimerSurfaceState.idle;
  bool _drawn = false;

  /// What the runner was last told, per call: only a change goes out. Explorer
  /// keeps what it was given, and the runner draws it again by itself when
  /// Explorer restarts, so a focus change or a second tick costs nothing.
  final Map<String, Object?> _sent = {};
  int? _tooltipMinute;

  /// Steps of the progress bar. The bar on a taskbar button is some forty
  /// pixels wide; two hundred steps keep it smooth and spare Explorer a call
  /// on most ticks.
  static const int _steps = 200;

  @override
  String get id => 'windows-taskbar';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(SurfacePlatform.windows);

  @override
  Future<void> init(TimerSurfaceHost host) async {
    _host = host;
    _channel.setMethodCallHandler(_handle);
  }

  Future<void> _handle(MethodCall call) async {
    final host = _host;
    // Buttons that are not on screen cannot have been clicked: a message
    // claiming otherwise comes from somewhere else and starts nothing.
    if (call.method != 'thumbClicked' || host == null || !_drawn) return;
    switch (call.arguments) {
      case 'toggle':
        await (_state.running ? host.end() : host.start());
      case 'focus':
        await host.showWindow();
        host.openFocus();
    }
  }

  Future<void> _send(String method, Map<String, Object?> args) async {
    if (mapEquals(_sent[method] as Map<String, Object?>?, args)) return;
    _sent[method] = args;
    await _channel.invokeMethod<void>(method, args);
  }

  @override
  Future<void> apply(TimerSurfaceState state) async {
    if (state.running != _state.running ||
        state.startedAt != _state.startedAt) {
      _tooltipMinute = null;
    }
    _state = state;
    if (!state.runningSurface) {
      await clear();
      return;
    }
    final t = state.texts;
    _drawn = true;
    await _send('setButtons', {
      'running': state.running,
      'toggle': state.running ? t.stop : t.start,
      'focus': t.openFocus,
    });
    await _send('setOverlay', {
      'running': state.running,
      'description': state.running ? t.running : '',
    });
    await _drawProgress();
    if (!state.running) {
      await _send('setTooltip', {'text': ''});
    } else if (!state.showsClock) {
      // A Pomodoro: "running" only, the same through work and breaks.
      await _send('setTooltip', {'text': t.running});
    }
  }

  /// The share of the interval behind, in thousandths, in [_steps] steps;
  /// null where there is no bar to fill (a stopwatch, a Pomodoro).
  @visibleForTesting
  int? progressOf(TimerSurfaceState state) {
    final start = state.startedAt;
    final end = state.endsAt;
    // A Pomodoro's bar would restart and race through a break: no bar there
    // (see [TimerSurfaceState.showsClock]).
    if (!state.showsClock || start == null || end == null) return null;
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 1000;
    final done = _now().toUtc().difference(start).inMilliseconds;
    final step = (done * _steps ~/ total).clamp(0, _steps);
    return step * (1000 ~/ _steps);
  }

  Future<void> _drawProgress() async {
    final value = progressOf(_state);
    await _send('setProgress', {
      'state': value == null ? 'none' : 'normal',
      'value': value ?? 0,
    });
  }

  @override
  void tick(Duration shown) {
    if (!_drawn || !_state.showsClock) return;
    unawaited(_drawProgress());
    final minute = shown.inMinutes;
    if (minute == _tooltipMinute) return;
    _tooltipMinute = minute;
    unawaited(
      _send('setTooltip', {
        'text': runningTooltip(_state.texts, shown, withApp: false),
      }),
    );
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  @override
  Future<void> clear() async {
    if (!_drawn) return;
    _drawn = false;
    _sent.clear();
    _tooltipMinute = null;
    await _channel.invokeMethod<void>('clear');
  }

  @override
  Future<void> dispose() async {
    await clear();
    _channel.setMethodCallHandler(null);
  }
}
