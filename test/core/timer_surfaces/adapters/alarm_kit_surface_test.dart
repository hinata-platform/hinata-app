import 'dart:async';

import 'package:alarm_kit/alarm_kit.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/adapters/alarm_kit_surface.dart';
import 'package:hinata/core/timer_surfaces/adapters/live_activity_surface.dart';
import 'package:hinata/core/timer_surfaces/phase_end_schedule.dart';
import 'package:hinata/core/timer_surfaces/timer_surface.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

/// The end of an interval as a system alarm (HIN-106), against a fake
/// AlarmKit: planned only with the switch on and alarms allowed, compared
/// with the server's timer on every state, never taken away by a cold start.
void main() {
  final now = DateTime.utc(2026, 10, 16, 12);
  final start = now.subtract(const Duration(minutes: 5));

  RunningTimer timer({
    TimerMode mode = TimerMode.countdown,
    TimerPhase? phase,
    DateTime? startedAt,
  }) => RunningTimer(
    id: 'timer-1',
    startedAt: startedAt ?? start,
    projectId: 'project-1',
    description: 'Quarterly report for the client',
    mode: mode,
    plannedMinutes: mode == TimerMode.countdown ? 25 : null,
    pomodoro: mode == TimerMode.pomodoro ? const PomodoroConfig() : null,
    phase: phase,
  );

  const texts = TimerSurfaceTexts(
    appName: 'Hinata',
    countdownOver: 'Countdown over',
    workOver: 'Interval over',
    breakOver: 'Break over',
    running: 'Timer running',
    onBreak: 'Break',
    stop: 'Stop',
    takeBreak: 'Take a break',
    resume: 'Resume',
    alarmTitle: 'Interval',
    alarmBreakOver: 'Break over.',
  );

  final alarmOn = TimerSurfacePrefs.suggested.copyWith(
    alarmMode: true,
    lockScreenDetails: true,
  );

  TimerSurfaceState state(
    RunningTimer? t, {
    TimerSurfacePrefs? prefs,
    bool usable = true,
  }) => deriveTimerSurfaceState(
    t,
    prefs ?? alarmOn,
    gated: false,
    alarmsUsable: usable,
    texts: texts,
    now: now,
  );

  late FakeAlarmKit kit;
  late AlarmModeStatus status;
  late TestHost host;
  late bool mayClear;
  late AlarmKitSurface surface;

  setUp(() async {
    kit = FakeAlarmKit();
    status = AlarmModeStatus(kit: kit);
    host = TestHost();
    mayClear = true;
    surface = AlarmKitSurface(
      status: status,
      mayClear: () => mayClear,
      clock: () => now,
    );
    await surface.init(host);
  });

  tearDown(() async {
    await surface.dispose();
    await kit.close();
  });

  group('the state', () {
    test(
      'asks for an alarm only with the switch, alarms allowed and an end',
      () {
        expect(state(timer()).alarmMode, isTrue);
        expect(state(timer(), usable: false).alarmMode, isFalse);
        expect(
          state(timer(), prefs: TimerSurfacePrefs.suggested).alarmMode,
          isFalse,
        );
        expect(
          state(
            timer(),
            prefs: alarmOn.copyWith(phaseEndNotification: false),
          ).alarmMode,
          isFalse,
        );
        expect(state(timer(mode: TimerMode.stopwatch)).alarmMode, isFalse);
        expect(TimerSurfacePrefs.suggested.alarmMode, isFalse);
      },
    );

    test('the alarm replaces the notification for the same moment', () {
      final on = state(timer());
      final off = state(timer(), usable: false);
      expect(PhaseEndSchedule.fireAt(on, now), isNull);
      expect(
        PhaseEndSchedule.alarmAt(on, now),
        PhaseEndSchedule.fireAt(off, now),
      );
      expect(PhaseEndSchedule.alarmAt(off, now), isNull);
    });

    test(
      'the Live Activity steps back for a countdown, not for a stopwatch',
      () {
        expect(liveActivityContent(state(timer()), now: now), isNull);
        expect(
          liveActivityContent(state(timer(), usable: false), now: now),
          isNotNull,
        );
        expect(
          liveActivityContent(
            state(timer(mode: TimerMode.stopwatch)),
            now: now,
          ),
          isNotNull,
        );
      },
    );
  });

  group('planning', () {
    test('a countdown plans one alarm at its end, with stop only', () async {
      await surface.apply(state(timer()));
      final end = start.add(const Duration(minutes: 25));
      expect(kit.scheduled, hasLength(1));
      final plan = kit.scheduled.single;
      expect(plan.id, alarmIdFor(end));
      expect(plan.duration, end.add(PhaseEndSchedule.grace).difference(now));
      expect(plan.stopIntent, 'stop');
      expect(plan.secondaryIntent, isNull);
      expect(plan.metadataKind, 'countdown');
      expect(plan.tint, alarmTint);
      expect(plan.sound, alarmSound);
      expect(plan.presentation.alert.title, 'Countdown over');
      expect(plan.presentation.alert.secondaryButton, isNull);
      expect(plan.presentation.countdown!.title, 'Interval');
    });

    test('a work phase offers the break, a break the way back', () async {
      await surface.apply(
        state(timer(mode: TimerMode.pomodoro, phase: TimerPhase.work)),
      );
      var plan = kit.scheduled.last;
      expect(plan.secondaryIntent, 'advancePhase');
      expect(plan.metadataKind, 'work');
      expect(plan.presentation.alert.title, 'Interval over');
      expect(plan.presentation.alert.secondaryButton!.text, 'Take a break');
      expect(
        plan.presentation.alert.secondaryBehavior,
        AlarmSecondaryBehavior.custom,
      );
      await surface.apply(
        state(
          timer(
            mode: TimerMode.pomodoro,
            phase: TimerPhase.shortBreak,
            startedAt: now,
          ),
        ),
      );
      plan = kit.scheduled.last;
      expect(plan.metadataKind, 'break');
      expect(plan.presentation.alert.title, 'Break over.');
      expect(plan.presentation.alert.secondaryButton!.text, 'Resume');
      // The work phase's alarm went with the new phase.
      expect(kit.held.map((a) => a.id), [plan.id]);
    });

    test(
      'never hands the system the description or any id of the timer',
      () async {
        await surface.apply(state(timer()));
        final plan = kit.scheduled.single;
        final words = [
          plan.presentation.alert.title,
          plan.presentation.alert.stopButton.text,
          plan.presentation.countdown!.title,
          plan.metadataKind,
          plan.id,
        ].join(' ');
        expect(words, isNot(contains('Quarterly')));
        expect(words, isNot(contains('timer-1')));
        expect(words, isNot(contains('project-1')));
      },
    );

    test('the same state twice plans once', () async {
      await surface.apply(state(timer()));
      await surface.apply(state(timer()));
      expect(kit.scheduled, hasLength(1));
    });

    test('nothing without the switch, and the switch off cancels', () async {
      await surface.apply(state(timer(), prefs: TimerSurfacePrefs.suggested));
      expect(kit.scheduled, isEmpty);
      await surface.apply(state(timer()));
      expect(kit.held, hasLength(1));
      await surface.apply(state(timer(), prefs: TimerSurfacePrefs.suggested));
      expect(kit.held, isEmpty);
    });

    test('nothing where the system has no AlarmKit', () async {
      final none = FakeAlarmKit(supported: false);
      final other = AlarmKitSurface(
        status: AlarmModeStatus(kit: none),
        clock: () => now,
      );
      await other.init(host);
      await other.apply(state(timer()));
      expect(none.scheduled, isEmpty);
      expect(none.calls, isEmpty);
      await none.close();
    });

    test('the limit is reported, so notifications take over', () async {
      kit.failNext = AlarmKitErrorCode.maximumLimitReached;
      await surface.apply(state(timer()));
      expect(status.limitReached, isTrue);
      expect(status.usable, isFalse);
    });
  });

  group('reconciling with the server', () {
    test('an alarm without a timer is cancelled', () async {
      kit.held.add(
        const Alarm(
          id: 'a1a2b000-4e17-4a1a-8000-00000000abcd',
          state: AlarmState.countdown,
        ),
      );
      await surface.apply(state(null));
      expect(kit.held, isEmpty);
    });

    test(
      'a timer without an alarm gets one, also after the system dropped it',
      () async {
        await surface.apply(state(timer()));
        kit.held.clear();
        kit.updates.add(const []);
        await pumpEventQueue();
        expect(kit.held, hasLength(1));
      },
    );

    test(
      'a ringing alarm stays for the person while the app is away',
      () async {
        await surface.apply(state(timer()));
        kit.held[0] = Alarm(id: kit.held[0].id, state: AlarmState.alerting);
        host.foreground = false;
        await surface.apply(state(null));
        expect(kit.held, hasLength(1));
      },
    );

    test('in front, a ringing alarm without a timer goes', () async {
      await surface.apply(state(timer()));
      kit.held[0] = Alarm(id: kit.held[0].id, state: AlarmState.alerting);
      await surface.apply(state(null));
      expect(kit.held, isEmpty);
    });

    test(
      'in front, the end withdraws the alarm the toast already says',
      () async {
        final running = state(timer());
        await surface.apply(running);
        await surface.phaseEnded(running, foreground: false);
        expect(kit.held, hasLength(1));
        await surface.phaseEnded(running, foreground: true);
        expect(kit.held, isEmpty);
      },
    );
  });

  group('clearing', () {
    test('a cold start does not take the alarms away', () async {
      await surface.apply(state(timer()));
      mayClear = false;
      await surface.clear();
      expect(kit.held, hasLength(1));
    });

    test('a sign-out or "Delete now" takes all of them', () async {
      await surface.apply(state(timer()));
      kit.held.add(
        const Alarm(
          id: 'a1a2b000-4e17-4a1a-8000-0000000000ff',
          state: AlarmState.alerting,
        ),
      );
      mayClear = true;
      await surface.clear();
      expect(kit.held, isEmpty);
    });
  });

  test('the alarm id is a UUID made of the end', () {
    final id = alarmIdFor(DateTime.utc(2026, 10, 16, 12, 25));
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-8[0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id),
      isTrue,
    );
    expect(alarmIdFor(DateTime.utc(2026, 10, 16, 12, 25)), id);
    expect(alarmIdFor(DateTime.utc(2026, 10, 16, 12, 26)), isNot(id));
  });

  test('the prefs keep the switch, and a broken store reads it as off', () {
    final on = const TimerSurfacePrefs().copyWith(alarmMode: true);
    expect(TimerSurfacePrefs.fromJson(on.toJson()).alarmMode, isTrue);
    expect(
      TimerSurfacePrefs.fromJson(const {'alarmMode': 'yes'}).alarmMode,
      isFalse,
    );
  });
}

