import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:system_hotkeys/system_hotkeys.dart';
import 'package:system_hotkeys_linux/system_hotkeys_linux.dart';

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
///
/// On Linux the GlobalShortcuts portal binds them and the desktop picks the
/// keys: the app's combination is only a suggestion, GNOME asks once, and
/// what the desktop settled on ([HotkeyStatus.triggers]) is what the settings
/// show, with a way into the desktop's own settings ([HotkeyStatus.configure]).
class GlobalHotkeysSurface extends TimerSurface {
  GlobalHotkeysSurface(
    this.platform, {
    required this.status,
    this.trayAvailable,
    HotkeyBinder? binder,
  }) : _binder = binder ?? const SystemHotkeyBinder();

  /// Whether the menu bar or tray icon is on screen. The shortcuts are
  /// released while it is not: a press must never start a timer that nothing
  /// outside the app shows.
  final ValueListenable<bool>? trayAvailable;
  TimerSurfaceState _state = TimerSurfaceState.idle;

  final SurfacePlatform platform;
  final HotkeyBinder _binder;

  /// What the settings show of the shortcuts, and their "press it now" check.
  final HotkeyStatus status;

  static const toggleId = 'hinata.timer.toggle';
  static const focusId = 'hinata.timer.focus';

  /// What the Linux portal knows the app by outside a Snap: the installed
  /// `com.ahmadre.hinata.desktop` (the AppImage integrates it).
  static const linuxApplicationId = 'com.ahmadre.hinata';

  TimerSurfaceHost? _host;
  StreamSubscription<HotKeyEvent>? _presses;
  StreamSubscription<Map<String, String>>? _triggers;
  bool _running = false;
  HotKey? _toggle;
  HotKey? _focus;

  @override
  String get id => 'global-hotkeys';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(platform);

  @override
  Future<void> init(TimerSurfaceHost host) async {
    _host = host;
    trayAvailable?.addListener(_trayChanged);
    if (capabilities.hotkeysBySystem) {
      _binder.identify(linuxApplicationId);
      _triggers = _binder.triggers.listen(
        (triggers) => status.triggers.value = triggers,
      );
      status._configure = _configure;
    }
  }

  void _trayChanged() => unawaited(apply(_state));

  @override
  Future<void> apply(TimerSurfaceState state) async {
    _state = state;
    _running = state.running;
    final shown = trayAvailable?.value ?? true;
    final next = Map<String, HotKeyResult>.of(status.results.value);
    final bind = <String, HotKey>{};
    final release = <String>[];
    var changed = false;
    // Only a combination that changed is bound again: releasing the other one
    // for a moment would hand it to whichever app asks first.
    for (final (id, hotKey, bound) in [
      (toggleId, shown ? state.toggleHotkey : null, _toggle),
      (focusId, shown ? state.focusHotkey : null, _focus),
    ]) {
      if (hotKey == bound) continue;
      changed = true;
      if (hotKey == null) {
        release.add(id);
        next.remove(id);
      } else if (isSafeHotkey(hotKey, platform)) {
        bind[id] = hotKey;
      } else {
        // Released all the same: the id must not go on meaning the old one.
        release.add(id);
        next[id] = HotKeyResult.unsupported;
      }
    }
    // Both at once in one call: on Linux every release binds the rest in a
    // new portal session, and one for the other shortcut alone is wasted.
    if (release.length == 2) {
      await _binder.unregisterAll();
    } else {
      for (final id in release) {
        await _binder.unregister(id);
      }
    }
    _toggle = shown ? state.toggleHotkey : null;
    _focus = shown ? state.focusHotkey : null;
    if (!changed) return;
    // Both in one go: the Linux desktop asks about the set once.
    if (bind.isNotEmpty) {
      next.addAll(
        await _binder.registerAll(
          bind,
          descriptions: {
            toggleId: state.texts.hotkeyToggle,
            focusId: state.texts.hotkeyFocus,
          },
        ),
      );
    }
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

  /// "Configure in the system": a set the person turned down is asked about
  /// again, as only binding it anew shows the desktop's dialog; otherwise the
  /// desktop's own settings open. False when there are none to open.
  Future<bool> _configure() async {
    if (status.results.value.values.contains(HotKeyResult.declined)) {
      await _binder.unregisterAll();
      _toggle = null;
      _focus = null;
      status.results.value = const {};
      await apply(_state);
      return true;
    }
    return _binder.configure();
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
    status.triggers.value = const {};
    await _binder.unregisterAll();
  }

  @override
  Future<void> dispose() async {
    trayAvailable?.removeListener(_trayChanged);
    await _triggers?.cancel();
    status._configure = null;
    await clear();
  }
}

/// What the settings see of the system-wide shortcuts: what the system
/// answered for each one, the presses, and whether the "press it now" check
/// is running. One per app, handed to the surface and to the settings.
class HotkeyStatus {
  /// The system's answer for each bound shortcut, by id; empty while off.
  final ValueNotifier<Map<String, HotKeyResult>> results = ValueNotifier(
    const {},
  );

  /// What the desktop says triggers each bound shortcut, in its own words, by
  /// id; empty text for one it bound without keys. Linux only.
  final ValueNotifier<Map<String, String>> triggers = ValueNotifier(const {});

  Future<bool> Function()? _configure;

  /// Opens the desktop's settings for the shortcuts, or asks again about a
  /// set the person turned down. False where there is nothing to open (Linux
  /// only).
  Future<bool> configure() => _configure?.call() ?? Future.value(false);

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
    triggers.dispose();
    lastPress.dispose();
    selfTest.dispose();
  }
}

/// `system_hotkeys`, behind one seam so the tests bind nothing for real.
abstract class HotkeyBinder {
  /// Tells a desktop that knows the app by an installed `.desktop` file
  /// which one it is (Linux, outside a Snap). Before the first bind.
  void identify(String applicationId);
  Future<Map<String, HotKeyResult>> registerAll(
    Map<String, HotKey> hotKeys, {
    Map<String, String> descriptions,
  });
  Future<void> unregister(String id);
  Future<void> unregisterAll();
  Stream<HotKeyEvent> get events;
  Stream<Map<String, String>> get triggers;
  Future<bool> configure();
}

class SystemHotkeyBinder implements HotkeyBinder {
  const SystemHotkeyBinder();

  @override
  void identify(String applicationId) =>
      SystemHotkeysLinux.registerWith(applicationId: applicationId);

  @override
  Future<Map<String, HotKeyResult>> registerAll(
    Map<String, HotKey> hotKeys, {
    Map<String, String> descriptions = const {},
  }) => SystemHotkeys.registerAll(hotKeys, descriptions: descriptions);

  @override
  Future<void> unregister(String id) => SystemHotkeys.unregister(id);

  @override
  Future<void> unregisterAll() => SystemHotkeys.unregisterAll();

  @override
  Stream<HotKeyEvent> get events => SystemHotkeys.events;

  @override
  Stream<Map<String, String>> get triggers => SystemHotkeys.triggers;

  @override
  Future<bool> configure() => SystemHotkeys.configure();
}
