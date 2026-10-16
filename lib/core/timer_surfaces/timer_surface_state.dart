import 'package:equatable/equatable.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

import '../models/time_models.dart';
import 'timer_reliability.dart';
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
    this.unlockToAct = '',
    this.actionFailed = '',
    this.timeLabel = '',
    this.alarmTitle = '',
    this.alarmBreakOver = '',
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

  /// Why an action from a locked screen did nothing (Android, HIN-103).
  final String unlockToAct;

  /// Why an action from outside the app did nothing else: no answer from the
  /// server, or the session ended (Android).
  final String actionFailed;

  /// What the time on a Live Update is called (Android 17): one word, the
  /// same for work and a break.
  final String timeLabel;

  /// The countdown's title of an alarm (iOS 26, HIN-106): one word, the same
  /// for a countdown, work and a break.
  final String alarmTitle;

  /// A ringing alarm's title after a break: short, because the system's
  /// banner has one line, and its button already says how to go on.
  final String alarmBreakOver;

  /// The words as a background isolate reads them back (HIN-103).
  Map<String, String> toJson() => {
    'appName': appName,
    'countdownOver': countdownOver,
    'workOver': workOver,
    'breakOver': breakOver,
    'running': running,
    'onBreak': onBreak,
    'stop': stop,
    'takeBreak': takeBreak,
    'resume': resume,
    'idle': idle,
    // The idle widget's start button (iOS, HIN-105).
    'start': start,
    'unlockToAct': unlockToAct,
    'actionFailed': actionFailed,
    'timeLabel': timeLabel,
    'alarmTitle': alarmTitle,
    'alarmBreakOver': alarmBreakOver,
  };

  /// Anything missing reads as empty; a surface then shows less, not wrong.
  factory TimerSurfaceTexts.fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key] is String ? json[key] as String : '';
    return TimerSurfaceTexts(
      appName: text('appName'),
      countdownOver: text('countdownOver'),
      workOver: text('workOver'),
      breakOver: text('breakOver'),
      running: text('running'),
      onBreak: text('onBreak'),
      stop: text('stop'),
      takeBreak: text('takeBreak'),
      resume: text('resume'),
      idle: text('idle'),
      start: text('start'),
      unlockToAct: text('unlockToAct'),
      actionFailed: text('actionFailed'),
      timeLabel: text('timeLabel'),
      alarmTitle: text('alarmTitle'),
      alarmBreakOver: text('alarmBreakOver'),
    );
  }

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
    unlockToAct,
    actionFailed,
    timeLabel,
    alarmTitle,
    alarmBreakOver,
  ];
}

/// Where a Pomodoro stands in its set: the length of every phase of the set,
/// in order, and which of them runs. Lengths and a position, nothing else.
class PomodoroSetPosition extends Equatable {
  const PomodoroSetPosition({required this.minutes, required this.index});

  /// The most phases a set may have to be drawn as segments.
  static const maxPhases = 12;

  final List<int> minutes;
  final int index;

  /// Minutes of the set before the running phase.
  int get minutesBefore => minutes.take(index).fold(0, (a, b) => a + b);

  /// Where [timer] stands in its set; null outside a Pomodoro, for a broken
  /// configuration, or for a set too long to draw.
  static PomodoroSetPosition? of(RunningTimer timer) {
    final config = timer.pomodoro;
    final phase = timer.phase;
    if (timer.mode != TimerMode.pomodoro || config == null || phase == null) {
      return null;
    }
    final cycles = config.cycles;
    if (cycles < 1 || cycles * 2 > maxPhases) return null;
    // A set: work, short break, work, … work, long break. A break follows the
    // work interval that was just counted, so it sits right after that one.
    // An interval under a minute is not counted, so a break can follow none:
    // it then sits after the first.
    final done = timer.cyclesDone;
    final index = switch (phase) {
      TimerPhase.work => 2 * (done % cycles),
      TimerPhase.longBreak => 2 * cycles - 1,
      TimerPhase.shortBreak => 2 * (done < 1 ? 0 : (done - 1) % cycles) + 1,
    };
    return PomodoroSetPosition(
      minutes: [
        for (var i = 0; i < cycles; i++) ...[
          config.work,
          i == cycles - 1 ? config.longBreak : config.shortBreak,
        ],
      ],
      index: index,
    );
  }

  @override
  List<Object?> get props => [minutes, index];
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
    this.backgroundUpdates = false,
    this.liveUpdate = false,
    this.reliabilityService = false,
    this.alarmMode = false,
    this.pomodoroSet,
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

  /// The Live Activity takes updates from the server while the app sleeps
  /// (iOS, HIN-103); only then does it register for them.
  final bool backgroundUpdates;

  /// The running timer's notification asks to be a Live Update (Android 16+).
  final bool liveUpdate;

  /// A foreground service holds the running timer's notification (Android).
  final bool reliabilityService;

  /// The end of this stretch rings as a system alarm (iOS 26, HIN-106)
  /// instead of a notification, and the system's countdown replaces the app's
  /// own Live Activity for a countdown or a Pomodoro. Only while the person
  /// switched it on and the system lets the app set alarms.
  final bool alarmMode;

  /// Where a Pomodoro stands in its set, for the Live Update's segments.
  final PomodoroSetPosition? pomodoroSet;

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
    backgroundUpdates,
    liveUpdate,
    reliabilityService,
    alarmMode,
    pomodoroSet,
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
/// [alarmsUsable] says whether this device can ring alarms right now (iOS 26,
/// allowed by the person, below the system's limit).
TimerSurfaceState deriveTimerSurfaceState(
  RunningTimer? timer,
  TimerSurfacePrefs prefs, {
  required bool gated,
  bool alarmsUsable = false,
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
    backgroundUpdates:
        on && prefs.runningSurface && prefs.backgroundLiveActivity,
    liveUpdate: on && prefs.runningSurface && prefs.liveUpdate,
    reliabilityService:
        kTimerReliabilityService &&
        on &&
        prefs.runningSurface &&
        prefs.reliabilityService,
    alarmMode:
        alarmsUsable &&
        on &&
        prefs.phaseEndNotification &&
        prefs.alarmMode &&
        target != null,
    pomodoroSet: PomodoroSetPosition.of(timer),
    toggleHotkey: standing.toggleHotkey,
    focusHotkey: standing.focusHotkey,
    confirmed: confirmed,
    texts: texts,
  );
}