class TestHost implements TimerSurfaceHost {
  bool foreground = true;

  @override
  bool get isForeground => foreground;

  @override
  Future<void> end() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> advancePhase() async {}

  @override
  void openFocus() {}

  @override
  void openRoute(String route) {}

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> quit() async {}
}

class Plan {
  Plan({
    required this.id,
    required this.duration,
    required this.presentation,
    required this.tint,
    this.metadataKind,
    this.stopIntent,
    this.secondaryIntent,
    this.sound,
  });

  final String id;
  final Duration duration;
  final AlarmPresentation presentation;
  final Color tint;
  final String? metadataKind;
  final String? stopIntent;
  final String? secondaryIntent;
  final String? sound;
}

/// The system's alarms of this app, in memory.
class FakeAlarmKit implements AlarmKit {
  FakeAlarmKit({this.supported = true});

  final bool supported;
  final List<Alarm> held = [];
  final List<Plan> scheduled = [];
  final List<String> calls = [];
  final StreamController<List<Alarm>> updates = StreamController.broadcast();
  AlarmKitErrorCode? failNext;

  Future<void> close() => updates.close();

  void _check() {
    if (!supported) {
      throw const AlarmKitException(AlarmKitErrorCode.unsupported);
    }
  }

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<AlarmAuthorization> authorizationState() async {
    _check();
    return AlarmAuthorization.authorized;
  }

