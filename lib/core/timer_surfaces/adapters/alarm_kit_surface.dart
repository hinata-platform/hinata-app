import 'dart:async';

import 'package:alarm_kit/alarm_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../../models/time_models.dart';
import '../phase_end_schedule.dart';
import '../timer_surface.dart';
import '../timer_surface_state.dart';

/// Whether this device can ring the end of an interval as a system alarm
/// (iOS and iPadOS 26, HIN-106), read from AlarmKit.
///
/// Usable once the system has AlarmKit, the person allowed alarms and the
/// system did not refuse one for its limit in this run. The limit is not
/// published; once it is hit, notifications take over again until the next
/// launch.
class AlarmModeStatus extends ChangeNotifier {
  AlarmModeStatus({AlarmKit? kit}) : kit = kit ?? AlarmKit.instance;

  final AlarmKit kit;

  bool _supported = false;
  AlarmAuthorization _authorization = AlarmAuthorization.notDetermined;
  bool _limitReached = false;
  StreamSubscription<AlarmAuthorization>? _updates;

  bool get supported => _supported;
  AlarmAuthorization get authorization => _authorization;
  bool get limitReached => _limitReached;

  bool get usable =>
      _supported &&
      _authorization == AlarmAuthorization.authorized &&
      !_limitReached;

  /// Reads the system's answers again; on the first call it also follows
  /// every change the person makes in Settings.
  Future<void> refresh() async {
    try {
      final supported = await kit.isSupported();
      final authorization = supported
          ? await kit.authorizationState()
          : AlarmAuthorization.notDetermined;
      _set(supported, authorization);
      if (supported) {
        _updates ??= kit.authorizationUpdates.listen(
          (next) => _set(_supported, next),
          onError: (Object _) {},
        );
      }
    } on AlarmKitException catch (error) {
      debugPrint('AlarmKit not readable: ${error.code.name}');
      _set(false, AlarmAuthorization.notDetermined);
    }
  }

  /// The system refused an alarm for its limit.
  void reportLimit() {
    if (_limitReached) return;
    _limitReached = true;
    notifyListeners();
  }

  void _set(bool supported, AlarmAuthorization authorization) {
    if (supported == _supported && authorization == _authorization) return;
    _supported = supported;
    _authorization = authorization;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_updates?.cancel());
    super.dispose();
  }
}

/// The id of the alarm for a stretch that ends at [endsAt]: a UUID made of
/// the moment, so the alarms the system holds tell by themselves which
/// stretch they belong to, without a list kept on the side.
String alarmIdFor(DateTime endsAt) {
  final millis = endsAt.toUtc().millisecondsSinceEpoch;
  return 'a1a2b000-4e17-4a1a-8000-${millis.toRadixString(16).padLeft(12, '0')}';
}

/// The colour of the alarm and its countdown: the house honey, like the Live
/// Activity and the widgets, whatever tint the account chose.
const Color alarmTint = Color(0xFFD9A032);

/// The sound in the runner's bundle: the app's interval chime, repeated.
const String alarmSound = 'HinataAlarm.caf';

/// The end of a countdown or a Pomodoro phase as a system alarm (iOS and
/// iPadOS 26, HIN-106).
///
/// One alarm at most, for the stretch that runs, ringing the moment its
/// notification would come. The system keeps it when the app is closed and
/// rings it through silent mode and Focus; its countdown replaces the app's
/// own Live Activity for that stretch. Stop and the next phase are the app's
/// intents, so a press does on the server what the same button in the app
/// does.
///
/// The system holds alarms, the server holds the timer: every state compares
/// the two ([AlarmKit.alarms]) and cancels what has no timer and plans what
/// has none. What the system keeps is generic: a title the person reads
/// anyway, the times, and one word for the extension (countdown, work,
/// break). Never the description, a project or an id of the timer.
class AlarmKitSurface extends TimerSurface {
  AlarmKitSurface({
    required this.status,
    this.mayClear,
    DateTime Function()? clock,
    this.follow = true,
  }) : _clock = clock ?? DateTime.now;

  final AlarmModeStatus status;

  /// Whether [clear] may cancel the alarms now. The host says no while the
  /// session is only being read back (a launch in the background, HIN-105):
  /// a cold start must never take an alarm away. Always when null.
  final bool Function()? mayClear;

  /// Whether to follow the system's changes ([AlarmKit.alarmUpdates]). A
  /// background engine only draws once and goes.
  final bool follow;

  final DateTime Function() _clock;

  AlarmKit get _kit => status.kit;

  TimerSurfaceHost? _host;
  TimerSurfaceState _last = TimerSurfaceState.idle;
  StreamSubscription<List<Alarm>>? _updates;

  /// One comparison at a time: a state and an update from the system must not
  /// both plan the same alarm.
  Future<void> _queue = Future.value();

  @override
  String get id => 'alarm-kit';

  @override
  TimerSurfaceCapabilities get capabilities => TimerSurfaceCapabilities.none;

