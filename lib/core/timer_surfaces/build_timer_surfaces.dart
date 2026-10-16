import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'adapters/alarm_kit_surface.dart';
import 'adapters/app_intents_surface.dart';
import 'adapters/global_hotkeys_surface.dart';
import 'adapters/home_widget_surface.dart';
import 'adapters/keep_running_surface.dart';
import 'adapters/live_activity_surface.dart';
import 'adapters/local_notifications_surface.dart';
import 'adapters/tray_surface.dart';
import 'adapters/web_notification_surface.dart';
import 'adapters/window_title_surface.dart';
import 'adapters/windows_taskbar_surface.dart';
import 'adapters/windows_toast_surface.dart';
import 'live_activity_push_registry.dart';
import 'surface_platform.dart';
import 'timer_surface.dart';

/// What runs a button outside the app while the app is not in front
/// (HIN-103). Top-level functions from `core/timer_actions`, handed in so that
/// nothing in the surfaces talks to the server itself.
class TimerBackgroundCallbacks {
  const TimerBackgroundCallbacks({this.notification, this.widget});

  final DidReceiveBackgroundNotificationResponseCallback? notification;
  final Future<void> Function(Uri?)? widget;
}

/// The surfaces of [platform], in the order they are applied.
List<TimerSurface> buildTimerSurfaces(
  SurfacePlatform platform, {
  required String Function() appTitle,
  required String Function() flashText,
  required HotkeyStatus hotkeys,
  LiveActivityPushRegistry? liveActivityRegistry,
  TimerBackgroundCallbacks background = const TimerBackgroundCallbacks(),
  AlarmModeStatus? alarms,
  bool Function()? alarmsMayClear,
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
      GlobalHotkeysSurface(
        platform,
        status: hotkeys,
        trayAvailable: tray.available,
      ),
  ];
  // The widget buttons on iOS run App Intents (HIN-105); only Android's
  // widget and tile go through home_widget's background callback.
  HomeWidgetSurface widgets() => HomeWidgetSurface(
    platform,
    store: platform == SurfacePlatform.macos
        ? MacTimerWidgetStore()
        : TimerWidgetStore(
            backgroundAction: platform == SurfacePlatform.android
                ? background.widget
                : null,
          ),
  );
  LocalNotificationsSurface notifications() => LocalNotificationsSurface(
    platform,
    backgroundResponse: background.notification,
  );
  return switch (platform) {
    SurfacePlatform.ios => [
      notifications(),
      // Before the Live Activity: with alarms on, the system's countdown
      // takes its place for a countdown or a Pomodoro (HIN-106).
      if (alarms != null)
        AlarmKitSurface(status: alarms, mayClear: alarmsMayClear),
      LiveActivitySurface(registry: liveActivityRegistry),
      widgets(),
      // After the widgets: the controls read the record they just wrote.
      AppIntentsSurface(),
      title,
    ],
    SurfacePlatform.android => [notifications(), widgets(), title],
    // The Mac's widgets on the desktop and in Notification Center (HIN-108).
    SurfacePlatform.macos => [
      notifications(),
      ...desktop(tray()),
      widgets(),
      title,
    ],
    SurfacePlatform.linux => [notifications(), ...desktop(tray()), title],
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
