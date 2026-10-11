import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../surface_platform.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// What closing the window does while a timer runs.
///
/// With "keep running when closed" on, a running timer and the menu bar or
/// tray icon on screen, the close button hides the window instead of quitting:
/// the timer goes on in the menu bar, and the window comes back from its menu
/// or (on a Mac) from the Dock. In every other case the window closes as it
/// always did — nothing may hide into a tray that is not there, or keep an
/// app alive with no timer to show for it. ⌘Q and "Quit" always quit.
class KeepRunningSurface extends TimerSurface {
  KeepRunningSurface(
    this.platform, {
    required this.trayAvailable,
    WindowGateway? window,
  }) : _window = window ?? WindowManagerGateway.shared;

  final SurfacePlatform platform;

  /// Whether the menu bar or tray icon is on screen (see `TraySurface`).
  final ValueListenable<bool> trayAvailable;

  final WindowGateway _window;
  TimerSurfaceState _state = TimerSurfaceState.idle;
  bool? _preventing;

  @override
  String get id => 'keep-running';

  @override
  TimerSurfaceCapabilities get capabilities =>
      capabilitiesForPlatform(platform);

  @override
  Future<void> init(TimerSurfaceHost host) async {
    _window.onCloseRequested(_onCloseRequested);
    trayAvailable.addListener(_update);
  }

  @override
  Future<void> apply(TimerSurfaceState state) async {
    _state = state;
    await _sync();
  }

  void _update() => unawaited(_sync());

  /// Whether a close hides the window right now.
  @visibleForTesting
  bool get keepsRunning =>
      _state.keepInTray && _state.running && trayAvailable.value;

  Future<void> _sync() async {
    // A window hidden into a tray that is gone again (signed out, the module
    // switched off, the icon put aside) comes back: an app with no window and
    // no icon would be running where nobody can see or quit it.
    if (_window.hidden && !(_state.keepInTray && trayAvailable.value)) {
      await _window.show();
    }
    final prevent = keepsRunning;
    // Never touches the window manager until the person has switched this on.
    if (prevent == (_preventing ?? false)) return;
    _preventing = prevent;
    await _window.setPreventClose(prevent);
  }

  void _onCloseRequested() {
    // The state may have moved on between the click and this callback: the
    // timer stopped, the tray went away. Then the close goes through after all.
    unawaited(keepsRunning ? _window.hide() : _window.close());
  }

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  @override
  Future<void> clear() async {
    if (_window.hidden) await _window.show();
    if (_preventing != true) return;
    _preventing = false;
    await _window.setPreventClose(false);
  }

  @override
  Future<void> dispose() async {
    trayAvailable.removeListener(_update);
    await clear();
  }
}

/// The app window, behind one seam so the tests need no plugin.
abstract class WindowGateway {
  /// Whether the window is hidden because a close hid it into the tray.
  bool get hidden;

  Future<void> setPreventClose(bool prevent);
  Future<void> hide();
  Future<void> show();

  /// Closes for good, past a prevented close.
  Future<void> close();

  void onCloseRequested(void Function() handler);
}

/// [WindowGateway] on window_manager. Initialised on first use only: an app
/// that never keeps a timer in the tray never hands its window to the plugin.
class WindowManagerGateway with WindowListener implements WindowGateway {
  WindowManagerGateway._();

  /// The one window of the app; the host shows and closes it through this.
  static final WindowManagerGateway shared = WindowManagerGateway._();

  void Function()? _onClose;
  Future<void>? _ready;

  @override
  bool hidden = false;

  Future<void> _init() => _ready ??= () async {
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
  }();

  /// The runner's side of the close behaviour (macOS AppDelegate): AppKit
  /// asks whether to quit also when the last window is only hidden.
  static const _runner = MethodChannel('hinata/window');

  @override
  Future<void> setPreventClose(bool prevent) async {
    if (!prevent && _ready == null) return;
    await _init();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _runner.invokeMethod<void>('setKeepsRunning', prevent);
    }
    await windowManager.setPreventClose(prevent);
  }

  @override
  Future<void> hide() async {
    await _init();
    await windowManager.hide();
    hidden = true;
  }

  @override
  Future<void> show() async {
    hidden = false;
    await _init();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> close() async {
    await _init();
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _runner.invokeMethod<void>('setKeepsRunning', false);
    }
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onCloseRequested(void Function() handler) => _onClose = handler;

  @override
  void onWindowClose() => _onClose?.call();
}
