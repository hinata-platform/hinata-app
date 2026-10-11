import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/time_models.dart';
import '../../widgets/hive_widgets.dart' show fmtClock;
import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';
import 'tray_gateway.dart';

/// The timer in the macOS menu bar and in the Windows and Linux tray.
///
/// On a Mac the title next to the icon ticks once a second while a timer
/// runs; on Windows the tooltip carries the time and changes once a minute;
/// Linux has the icon and the menu only (a StatusNotifierItem draws no text).
///
/// Everything the icon, the title and the tooltip show is identical for work
/// and a break — the time and "running" — because the menu bar is on every
/// screen share. The mode and the phase are words of the open menu, and the
/// description is there only with "details" switched on.
class TraySurface extends TimerSurface {
  TraySurface(this.platform, {TrayGateway? gateway})
    : _gateway = gateway ?? TrayManagerGateway(platform);

  final SurfacePlatform platform;
  final TrayGateway _gateway;

  /// Whether the icon is on screen. The close behaviour reads it: a window
  /// may only hide into a tray that is there.
  ValueListenable<bool> get available => _available;
  final ValueNotifier<bool> _available = ValueNotifier(false);

  TimerSurfaceHost? _host;
  TimerSurfaceState _state = TimerSurfaceState.idle;
  List<TrayMenuEntry>? _menu;
  String? _icon;
  String? _title;
  String? _tooltip;
  int? _tooltipMinute;

  bool get _mac => platform == SurfacePlatform.macos;

  @override
  String get id => 'tray';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(platform);

  @override
  Future<void> init(TimerSurfaceHost host) async {
    _host = host;
    _gateway.onSelected(_select);
  }

  @override
  Future<void> apply(TimerSurfaceState state) async {
    _state = state;
    if (!state.runningSurface) {
      await clear();
      return;
    }
    try {
      final icon = state.running ? 'running' : 'idle';
      if (icon != _icon) {
        await _gateway.setIcon(running: state.running);
        _icon = icon;
      }
      final menu = trayMenu(state);
      if (!listEquals(menu, _menu)) {
        await _gateway.setMenu(menu);
        _menu = menu;
      }
      if (!state.running) {
        await _setTitle('');
        await _setTooltip(
          state.texts.idle.isEmpty
              ? state.texts.appName
              : '${state.texts.appName} · ${state.texts.idle}',
        );
      }
      _available.value = true;
    } catch (_) {
      // Linux without a StatusNotifierItem host, or a plugin that is missing:
      // the coordinator puts the surface aside after the second failure, and
      // nothing may hide into a tray that is not there.
      _available.value = false;
      rethrow;
    }
  }

  @override
  void tick(Duration shown) {
    if (!_state.running || !_state.runningSurface || _icon == null) return;
    final clock = fmtClock(shown);
    if (_mac) {
      unawaited(_setTitle(' $clock'));
      return;
    }
    // A tooltip is read when hovered, not watched; once a minute is plenty and
    // spares the shell a repaint every second.
    final minute = shown.inMinutes;
    if (minute == _tooltipMinute) return;
    _tooltipMinute = minute;
    unawaited(_setTooltip(trayTooltip(_state.texts, fmtClockMinutes(shown))));
  }

  Future<void> _setTitle(String title) async {
    if (!_mac || title == _title) return;
    _title = title;
    await _gateway.setTitle(title);
  }

  Future<void> _setTooltip(String text) async {
    if (_mac || text == _tooltip) return;
    _tooltip = text;
    await _gateway.setTooltip(text);
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  void _select(String key) {
    final host = _host;
    if (host == null) return;
    switch (key) {
      case TrayMenuEntry.toggle:
        unawaited(_state.running ? host.end() : host.start());
      case TrayMenuEntry.next:
        unawaited(host.advancePhase());
      case TrayMenuEntry.focus:
        unawaited(host.showWindow().then((_) => host.openFocus()));
      case TrayMenuEntry.show:
        unawaited(host.showWindow());
      case TrayMenuEntry.quit:
        unawaited(host.quit());
    }
  }

  @override
  Future<void> clear() async {
    _available.value = false;
    if (_icon == null) return;
    _icon = null;
    _menu = null;
    _title = null;
    _tooltip = null;
    _tooltipMinute = null;
    await _gateway.remove();
  }

  @override
  Future<void> dispose() async {
    await clear();
    _available.dispose();
  }
}

/// The tooltip of a running timer: the time and "running", for work and a
/// break alike.
String trayTooltip(TimerSurfaceTexts texts, String time) =>
    '${texts.appName} · $time · ${texts.running}';

/// Hours and minutes, for a tooltip that changes once a minute.
String fmtClockMinutes(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// The menu for [state]: what the timer is (a line that cannot be clicked),
/// what can be done with it, and the window. At most six entries, fixed — no
/// list that grows.
List<TrayMenuEntry> trayMenu(TimerSurfaceState state) {
  final t = state.texts;
  final status = !state.running
      ? t.idle
      : switch (state.mode) {
          TimerMode.pomodoro =>
            state.phase != TimerPhase.work ? t.breakPhase : t.focusPhase,
          TimerMode.countdown => t.countdown,
          _ => t.stopwatch,
        };
  return [
    if (status.isNotEmpty) TrayMenuEntry.label(status),
    if (state.running && state.label != null) TrayMenuEntry.label(state.label!),
    const TrayMenuEntry.separator(),
    TrayMenuEntry(TrayMenuEntry.toggle, state.running ? t.stop : t.start),
    if (state.running && state.mode == TimerMode.pomodoro)
      TrayMenuEntry(TrayMenuEntry.next, t.nextPhase),
    TrayMenuEntry(TrayMenuEntry.focus, t.openFocus),
    const TrayMenuEntry.separator(),
    TrayMenuEntry(TrayMenuEntry.show, t.showWindow),
    TrayMenuEntry(TrayMenuEntry.quit, t.quit),
  ];
}
