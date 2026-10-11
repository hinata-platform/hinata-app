import 'dart:io' show Platform;

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';

import '../surface_platform.dart';

/// One row of the menu bar's or the tray's menu.
///
/// A plain value, so the surface can tell whether the menu changed before it
/// asks the system to rebuild it, and tests read the menu without a plugin.
@immutable
class TrayMenuEntry {
  const TrayMenuEntry(this.key, this.label) : separator = false;

  /// A line that says something and cannot be clicked.
  const TrayMenuEntry.label(this.label) : key = null, separator = false;

  const TrayMenuEntry.separator() : key = null, label = '', separator = true;

  static const toggle = 'toggle';
  static const next = 'next';
  static const focus = 'focus';
  static const show = 'show';
  static const quit = 'quit';

  /// Null for a label or a separator.
  final String? key;
  final String label;
  final bool separator;

  @override
  bool operator ==(Object other) =>
      other is TrayMenuEntry &&
      other.key == key &&
      other.label == label &&
      other.separator == separator;

  @override
  int get hashCode => Object.hash(key, label, separator);

  @override
  String toString() => separator ? '---' : '${key ?? '·'} $label';
}

/// What the tray surface needs of the system, behind one seam: the plugin
/// changes (tray_manager is moving to nativeapi), the surface does not.
abstract class TrayGateway {
  Future<void> setIcon({required bool running});
  Future<void> setTitle(String title);
  Future<void> setTooltip(String text);
  Future<void> setMenu(List<TrayMenuEntry> entries);
  Future<void> remove();

  /// The key of a chosen menu entry.
  void onSelected(void Function(String key) handler);
}

/// [TrayGateway] on tray_manager 0.5.
class TrayManagerGateway with TrayListener implements TrayGateway {
  TrayManagerGateway(this.platform);

  final SurfacePlatform platform;
  void Function(String key)? _handler;
  bool _listening = false;
  bool _monospaced = false;

  /// The macOS runner's side of the menu bar (see MainFlutterWindow.swift).
  static const _runner = MethodChannel('hinata/window');

  static const _dir = 'assets/branding/tray';

  String _iconPath(bool running) {
    final name = running ? 'running' : 'idle';
    return switch (platform) {
      // The 44 px image for the 18 pt slot: tray_manager loads exactly the
      // file it is given, so the sharp one is the one to give it.
      SurfacePlatform.macos => '$_dir/menubar_$name@2x.png',
      SurfacePlatform.windows => '$_dir/tray_$name.ico',
      // tray_manager hands a sandboxed app's path on as an icon *name*; an
      // absolute path into the snap is one the panel outside can read.
      _ => switch (Platform.environment['SNAP']) {
        final snap? => '$snap/data/flutter_assets/$_dir/tray_$name.png',
        null => '$_dir/tray_$name.png',
      },
    };
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    trayManager.addListener(this);
  }

  /// Whether a panel hosts tray icons (Linux). libayatana does not fail
  /// without one — the icon is simply nowhere — so this asks the bus first.
  /// Asked once; a desktop does not grow a tray host mid-session.
  Future<bool>? _hosted;

  static Future<bool> _statusNotifierHost() async {
    final client = DBusClient.session();
    try {
      return await client.nameHasOwner('org.kde.StatusNotifierWatcher');
    } catch (_) {
      return false;
    } finally {
      await client.close();
    }
  }

  @override
  Future<void> setIcon({required bool running}) async {
    if (platform == SurfacePlatform.linux &&
        !await (_hosted ??= _statusNotifierHost())) {
      throw StateError('No StatusNotifierItem host on this desktop');
    }
    _listen();
    await trayManager.setIcon(
      _iconPath(running),
      isTemplate: platform == SurfacePlatform.macos,
    );
    if (platform == SurfacePlatform.macos && !_monospaced) {
      _monospaced = true;
      await _runner.invokeMethod<void>('monospaceMenuBarDigits');
    }
  }

  @override
  Future<void> setTitle(String title) => trayManager.setTitle(title);

  @override
  Future<void> setTooltip(String text) => trayManager.setToolTip(text);

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) =>
      trayManager.setContextMenu(
        Menu(
          items: [
            for (final entry in entries)
              if (entry.separator)
                MenuItem.separator()
              else
                MenuItem(
                  key: entry.key,
                  label: entry.label,
                  disabled: entry.key == null,
                ),
          ],
        ),
      );

  @override
  Future<void> remove() async {
    _monospaced = false;
    if (_listening) {
      trayManager.removeListener(this);
      _listening = false;
    }
    await trayManager.destroy();
  }

  @override
  void onSelected(void Function(String key) handler) => _handler = handler;

  // A click on the icon opens the menu on a Mac (tray_manager does not do it
  // by itself) and on Windows, where the right button is the usual one and
  // the left one should not do nothing. Linux panels open it themselves.
  @override
  void onTrayIconMouseDown() {
    if (platform == SurfacePlatform.macos) trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {
    if (platform == SurfacePlatform.windows) trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconMouseUp() {
    if (platform == SurfacePlatform.windows) trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key != null) _handler?.call(key);
  }
}
