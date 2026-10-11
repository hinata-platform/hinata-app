import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

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
  titleClock;

  /// Whether [platform] has anything this switch could turn on.
  bool availableOn(SurfacePlatform platform) {
    final caps = capabilitiesForPlatform(platform);
    return switch (this) {
      phaseEnd => caps.phaseEndNotification,
      running => caps.runningSurface,
      // Only a surface that carries a label can show a description; the web
      // badge is a dot.
      details => caps.runningSurface && platform != SurfacePlatform.web,
      lockDetails => caps.lockScreen && caps.runningSurface,
      titleClock => caps.titleClock,
    };
  }

  /// Whether turning this on needs the system's permission for notifications.
  bool needsPermission(SurfacePlatform platform) => switch (this) {
    phaseEnd => true,
    running => platform != SurfacePlatform.web,
    _ => false,
  };

  /// The details only mean something while the running timer is shown.
  bool get dependsOnRunning => this == details || this == lockDetails;

  IconData get icon => switch (this) {
    phaseEnd => LucideIcons.bellRing,
    running => LucideIcons.timer,
    details => LucideIcons.textSearch,
    lockDetails => LucideIcons.lockKeyhole,
    titleClock => LucideIcons.panelTop,
  };

  String labelKey(SurfacePlatform platform) => switch (this) {
    phaseEnd => 'account.timerSurfaces.phaseEnd',
    running =>
      platform == SurfacePlatform.web
          ? 'account.timerSurfaces.runningWeb'
          : 'account.timerSurfaces.running',
    details => 'account.timerSurfaces.details',
    lockDetails => 'account.timerSurfaces.lockDetails',
    titleClock => 'account.timerSurfaces.titleClock',
  };

  String hintKey(SurfacePlatform platform) => switch (this) {
    phaseEnd => 'account.timerSurfaces.phaseEndHint',
    running =>
      platform == SurfacePlatform.web
          ? 'account.timerSurfaces.runningWebHint'
          : 'account.timerSurfaces.runningHint',
    details => 'account.timerSurfaces.detailsHint',
    lockDetails => 'account.timerSurfaces.lockDetailsHint',
    titleClock => 'account.timerSurfaces.titleClockHint',
  };

  bool read(TimerSurfacePrefs prefs) => switch (this) {
    phaseEnd => prefs.phaseEndNotification,
    running => prefs.runningSurface,
    details => prefs.surfaceDetails,
    lockDetails => prefs.lockScreenDetails,
    titleClock => prefs.titleClock,
  };

  TimerSurfacePrefs write(TimerSurfacePrefs prefs, bool on) => switch (this) {
    phaseEnd => prefs.copyWith(phaseEndNotification: on),
    running => prefs.copyWith(runningSurface: on),
    details => prefs.copyWith(surfaceDetails: on),
    lockDetails => prefs.copyWith(lockScreenDetails: on),
    titleClock => prefs.copyWith(titleClock: on),
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
  return next.copyWith(surfaceDetails: false, lockScreenDetails: false);
}

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
