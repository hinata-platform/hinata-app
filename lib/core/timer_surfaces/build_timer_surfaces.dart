import 'adapters/local_notifications_surface.dart';
import 'adapters/web_notification_surface.dart';
import 'adapters/window_title_surface.dart';
import 'adapters/windows_toast_surface.dart';
import 'surface_platform.dart';
import 'timer_surface.dart';

/// The surfaces of [platform], in the order they are applied.
List<TimerSurface> buildTimerSurfaces(
  SurfacePlatform platform, {
  required String Function() appTitle,
  required String Function() flashText,
}) {
  final title = WindowTitleSurface(
    platform,
    appTitle: appTitle,
    flashText: flashText,
  );
  return switch (platform) {
    SurfacePlatform.android ||
    SurfacePlatform.ios ||
    SurfacePlatform.macos ||
    SurfacePlatform.linux => [LocalNotificationsSurface(platform), title],
    SurfacePlatform.windows => [WindowsToastSurface(), title],
    SurfacePlatform.web => [WebNotificationSurface(), title],
    SurfacePlatform.other => [title],
  };
}
