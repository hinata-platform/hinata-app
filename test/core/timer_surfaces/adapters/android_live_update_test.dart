import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/adapters/android_live_update.dart';
import 'package:hinata/core/timer_surfaces/adapters/local_notifications_surface.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

import 'fake_host.dart';

/// The running timer as a Live Update (HIN-104), against the plugin's channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const texts = TimerSurfaceTexts(
    appName: 'Hinata',
    countdownOver: 'over',
    workOver: 'work over',
    breakOver: 'break over',
    running: 'Timer running',
    onBreak: 'On a break',
    stop: 'Stop',
    takeBreak: 'Take a break',
    resume: 'Resume',
    timeLabel: 'Time',
  );
  final now = DateTime.utc(2026, 10, 14, 9);
  const prefs = TimerSurfacePrefs(
    consented: true,
    runningSurface: true,
    liveUpdate: true,
  );

  RunningTimer pomodoro(TimerPhase phase, int done) => RunningTimer(
    id: 't1',
    startedAt: now,
    mode: TimerMode.pomodoro,
    pomodoro: const PomodoroConfig(),
    phase: phase,
    cyclesDone: done,
    description: 'Quarterly report',
  );

  TimerSurfaceState derive(RunningTimer timer, [TimerSurfacePrefs? with_]) =>
      deriveTimerSurfaceState(
        timer,
        with_ ?? prefs,
        gated: false,
        texts: texts,
        now: now,
      );

  group('PomodoroSetPosition', () {
    test('a set is every work interval with the break after it', () {
      final set = PomodoroSetPosition.of(pomodoro(TimerPhase.work, 0))!;
      expect(set.minutes, [25, 5, 25, 5, 25, 5, 25, 15]);
      expect(set.index, 0);
    });

    test('a break sits right after the interval it follows', () {
      expect(
        PomodoroSetPosition.of(pomodoro(TimerPhase.shortBreak, 1))!.index,
        1,
      );
      expect(PomodoroSetPosition.of(pomodoro(TimerPhase.work, 1))!.index, 2);
      expect(
        PomodoroSetPosition.of(pomodoro(TimerPhase.longBreak, 4))!.index,
        7,
      );
      expect(PomodoroSetPosition.of(pomodoro(TimerPhase.work, 4))!.index, 0);
    });

    test('a set too long to draw has no segments', () {
      final long = RunningTimer(
        id: 't1',
        startedAt: now,
        mode: TimerMode.pomodoro,
        pomodoro: const PomodoroConfig(cycles: 7),
        phase: TimerPhase.work,
      );
      expect(PomodoroSetPosition.of(long), isNull);
    });
  });

  group('AndroidLiveUpdate', () {
    test('switched off, the notification stays as it was', () {
      final state = derive(
        pomodoro(TimerPhase.work, 0),
        prefs.copyWith(liveUpdate: false),
      );
      expect(AndroidLiveUpdate.of(state).promote, isFalse);
      expect(AndroidLiveUpdate.of(state).style, isNull);
    });

    test(
      'a Pomodoro is one segment per phase with a point at each boundary',
      () {
        final style =
            AndroidLiveUpdate.of(derive(pomodoro(TimerPhase.work, 1))).style!
                as ProgressStyleInformation;
        expect(style.segments.map((s) => s.length), [
          25,
          5,
          25,
          5,
          25,
          5,
          25,
          15,
        ]);
        expect(style.points.map((p) => p.position), [
          25,
          30,
          55,
          60,
          85,
          90,
          115,
        ]);
        expect(style.progress, 30);
      },
    );

    test('work and a break look the same: one colour, no words', () {
      final work =
          AndroidLiveUpdate.of(derive(pomodoro(TimerPhase.work, 1))).style!
              as ProgressStyleInformation;
      final pause =
          AndroidLiveUpdate.of(
                derive(pomodoro(TimerPhase.shortBreak, 1)),
              ).style!
              as ProgressStyleInformation;
      final colours = {
        for (final s in [...work.segments, ...pause.segments]) s.color,
        for (final p in [...work.points, ...pause.points]) p.color,
      };
      expect(colours, {AndroidLiveUpdate.segmentColor});
    });

    test('a countdown and a stopwatch are one metric', () {
      final countdown = AndroidLiveUpdate.of(
        derive(
          RunningTimer(
            id: 't1',
            startedAt: now,
            mode: TimerMode.countdown,
            plannedMinutes: 30,
          ),
        ),
      );
      final metric =
          (countdown.style! as MetricStyleInformation).metrics.single;
      expect(metric.kind, NotificationMetricKind.timer);
      expect(metric.time, now.add(const Duration(minutes: 30)));
      expect(metric.label, 'Time');

      final stopwatch = AndroidLiveUpdate.of(
        derive(RunningTimer(id: 't1', startedAt: now)),
      );
      expect(
        (stopwatch.style! as MetricStyleInformation).metrics.single.kind,
        NotificationMetricKind.stopwatch,
      );
    });
  });

  group('LocalNotificationsSurface on Android', () {
    late List<MethodCall> calls;
    late FakeHost host;
    late LocalNotificationsSurface surface;

    setUp(() async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async {
              calls.add(call);
              return call.method == 'initialize' ? true : null;
            },
          );
      host = FakeHost();
      surface = LocalNotificationsSurface(
        SurfacePlatform.android,
        clock: () => now,
        actionToken: () async => 'token',
      );
      await surface.init(host);
    });

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    Map<Object?, Object?> lastRunning(String method) {
      final call = calls.lastWhere((c) => c.method == method);
      final args = call.arguments as Map<Object?, Object?>;
      final data = method == 'show'
          ? args
          : args['notificationData']! as Map<Object?, Object?>;
      expect(data['id'], LocalNotificationsSurface.runningId);
      return data['platformSpecifics']! as Map<Object?, Object?>;
    }

    test(
      'asks to be promoted, and the chip shows the clock, not a text',
      () async {
        await surface.apply(derive(pomodoro(TimerPhase.shortBreak, 1)));

        final android = lastRunning('show');
        expect(android['requestPromotedOngoing'], isTrue);
        expect(android['shortCriticalText'], isNull);
        expect(android['usesChronometer'], isTrue);
        expect(android['style'], AndroidNotificationStyle.progress.index);
      },
    );

    test('a swipe is not put back until the timer changes', () async {
      final state = derive(pomodoro(TimerPhase.work, 0));
      await surface.apply(state);
      surface.respond(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.notificationDismissed,
          id: LocalNotificationsSurface.runningId,
        ),
      );
      final shown = calls.where((c) => c.method == 'show').length;

      await surface.apply(state);
      expect(calls.where((c) => c.method == 'show').length, shown);
      expect(host.calls, isEmpty);

      await surface.apply(derive(pomodoro(TimerPhase.shortBreak, 1)));
      expect(calls.where((c) => c.method == 'show').length, shown + 1);
    });

    test(
      'the reliability mode holds the same notification in a service',
      () async {
        await surface.apply(
          derive(
            RunningTimer(id: 't1', startedAt: now),
            prefs.copyWith(reliabilityService: true),
          ),
        );

        final call = calls.lastWhere(
          (c) => c.method == 'startForegroundService',
        );
        final args = call.arguments as Map<Object?, Object?>;
        expect(args['foregroundServiceTypes'], [
          AndroidServiceForegroundType.foregroundServiceTypeSpecialUse.value,
        ]);
        expect(lastRunning('startForegroundService')['ongoing'], isTrue);

        await surface.apply(TimerSurfaceState.idle);
        expect(calls.last.method, isNot('startForegroundService'));
        expect(calls.map((c) => c.method), contains('stopForegroundService'));
      },
    );
  });
}