  @override
  Future<AlarmAuthorization> requestAuthorization() => authorizationState();

  @override
  Stream<AlarmAuthorization> get authorizationUpdates => const Stream.empty();

  @override
  Stream<List<Alarm>> get alarmUpdates => updates.stream;

  @override
  Future<List<Alarm>> alarms() async {
    _check();
    calls.add('alarms');
    return List.of(held);
  }

  @override
  Future<Alarm> scheduleTimer({
    required String id,
    required Duration duration,
    required AlarmPresentation presentation,
    required Color tint,
    String? metadataKind,
    String? stopIntent,
    String? secondaryIntent,
    String? sound,
    Duration? postAlert,
  }) async {
    _check();
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw AlarmKitException(failure);
    }
    scheduled.add(
      Plan(
        id: id,
        duration: duration,
        presentation: presentation,
        tint: tint,
        metadataKind: metadataKind,
        stopIntent: stopIntent,
        secondaryIntent: secondaryIntent,
        sound: sound,
      ),
    );
    final alarm = Alarm(
      id: id,
      state: AlarmState.countdown,
      preAlert: duration,
    );
    held
      ..removeWhere((a) => a.id == id)
      ..add(alarm);
    return alarm;
  }

  @override
  Future<void> cancel(String id) async {
    _check();
    calls.add('cancel $id');
    held.removeWhere((a) => a.id == id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
