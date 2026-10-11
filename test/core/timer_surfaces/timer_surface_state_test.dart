import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

void main() {
  final start = DateTime.utc(2026, 10, 11, 9);

  RunningTimer timer({
    TimerMode mode = TimerMode.stopwatch,
    int? planned,
    TimerPhase? phase,
    String? description = 'Quarterly report for the client',
  }) => RunningTimer(
    id: 'timer-1',
    startedAt: start,
    projectId: 'project-1',
    issueId: 'issue-1',
    description: description,
    tags: const ['Review'],
    billable: true,
    mode: mode,
    plannedMinutes: planned,
    pomodoro: mode == TimerMode.pomodoro ? const PomodoroConfig() : null,
    phase: phase,
  );

  const everything = TimerSurfacePrefs(
    consented: true,
    introSeen: true,
    phaseEndNotification: true,
    runningSurface: true,
    surfaceDetails: true,
    lockScreenDetails: true,
    titleClock: true,
  );

  group('privacy by default', () {
    test('before the introduction is confirmed every switch reads as off', () {
      final state = deriveTimerSurfaceState(
        timer(),
        everything.copyWith(consented: false),
        gated: false,
      );

      expect(state.running, isTrue);
      expect(state.phaseEndNotification, isFalse);
      expect(state.runningSurface, isFalse);
      expect(state.titleClock, isFalse);
      expect(state.label, isNull);
      expect(state.lockScreenLabel, isNull);
    });

    test('with details off no surface gets the description', () {
      final state = deriveTimerSurfaceState(
        timer(),
        TimerSurfacePrefs.suggested,
        gated: false,
      );

      expect(state.label, isNull);
      expect(state.lockScreenLabel, isNull);
      expect(state.phaseEndNotification, isTrue);
      expect(state.runningSurface, isTrue);
    });

    test('details reach a surface only when switched on', () {
      final state = deriveTimerSurfaceState(timer(), everything, gated: false);

      expect(state.label, 'Quarterly report for the client');
      expect(state.lockScreenLabel, 'Quarterly report for the client');
    });

    test('the state names no project, issue, tag or timer', () {
      final state = deriveTimerSurfaceState(timer(), everything, gated: false);
      final printed = state.props.join(' ');

      expect(printed, isNot(contains('project-1')));
      expect(printed, isNot(contains('issue-1')));
      expect(printed, isNot(contains('timer-1')));
      expect(printed, isNot(contains('Review')));
    });

    test('a gated host draws nothing', () {
      expect(
        deriveTimerSurfaceState(timer(), everything, gated: true),
        TimerSurfaceState.idle,
      );
      expect(
        deriveTimerSurfaceState(null, everything, gated: false),
        TimerSurfaceState.idle,
      );
    });

    test('a local copy is valid for a day at most', () {
      final state = deriveTimerSurfaceState(timer(), everything, gated: false);

      expect(state.validUntil, start.add(const Duration(hours: 24)));
    });
  });

  group('the end of the stretch', () {
    test('a stopwatch has none', () {
      expect(
        deriveTimerSurfaceState(timer(), everything, gated: false).endsAt,
        isNull,
      );
    });

    test('a countdown ends after its planned minutes', () {
      final state = deriveTimerSurfaceState(
        timer(mode: TimerMode.countdown, planned: 25),
        everything,
        gated: false,
      );

      expect(state.endsAt, start.add(const Duration(minutes: 25)));
    });

    test('a Pomodoro phase ends after the length of that phase', () {
      final work = deriveTimerSurfaceState(
        timer(mode: TimerMode.pomodoro, phase: TimerPhase.work),
        everything,
        gated: false,
      );
      final rest = deriveTimerSurfaceState(
        timer(mode: TimerMode.pomodoro, phase: TimerPhase.shortBreak),
        everything,
        gated: false,
      );

      expect(work.endsAt, start.add(const Duration(minutes: 25)));
      expect(rest.endsAt, start.add(const Duration(minutes: 5)));
      expect(rest.isBreak, isTrue);
    });
  });
}
