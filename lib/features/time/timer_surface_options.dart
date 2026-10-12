import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/timer_surfaces/adapters/live_activity_surface.dart';
import '../../core/timer_surfaces/adapters/local_notifications_surface.dart';
import '../../core/timer_surfaces/adapters/web_notification_surface.dart';
import '../../core/timer_surfaces/surface_platform.dart';
import '../../core/timer_surfaces/timer_surface_prefs.dart';

/// One switch of the timer outside the app, as the introduction and the
/// settings both offer it.
///
/// One table instead of two lists of rows, so the introduction can never offer
/// a switch the settings do not have, or the other way round.
enum TimerSurfaceOption {
  phaseEnd,
  running,
  details,
  lockDetails,
  titleClock,

  /// Closing the window leaves a running timer in the menu bar or tray.
  keepRunning,

  /// The master switch of the system-wide shortcuts; their combinations are
  /// set in the settings, below it.
  hotkeys,

  /// The Live Activity follows the timer while the app sleeps (iOS): the
  /// server sends each change, sealed, through the push services.
  backgroundUpdates;

  /// Whether [platform] has anything this switch could turn on.
  bool availableOn(SurfacePlatform platform) {
    final caps = capabilitiesForPlatform(platform);
    return switch (this) {
      phaseEnd => caps.phaseEndNotification,
      running => caps.runningSurface,
      // Only a surface that carries a label can show a description; the web
      // badge is a dot, a Linux tray menu is readable on the session bus by
      // any process, open or not, and on iOS everything that shows the
      // running timer is on the lock screen too (its own switch).
      details =>
        caps.runningSurface &&
            platform != SurfacePlatform.web &&
            platform != SurfacePlatform.linux &&
            platform != SurfacePlatform.ios,
      lockDetails => caps.lockScreen && caps.runningSurface,
      titleClock => caps.titleClock,
      keepRunning => caps.keepRunning,
      hotkeys => caps.globalHotkeys,
      backgroundUpdates => platform == SurfacePlatform.ios,
    };
  }

  /// Whether the introduction offers it. The shortcuts are a power feature
  /// with combinations to choose; they wait in the settings.
  /// The background updates send the timer's state through third parties, so
  /// they are asked for on their own, in the settings, never in passing.
  bool get inIntro => this != hotkeys && this != backgroundUpdates;

  /// Whether turning this on needs the system's permission for notifications.
  /// A Live Activity and the widgets ask for none.
  bool needsPermission(SurfacePlatform platform) => switch (this) {
    phaseEnd => true,
    // Only Android's ongoing notification; the menu bar, the tray and the
    // web's badge are no notification.
    running => platform == SurfacePlatform.android,
    _ => false,
  };

  /// Switches that only mean something while the running timer is shown: the
  /// details, keeping it running when the window closes, and the shortcuts,
  /// which must never start a timer nothing outside the app shows.
  bool get dependsOnRunning =>
      this == details ||
      this == lockDetails ||
      this == keepRunning ||
      this == hotkeys ||
      this == backgroundUpdates;

  IconData get icon => switch (this) {
    phaseEnd => LucideIcons.bellRing,
    running => LucideIcons.timer,
    details => LucideIcons.textSearch,
    lockDetails => LucideIcons.lockKeyhole,
    titleClock => LucideIcons.panelTop,
    keepRunning => LucideIcons.panelTopClose,
    hotkeys => LucideIcons.keyboard,
    backgroundUpdates => LucideIcons.refreshCw,
  };

  String labelKey(SurfacePlatform platform) => switch (this) {
    phaseEnd => 'account.timerSurfaces.phaseEnd',
    running => 'account.timerSurfaces.running${surfacePlace(platform)}',
    details =>
      capabilitiesForPlatform(platform).trayIcon
          ? 'account.timerSurfaces.detailsMenu'
          : 'account.timerSurfaces.details',
    lockDetails => 'account.timerSurfaces.lockDetails',
    titleClock => 'account.timerSurfaces.titleClock',
    keepRunning => 'account.timerSurfaces.keepRunning',
    hotkeys => 'account.timerSurfaces.hotkeys',
    backgroundUpdates => 'account.timerSurfaces.backgroundUpdates',
  };

  String hintKey(SurfacePlatform platform) => switch (this) {
    phaseEnd => 'account.timerSurfaces.phaseEndHint',
    running => 'account.timerSurfaces.running${surfacePlace(platform)}Hint',
    details =>
      capabilitiesForPlatform(platform).trayIcon
          ? 'account.timerSurfaces.detailsMenuHint'
          : 'account.timerSurfaces.detailsHint',
    lockDetails => 'account.timerSurfaces.lockDetailsHint',
    titleClock => 'account.timerSurfaces.titleClockHint',
    keepRunning =>
      'account.timerSurfaces.keepRunning${surfacePlace(platform)}Hint',
    hotkeys => 'account.timerSurfaces.hotkeysHint',
    backgroundUpdates => 'account.timerSurfaces.backgroundUpdatesHint',
  };

