import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

import '../hotkey_rules.dart';
import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// The system-wide shortcuts: start or stop the timer, open the focus view.
///
/// Bound through `system_hotkeys`, the operating system's registration API:
/// the app hears its two combinations and no other key — no event tap, no
/// keyboard hook, no Accessibility permission. Nothing is bound until the
/// person switches the shortcuts on, and what the system answered for each
/// one ([HotkeyStatus.results]) is shown in the settings. On Windows a
/// combination another app holds comes back as a conflict; on a Mac only the
/// system's own shortcuts do, and the settings' "press it now" check is the
/// proof that a press arrives.
class GlobalHotkeysSurface extends TimerSurface {
  GlobalHotkeysSurface(
    this.platform, {
    required this.status,
    HotkeyBinder? binder,
  }) : _binder = binder ?? const SystemHotkeyBinder();

  final SurfacePlatform platform;
  final HotkeyBinder _binder;

  /// What the settings show of the shortcuts, and their "press it now" check.
  final HotkeyStatus status;

  static const toggleId = 'hinata.timer.toggle';
  static const focusId = 'hinata.timer.focus';

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
    final next = Map<String, HotKeyResult>.of(status.results.value);
    var changed = false;
    // Only a combination that changed is bound again: releasing the other one
    // for a moment would hand it to whichever app asks first.
    for (final (id, hotKey, bound) in [
      (toggleId, state.toggleHotkey, _toggle),
      (focusId, state.focusHotkey, _focus),
    ]) {
      if (hotKey == bound) continue;
      changed = true;
      if (hotKey == null) {
        await _binder.unregister(id);
        next.remove(id);
      } else {
        next[id] = isSafeHotkey(hotKey, platform)
            ? await _binder.register(id, hotKey)
            : HotKeyResult.unsupported;
      }
    }
    _toggle = state.toggleHotkey;
    _focus = state.focusHotkey;
    if (!changed) return;
    status.results.value = Map.unmodifiable(next);
    if (next.isEmpty) {
      await _presses?.cancel();
      _presses = null;
    } else {
      _presses ??= _binder.events.listen(_pressed);
    }
  }

  void _pressed(HotKeyEvent event) {
    status._press(event.id);
    if (status.selfTest.value) return;
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
    status.results.value = const {};
    await _binder.unregisterAll();
  }

  @override
  Future<void> dispose() => clear();
}

/// What the settings see of the system-wide shortcuts: what the system
/// answered for each one, the presses, and whether the "press it now" check
/// is running. One per app, handed to the surface and to the settings.
class HotkeyStatus {
  /// The system's answer for each bound shortcut, by id; empty while off.
  final ValueNotifier<Map<String, HotKeyResult>> results = ValueNotifier(
    const {},
  );

  /// Every press, by id. The count makes the same shortcut pressed twice two
  /// different values.
  final ValueNotifier<({String id, int count})?> lastPress = ValueNotifier(
    null,
  );
  int _count = 0;

  /// While the settings run their check, a press is only counted: testing the
  /// start/stop shortcut must not start or stop the timer.
  final ValueNotifier<bool> selfTest = ValueNotifier(false);

  void _press(String id) => lastPress.value = (id: id, count: ++_count);

  void dispose() {
    results.dispose();
    lastPress.dispose();
    selfTest.dispose();
  }
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
