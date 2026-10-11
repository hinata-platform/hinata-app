import 'package:equatable/equatable.dart';

import 'timer_surface_state.dart';

/// What a surface can do on the platform it runs on.
///
/// A static table per platform ([capabilitiesForPlatform]), so the settings
/// can filter their rows without asking any plugin.
class TimerSurfaceCapabilities extends Equatable {
  const TimerSurfaceCapabilities({
    this.phaseEndNotification = false,
    this.schedulesAhead = false,
    this.runningSurface = false,
    this.lockScreen = false,
    this.titleClock = false,
    this.exactAlarms = false,
    this.trayIcon = false,
    this.keepRunning = false,
    this.globalHotkeys = false,
    this.taskbar = false,
  });

  static const none = TimerSurfaceCapabilities();

  /// Announces the end of an interval outside the app.
  final bool phaseEndNotification;

  /// Delivers that announcement with the app closed. Linux and the web show it
  /// only while the app runs in the background.
  final bool schedulesAhead;

  /// Shows the running timer outside the app.
  final bool runningSurface;

  /// Has something on the lock screen.
  final bool lockScreen;

  /// Can put the time in the window or tab title.
  final bool titleClock;

  /// Asks the system for the exact moment (Android 12 and later).
  final bool exactAlarms;

  /// Has an icon with a menu: in the menu bar on a Mac, in the tray (the
  /// notification area) on Windows and Linux.
  final bool trayIcon;

  /// Can close the window while the timer goes on in the menu bar or tray.
  final bool keepRunning;

  /// Can bind system-wide keyboard shortcuts.
  final bool globalHotkeys;

  /// Draws progress and buttons on the taskbar button (Windows).
  final bool taskbar;

  TimerSurfaceCapabilities operator |(TimerSurfaceCapabilities other) =>
      TimerSurfaceCapabilities(
        phaseEndNotification:
            phaseEndNotification || other.phaseEndNotification,
        schedulesAhead: schedulesAhead || other.schedulesAhead,
        runningSurface: runningSurface || other.runningSurface,
        lockScreen: lockScreen || other.lockScreen,
        titleClock: titleClock || other.titleClock,
        exactAlarms: exactAlarms || other.exactAlarms,
        trayIcon: trayIcon || other.trayIcon,
        keepRunning: keepRunning || other.keepRunning,
        globalHotkeys: globalHotkeys || other.globalHotkeys,
        taskbar: taskbar || other.taskbar,
      );

  @override
  List<Object?> get props => [
    phaseEndNotification,
    schedulesAhead,
    runningSurface,
    lockScreen,
    titleClock,
    exactAlarms,
    trayIcon,
    keepRunning,
    globalHotkeys,
    taskbar,
  ];
}

/// What a surface may ask of the running app.
///
/// Routes and the existing timer actions only. A surface never talks to the
/// server itself, so an action from a notification is the same request as the
/// button in the app, and the server cannot tell them apart.
abstract class TimerSurfaceHost {
  /// Whether the app is in front, so a surface can stay quiet while the in-app
  /// toast already says it.
  bool get isForeground;

  /// Stops the timer, or ends the session during a break.
  Future<void> end();

  /// Starts the plain stopwatch, the same start the timer bar's button makes.
  Future<void> start();

  /// Turns a Pomodoro to its next phase.
  Future<void> advancePhase();

  /// Opens the focus screen.
  void openFocus();

  /// Opens an in-app route.
  void openRoute(String route);

  /// Brings the app's window back to the front (from the menu bar or tray).
  Future<void> showWindow();

  /// Quits the app, the menu bar's "Quit".
  Future<void> quit();
}

/// One place outside the app the timer shows.
///
/// It only ever takes a [TimerSurfaceState]. There is no way to hand a surface
/// free text, so nothing else (a working-time hint, a reminder) can travel
/// through one.
abstract class TimerSurface {
  String get id;

  TimerSurfaceCapabilities get capabilities;

  Future<void> init(TimerSurfaceHost host);

  /// Draws [state]. Called on a change of state, never once a second.
  Future<void> apply(TimerSurfaceState state);

  /// The interval just ended while the app runs. In front, a surface withdraws
  /// what it planned (the toast says it); behind, a surface that cannot plan
  /// ahead shows it now.
  Future<void> phaseEnded(TimerSurfaceState state, {required bool foreground});

  /// The shown time once a second, for the few surfaces that print it.
  void tick(Duration shown) {}

  /// Removes everything this surface put outside the app.
  Future<void> clear();

  Future<void> dispose();
}
