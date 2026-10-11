import 'adapters/global_hotkeys_surface.dart';
import 'adapters/keep_running_surface.dart';
import 'adapters/local_notifications_surface.dart';
import 'adapters/tray_surface.dart';
import 'adapters/web_notification_surface.dart';
import 'adapters/window_title_surface.dart';
import 'adapters/windows_taskbar_surface.dart';
import 'adapters/windows_toast_surface.dart';
import 'surface_platform.dart';
import 'timer_surface.dart';

/// The surfaces of [platform], in the order they are applied.
List<TimerSurface> buildTimerSurfaces(
  SurfacePlatform platform, {
  required String Function() appTitle,
  required String Function() flashText,
  required HotkeyStatus hotkeys,
}) {
  final title = WindowTitleSurface(
    platform,
    appTitle: appTitle,
    flashText: flashText,
  );
  // The menu bar or tray first: the close behaviour asks whether it is there.
  TraySurface tray() => TraySurface(platform);
  List<TimerSurface> desktop(TraySurface tray) => [
    tray,
    KeepRunningSurface(platform, trayAvailable: tray.available),
    if (capabilitiesForPlatform(platform).globalHotkeys)
      GlobalHotkeysSurface(platform, status: hotkeys),
  ];
  return switch (platform) {
    SurfacePlatform.android ||
    SurfacePlatform.ios => [LocalNotificationsSurface(platform), title],
    SurfacePlatform.macos || SurfacePlatform.linux => [
      LocalNotificationsSurface(platform),
      ...desktop(tray()),
      title,
    ],
    SurfacePlatform.windows => [
      WindowsToastSurface(),
      ...desktop(tray()),
      if (capabilitiesForPlatform(platform).taskbar) WindowsTaskbarSurface(),
      title,
    ],
    SurfacePlatform.web => [WebNotificationSurface(), title],
    SurfacePlatform.other => [title],
  };
}
