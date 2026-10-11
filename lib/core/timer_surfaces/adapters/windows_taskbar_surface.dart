import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';
import 'tray_surface.dart' show fmtClockMinutes;

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
  int? _progress;
  int? _tooltipMinute;

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
    if (call.method != 'thumbClicked') return;
    final host = _host;
    if (host == null) return;
    switch (call.arguments) {
      case 'toggle':
        await (_state.running ? host.end() : host.start());
      case 'focus':
        await host.showWindow();
        host.openFocus();
    }
  }

  @override
  Future<void> apply(TimerSurfaceState state) async {
    _state = state;
    if (!state.runningSurface) {
      await clear();
      return;
    }
    final t = state.texts;
    await _channel.invokeMethod<void>('setButtons', {
      'running': state.running,
      'toggle': state.running ? t.stop : t.start,
      'focus': t.openFocus,
    });
    await _channel.invokeMethod<void>('setOverlay', {
      'running': state.running,
      'description': state.running ? t.running : '',
    });
    _drawn = true;
    _progress = null;
    _tooltipMinute = null;
    await _drawProgress();
    if (!state.running) {
      await _channel.invokeMethod<void>('setTooltip', {'text': ''});
    }
  }

  /// The share of the interval behind, in thousandths; null for a stopwatch,
  /// which has no end to be a share of.
  @visibleForTesting
  int? progressOf(TimerSurfaceState state) {
    final start = state.startedAt;
    final end = state.endsAt;
    if (!state.running || start == null || end == null) return null;
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 1000;
    final done = _now().toUtc().difference(start).inMilliseconds;
    return (done * 1000 ~/ total).clamp(0, 1000);
  }

  Future<void> _drawProgress() async {
    final value = progressOf(_state);
    if (value == _progress && _progress != null) return;
    _progress = value;
    await _channel.invokeMethod<void>('setProgress', {
      'state': value == null ? 'none' : 'normal',
      'value': value ?? 0,
    });
  }

  @override
  void tick(Duration shown) {
    if (!_drawn || !_state.running) return;
    unawaited(_drawProgress());
    final minute = shown.inMinutes;
    if (minute == _tooltipMinute) return;
    _tooltipMinute = minute;
    unawaited(
      _channel.invokeMethod<void>('setTooltip', {
        'text': '${fmtClockMinutes(shown)} · ${_state.texts.running}',
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
    _progress = null;
    await _channel.invokeMethod<void>('clear');
  }

  @override
  Future<void> dispose() async {
    await clear();
    _channel.setMethodCallHandler(null);
  }
}
