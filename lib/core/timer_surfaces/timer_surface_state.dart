import 'package:equatable/equatable.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

import '../models/time_models.dart';
import 'timer_surface_prefs.dart';

/// The words a surface may show, resolved in the reader's language.
///
/// Generic on purpose. A notification history outlives the moment on a shared
/// computer, so no text here ever names what the person works on; the
/// description travels separately in [TimerSurfaceState.label], and only when
/// the person switched it on.
class TimerSurfaceTexts extends Equatable {
  const TimerSurfaceTexts({
    required this.appName,
    required this.countdownOver,
    required this.workOver,
    required this.breakOver,
    required this.running,
    required this.onBreak,
    required this.stop,
    required this.takeBreak,
    required this.resume,
    this.start = '',
    this.nextPhase = '',
    this.openFocus = '',
    this.showWindow = '',
    this.quit = '',
    this.idle = '',
    this.stopwatch = '',
    this.countdown = '',
    this.focusPhase = '',
    this.breakPhase = '',
  });

  /// Empty texts: a surface that is handed these has nothing to show yet.
  static const empty = TimerSurfaceTexts(
    appName: '',
    countdownOver: '',
    workOver: '',
    breakOver: '',
    running: '',
    onBreak: '',
    stop: '',
    takeBreak: '',
    resume: '',
  );

  final String appName;
  final String countdownOver;
  final String workOver;
  final String breakOver;

  /// Title of the ongoing notification while work is being timed.
  final String running;

  /// Title of the ongoing notification during a break.
  final String onBreak;
  final String stop;
  final String takeBreak;
  final String resume;

  // The menu bar's and the tray's menu. The mode and the phase are words of
  // the open menu only: the icon, the title and the tooltip say "running"
  // and the time, the same for work and a break.
  final String start;
  final String nextPhase;
  final String openFocus;
  final String showWindow;
  final String quit;

  /// The tooltip and the menu's status line with no timer running.
  final String idle;
  final String stopwatch;
  final String countdown;
  final String focusPhase;
  final String breakPhase;

  @override
  List<Object?> get props => [
    appName,
    countdownOver,
    workOver,
    breakOver,
    running,
    onBreak,
    stop,
    takeBreak,
    resume,
    start,
    nextPhase,
    openFocus,
    showWindow,
    quit,
    idle,
    stopwatch,
    countdown,
    focusPhase,
    breakPhase,
  ];
}

/// What every surface outside the app draws, and nothing more.
///
/// It carries no project, issue, tag or billable flag, and no timer id: a
/// surface is a display of the server's timer and never needs to know which
/// record it is. Everything a surface would need to act on the timer goes back
/// through the running app ([TimerSurfaceHost]).
class TimerSurfaceState extends Equatable {
  const TimerSurfaceState({
    required this.running,
    this.mode,
    this.phase,
    this.startedAt,
    this.endsAt,
    this.label,
    this.lockScreenLabel,
    this.validUntil,
    this.phaseEndNotification = false,
    this.runningSurface = false,
    this.titleClock = false,
    this.keepInTray = false,
    this.toggleHotkey,
    this.focusHotkey,
    this.confirmed = true,
    this.texts = TimerSurfaceTexts.empty,
  });

  /// Nothing to show, and every surface clears.
  static const idle = TimerSurfaceState(running: false);

  final bool running;
  final TimerMode? mode;
  final TimerPhase? phase;

  /// When the timed stretch began, in UTC. For a Pomodoro that is the start of
  /// the current phase, which is what the server keeps for each phase.
  final DateTime? startedAt;

  /// When the current countdown or phase ends, in UTC; null for a stopwatch.
  final DateTime? endsAt;

  /// The description, only with the details switched on: in the running
  /// timer's notification (Android) or the open tray menu (desktop).
  final String? label;

  /// The description for lock-screen surfaces, only with that switch on.
  final String? lockScreenLabel;

  /// A local copy never outlives this moment, even if nothing clears it.
  final DateTime? validUntil;

  final bool phaseEndNotification;
  final bool runningSurface;
  final bool titleClock;

  /// Closing the window leaves the timer in the menu bar or tray.
  final bool keepInTray;

