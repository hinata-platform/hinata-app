import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// The system-wide shortcuts: start or stop the timer, open the focus view.
///
/// Bound through `system_hotkeys`, the operating system's registration API:
/// the app hears its two combinations and no other key — no event tap, no
/// keyboard hook, no Accessibility permission. Nothing is bound until the
/// person switches the shortcuts on, and what the system answered for each
/// one ([results]) is shown in the settings, so a combination another app
/// holds is reported instead of silently doing nothing.
class GlobalHotkeysSurface extends TimerSurface {
  GlobalHotkeysSurface(this.platform, {HotkeyBinder? binder})
    : _binder = binder ?? const SystemHotkeyBinder();

  final SurfacePlatform platform;
  final HotkeyBinder _binder;

  static const toggleId = 'hinata.timer.toggle';
  static const focusId = 'hinata.timer.focus';

  /// The system's answer for each bound shortcut, by id; empty while off.
  static final ValueNotifier<Map<String, HotKeyResult>> results = ValueNotifier(
    const {},
  );

  /// Fires on every press, for the settings' "press it now" check. The count
  /// makes the same shortcut pressed twice two different values.
  static final ValueNotifier<({String id, int count})?> lastPress =
      ValueNotifier(null);
  static int _pressCount = 0;

  /// While the settings run their check, a press is only counted: testing the
  /// start/stop shortcut must not start or stop the timer.
  static final ValueNotifier<bool> selfTest = ValueNotifier(false);

  TimerSurfaceHost? _host;
  StreamSubscription<HotKeyEvent>? _presses;
  bool _running = false;
  HotKey? _toggle;
  HotKey? _focus;

  @override
  String get id => 'global-hotkeys';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(platform);

  @override
  Future<void> init(TimerSurfaceHost host) async => _host = host;

  @override
  Future<void> apply(TimerSurfaceState state) async {
    _running = state.running;
    if (state.toggleHotkey == _toggle && state.focusHotkey == _focus) return;
    _toggle = state.toggleHotkey;
    _focus = state.focusHotkey;
    final next = <String, HotKeyResult>{};
    for (final (id, hotKey) in [(toggleId, _toggle), (focusId, _focus)]) {
      if (hotKey == null) {
        await _binder.unregister(id);
      } else {
        next[id] = await _binder.register(id, hotKey);
      }
    }
    results.value = Map.unmodifiable(next);
    if (next.isEmpty) {
      await _presses?.cancel();
      _presses = null;
    } else {
      _presses ??= _binder.events.listen(_pressed);
    }
  }

  void _pressed(HotKeyEvent event) {
    lastPress.value = (id: event.id, count: ++_pressCount);
    if (selfTest.value) return;
    final host = _host;
    if (host == null) return;
    switch (event.id) {
      case toggleId:
        unawaited(_running ? host.end() : host.start());
      case focusId:
        unawaited(host.showWindow().then((_) => host.openFocus()));
    }
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  @override
  Future<void> clear() async {
    _toggle = null;
    _focus = null;
    await _presses?.cancel();
    _presses = null;
    results.value = const {};
    await _binder.unregisterAll();
  }

  @override
  Future<void> dispose() => clear();
}

/// `system_hotkeys`, behind one seam so the tests bind nothing for real.
abstract class HotkeyBinder {
  Future<HotKeyResult> register(String id, HotKey hotKey);
  Future<void> unregister(String id);
  Future<void> unregisterAll();
  Stream<HotKeyEvent> get events;
}

class SystemHotkeyBinder implements HotkeyBinder {
  const SystemHotkeyBinder();

  @override
  Future<HotKeyResult> register(String id, HotKey hotKey) =>
      SystemHotkeys.register(id, hotKey);

  @override
  Future<void> unregister(String id) => SystemHotkeys.unregister(id);

  @override
  Future<void> unregisterAll() => SystemHotkeys.unregisterAll();

  @override
  Stream<HotKeyEvent> get events => SystemHotkeys.events;
}