  bool read(TimerSurfacePrefs prefs) => switch (this) {
    phaseEnd => prefs.phaseEndNotification,
    running => prefs.runningSurface,
    details => prefs.surfaceDetails,
    lockDetails => prefs.lockScreenDetails,
    titleClock => prefs.titleClock,
    keepRunning => prefs.keepInTray,
    hotkeys => prefs.globalHotkeys,
    backgroundUpdates => prefs.backgroundLiveActivity,
  };

  TimerSurfacePrefs write(TimerSurfacePrefs prefs, bool on) => switch (this) {
    phaseEnd => prefs.copyWith(phaseEndNotification: on),
    running => prefs.copyWith(runningSurface: on),
    details => prefs.copyWith(surfaceDetails: on),
    lockDetails => prefs.copyWith(lockScreenDetails: on),
    titleClock => prefs.copyWith(titleClock: on),
    keepRunning => prefs.copyWith(keepInTray: on),
    hotkeys => prefs.copyWith(globalHotkeys: on),
    backgroundUpdates => prefs.copyWith(backgroundLiveActivity: on),
  };

  /// The switches [platform] offers, in the order they are shown.
  static List<TimerSurfaceOption> offeredOn(SurfacePlatform platform) => [
    for (final option in values)
      if (option.availableOn(platform)) option,
  ];
}

/// [prefs] with [option] set to [on]. Switching the running timer off also
/// switches its details off, so they do not come back unasked with it.
TimerSurfacePrefs withOption(
  TimerSurfacePrefs prefs,
  TimerSurfaceOption option,
  bool on,
) {
  final next = option.write(prefs, on);
  if (option != TimerSurfaceOption.running || on) return next;
  return next.copyWith(
    surfaceDetails: false,
    lockScreenDetails: false,
    keepInTray: false,
    globalHotkeys: false,
    backgroundLiveActivity: false,
  );
}

/// [prefs] with the shortcuts switched on, with the conventional combinations
/// where none was chosen before.
TimerSurfacePrefs withHotkeysOn(
  TimerSurfacePrefs prefs,
  SurfacePlatform platform,
) => prefs.copyWith(
  globalHotkeys: true,
  toggleHotkey:
      prefs.toggleHotkey ?? TimerSurfacePrefs.defaultToggleHotkey(platform),
  focusHotkey:
      prefs.focusHotkey ?? TimerSurfacePrefs.defaultFocusHotkey(platform),
);

/// Whether [platform] has any surface at all.
bool hasTimerSurfaces(SurfacePlatform platform) {
  final caps = capabilitiesForPlatform(platform);
  return caps.phaseEndNotification || caps.runningSurface || caps.titleClock;
}

/// Everything the switches ask of the system, behind one seam so widget tests
/// never reach a platform channel.
class TimerSurfacePermissionGate {
  const TimerSurfacePermissionGate();

  /// Asks to show notifications. On the web this must run inside the tap that
  /// asked for it, or the browser refuses without asking.
  Future<bool> request(SurfacePlatform platform) =>
      platform == SurfacePlatform.web
      ? WebNotificationPermission.request()
      : LocalNotificationPermissions(platform).request();

  /// Whether Live Activities are allowed for this app (iOS); true elsewhere,
  /// where nothing could switch them off.
  Future<bool> activitiesEnabled(SurfacePlatform platform) async {
    if (platform != SurfacePlatform.ios) return true;
    try {
      return await const LiveActivityChannel().areActivitiesEnabled();
    } catch (_) {
      return true;
    }
  }

  /// Whether the system delivers on the minute (Android 12 and later).
  Future<bool> canScheduleExact(SurfacePlatform platform) =>
      LocalNotificationPermissions(platform).canScheduleExact();

  /// Opens the system page for exact alarms.
  Future<void> requestExact(SurfacePlatform platform) =>
      LocalNotificationPermissions(platform).requestExact();

  /// The system page where notifications are allowed again, where a link can
  /// open it. Android and the browsers have none a URL reaches.
  Uri? settingsUri(SurfacePlatform platform) => switch (platform) {
    SurfacePlatform.ios => Uri.parse('app-settings:'),
    SurfacePlatform.macos => Uri.parse(
      'x-apple.systempreferences:com.apple.preference.notifications',
    ),
    SurfacePlatform.windows => Uri.parse('ms-settings:notifications'),
    _ => null,
  };

  Future<void> openSettings(Uri uri) async {
    try {
      await launchUrl(uri);
    } catch (_) {
      // Nothing to do: the note already says where to look.
    }
  }
}

/// The person's switches, where somebody provided them.
///
/// The app always does. A screen pumped on its own in a test, or a sheet
/// opened from a context without them, simply shows nothing about surfaces
/// instead of failing.
TimerSurfacePrefsCubit? maybeTimerSurfacePrefs(BuildContext context) {
  try {
    return context.read<TimerSurfacePrefsCubit>();
  } on ProviderNotFoundException {
    return null;
  }
}