  /// The system-wide shortcuts to bind; null when switched off.
  final HotKey? toggleHotkey;
  final HotKey? focusHotkey;

  /// Whether the server confirmed this timer in this run; false for one read
  /// back from the cache. Surfaces that put up something new wait for it.
  final bool confirmed;
  final TimerSurfaceTexts texts;

  bool get isBreak => phase?.isBreak ?? false;

  /// Whether a surface outside the app may print the time.
  ///
  /// Not for a Pomodoro: the time shown there is what is left of the current
  /// interval, and a clock that jumps to 4:59 instead of 24:59 tells anyone
  /// watching the menu bar or a shared screen that a break began. The running
  /// mark says the same for work and a break; the time stays in the app.
  bool get showsClock => running && mode != TimerMode.pomodoro;

  /// What the notification at the end of this stretch says.
  String get endText {
    if (mode == TimerMode.countdown) return texts.countdownOver;
    return isBreak ? texts.breakOver : texts.workOver;
  }

  @override
  List<Object?> get props => [
    running,
    mode,
    phase,
    startedAt,
    endsAt,
    label,
    lockScreenLabel,
    validUntil,
    phaseEndNotification,
    runningSurface,
    titleClock,
    keepInTray,
    toggleHotkey,
    focusHotkey,
    confirmed,
    texts,
  ];
}

/// How long a local copy of a timer may live at most.
const Duration timerSurfaceLifetime = Duration(hours: 24);

/// The state the surfaces draw for [timer] under [prefs].
///
/// Nothing leaves the app before the person has confirmed the introduction:
/// without [TimerSurfacePrefs.consented] every switch reads as off, whatever
/// is stored. [gated] is the host's verdict on everything else that has to
/// hold (signed in, module on); a gated state is [TimerSurfaceState.idle].
TimerSurfaceState deriveTimerSurfaceState(
  RunningTimer? timer,
  TimerSurfacePrefs prefs, {
  required bool gated,
  TimerSurfaceTexts texts = TimerSurfaceTexts.empty,
  bool confirmed = true,
  DateTime? now,
}) {
  if (gated) return TimerSurfaceState.idle;
  final on = prefs.consented;
  // What stays with no timer running: the menu bar's icon and its "Start",
  // the close behaviour and the shortcuts, which start a timer too. Nothing
  // that announces or counts.
  final standing = TimerSurfaceState(
    running: false,
    runningSurface: on && prefs.runningSurface,
    keepInTray: on && prefs.runningSurface && prefs.keepInTray,
    // Only beside the menu bar or tray icon: a shortcut pressed by accident
    // must never start a timer that nothing outside the app shows.
    toggleHotkey: on && prefs.runningSurface && prefs.globalHotkeys
        ? prefs.toggleHotkey
        : null,
    focusHotkey: on && prefs.runningSurface && prefs.globalHotkeys
        ? prefs.focusHotkey
        : null,
    texts: texts,
  );
  if (timer == null) return standing;
  final startedAt = timer.startedAt.toUtc();
  // A timer older than a day is no longer shown anywhere outside the app,
  // whatever the cached copy says; the server cuts such a timer anyway.
  if (!startedAt
      .add(timerSurfaceLifetime)
      .isAfter((now ?? DateTime.now()).toUtc())) {
    return standing;
  }
  final target = timer.target;
  final description = timer.description?.trim();
  final hasDescription = description != null && description.isNotEmpty;
  return TimerSurfaceState(
    running: true,
    mode: timer.mode,
    phase: timer.phase,
    startedAt: startedAt,
    endsAt: target == null ? null : startedAt.add(target),
    label: on && prefs.surfaceDetails && hasDescription ? description : null,
    lockScreenLabel: on && prefs.lockScreenDetails && hasDescription
        ? description
        : null,
    validUntil: startedAt.add(timerSurfaceLifetime),
    phaseEndNotification: on && prefs.phaseEndNotification,
    runningSurface: on && prefs.runningSurface,
    titleClock: on && prefs.titleClock,
    keepInTray: standing.keepInTray,
    toggleHotkey: standing.toggleHotkey,
    focusHotkey: standing.focusHotkey,
    confirmed: confirmed,
    texts: texts,
  );
}
