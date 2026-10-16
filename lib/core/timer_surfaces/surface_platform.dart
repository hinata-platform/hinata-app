import 'package:flutter/foundation.dart';

import 'timer_surface.dart';

/// The one place that decides which platform the timer surfaces are on.
///
/// `kIsWeb` first: on the web [defaultTargetPlatform] reports the browser's
/// operating system, and a Safari on a Mac must not get the macOS surfaces.
enum SurfacePlatform {
  web,
  android,
  ios,
  macos,
  windows,
  linux,
  other;

  static SurfacePlatform get current {
    if (kIsWeb) return SurfacePlatform.web;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => SurfacePlatform.android,
      TargetPlatform.iOS => SurfacePlatform.ios,
      TargetPlatform.macOS => SurfacePlatform.macos,
      TargetPlatform.windows => SurfacePlatform.windows,
      TargetPlatform.linux => SurfacePlatform.linux,
      TargetPlatform.fuchsia => SurfacePlatform.other,
    };
  }
}

/// What the surfaces of [platform] can do, without asking a plugin.
TimerSurfaceCapabilities capabilitiesForPlatform(SurfacePlatform platform) =>
    switch (platform) {
      SurfacePlatform.android => const TimerSurfaceCapabilities(
        phaseEndNotification: true,
        schedulesAhead: true,
        runningSurface: true,
        lockScreen: true,
        exactAlarms: true,
      ),
      // The running timer is the Live Activity and the widgets (HIN-102).
      SurfacePlatform.ios => const TimerSurfaceCapabilities(
        phaseEndNotification: true,
        schedulesAhead: true,
        runningSurface: true,
        lockScreen: true,
      ),
      // The running timer is the menu bar's clock on a Mac, the tray icon with
      // its tooltip on Windows and the bare tray icon on Linux; no window
      // title on the desktop.
      SurfacePlatform.macos => const TimerSurfaceCapabilities(
        phaseEndNotification: true,
        schedulesAhead: true,
        runningSurface: true,
        trayIcon: true,
        keepRunning: true,
        globalHotkeys: true,
      ),
      SurfacePlatform.windows => const TimerSurfaceCapabilities(
        phaseEndNotification: true,
        schedulesAhead: true,
        runningSurface: true,
        trayIcon: true,
        keepRunning: true,
        globalHotkeys: true,
        taskbar: true,
      ),
      // The tray is best effort here (a desktop without a StatusNotifierItem
      // host shows nothing), and so are the shortcuts: the GlobalShortcuts
      // portal binds them where the desktop has a backend for it (KDE, GNOME
      // 48 and later), and the desktop picks the keys.
      SurfacePlatform.linux => const TimerSurfaceCapabilities(
        phaseEndNotification: true,
        runningSurface: true,
        trayIcon: true,
        keepRunning: true,
        globalHotkeys: true,
        hotkeysBySystem: true,
      ),
      // On the web the running timer is the app badge of an installed app.
      SurfacePlatform.web => const TimerSurfaceCapabilities(
        phaseEndNotification: true,
        runningSurface: true,
        titleClock: true,
      ),
      SurfacePlatform.other => TimerSurfaceCapabilities.none,
    };

/// Where the running timer sits on [platform], as the suffix of its texts:
/// `MenuBar` on a Mac, `Tray` (the notification area) on Windows and Linux,
/// `Web` for the app badge, `Ios` for the Live Activity and the widgets,
/// empty for Android's notification.
String surfacePlace(SurfacePlatform platform) => switch (platform) {
  SurfacePlatform.web => 'Web',
  SurfacePlatform.ios => 'Ios',
  SurfacePlatform.macos => 'MenuBar',
  SurfacePlatform.windows || SurfacePlatform.linux => 'Tray',
  _ => '',
};