  @override
  Future<void> init(TimerSurfaceHost host) async {
    _host = host;
    await status.refresh();
    if (follow && status.supported) {
      _updates ??= _kit.alarmUpdates.listen(
        (_) => _enqueue(() => _reconcile(_last)),
        onError: (Object _) {},
      );
    }
  }

  @override
  Future<void> apply(TimerSurfaceState state) {
    _last = state;
    return _enqueue(() => _reconcile(state));
  }

  Future<void> _enqueue(Future<void> Function() work) {
    final next = _queue.then((_) => work());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _reconcile(TimerSurfaceState state) async {
    if (!status.supported) return;
    final at = PhaseEndSchedule.alarmAt(state, _clock());
    final endsAt = state.endsAt;
    final wanted = at == null || endsAt == null ? null : alarmIdFor(endsAt);
    final List<Alarm> alarms;
    try {
      alarms = await _kit.alarms();
    } on AlarmKitException catch (error) {
      debugPrint('Alarms not readable: ${error.code.name}');
      return;
    }
    for (final alarm in alarms) {
      if (alarm.id == wanted) continue;
      // One that rings right now stays for the person to silence while the
      // app is not in front: the stretch it announces has just ended. In
      // front, the app says it, and a new stretch means the person acted.
      if (alarm.state == AlarmState.alerting &&
          wanted == null &&
          !(_host?.isForeground ?? false)) {
        continue;
      }
      await _cancel(alarm.id);
    }
    if (wanted == null || at == null) return;
    if (alarms.any((alarm) => alarm.id == wanted)) return;
    await _schedule(wanted, at, state);
  }

  Future<void> _schedule(
    String id,
    DateTime at,
    TimerSurfaceState state,
  ) async {
    final pomodoro = state.mode == TimerMode.pomodoro;
    try {
      await _kit.scheduleTimer(
        id: id,
        duration: at.difference(_clock().toUtc()),
        tint: alarmTint,
        sound: alarmSound,
        metadataKind: alarmKind(state),
        // The names of TimerBackgroundCommand, which AppDelegate maps back.
        stopIntent: 'stop',
        secondaryIntent: pomodoro ? 'advancePhase' : null,
        presentation: alarmPresentation(state),
      );
    } on AlarmKitException catch (error) {
      switch (error.code) {
        case AlarmKitErrorCode.maximumLimitReached:
          status.reportLimit();
        case AlarmKitErrorCode.notAuthorized:
          await status.refresh();
        default:
          debugPrint('Alarm not planned: ${error.code.name}');
      }
    }
  }

  Future<void> _cancel(String id) async {
    try {
      await _kit.cancel(id);
    } on AlarmKitException catch (error) {
      // Gone already: stopped by its own button or by the system.
      debugPrint('Alarm not cancelled: ${error.code.name}');
    }
  }

  /// In front, the toast says it: the alarm planned for this moment goes, as
  /// the planned notification does.
  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {
    final endsAt = state.endsAt;
    if (!foreground || endsAt == null || !status.supported) return;
    await _enqueue(() => _cancel(alarmIdFor(endsAt)));
  }

  @override
  Future<void> clear() async {
    if (!status.supported || !(mayClear?.call() ?? true)) return;
    _last = TimerSurfaceState.idle;
    await _enqueue(() async {
      try {
        for (final alarm in await _kit.alarms()) {
          await _cancel(alarm.id);
        }
      } on AlarmKitException catch (error) {
        debugPrint('Alarms not cleared: ${error.code.name}');
      }
    });
  }

  @override
  Future<void> dispose() async {
    await _updates?.cancel();
    _updates = null;
  }
}

/// The one word the widget extension reads: which glyph and which buttons.
String alarmKind(TimerSurfaceState state) {
  if (state.mode != TimerMode.pomodoro) return 'countdown';
  return state.isBreak ? 'break' : 'work';
}

/// What the system shows for the alarm of [state]. The words the
/// notification it replaces would say (shorter after a break, where the
/// button says how to go on), and a title for the countdown that does not
/// tell work from a break on a lock screen.
AlarmPresentation alarmPresentation(TimerSurfaceState state) {
  final texts = state.texts;
  final pomodoro = state.mode == TimerMode.pomodoro;
  return AlarmPresentation(
    alert: AlarmAlert(
      title: pomodoro && state.isBreak && texts.alarmBreakOver.isNotEmpty
          ? texts.alarmBreakOver
          : state.endText,
      stopButton: AlarmButton(
        text: texts.stop,
        systemImageName: 'stop.fill',
        textColor: const Color(0xFFFFFFFF),
      ),
      secondaryButton: pomodoro
          ? AlarmButton(
              text: state.isBreak ? texts.resume : texts.takeBreak,
              systemImageName: state.isBreak
                  ? 'play.fill'
                  : 'cup.and.saucer.fill',
              textColor: alarmTint,
            )
          : null,
      secondaryBehavior: pomodoro ? AlarmSecondaryBehavior.custom : null,
    ),
    countdown: AlarmCountdown(title: texts.alarmTitle),
  );
}
