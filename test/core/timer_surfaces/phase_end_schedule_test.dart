import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/phase_end_schedule.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

void main() {
  final end = DateTime.utc(2026, 10, 11, 9, 25);

  TimerSurfaceState countdown({DateTime? endsAt, bool notify = true}) =>
      TimerSurfaceState(
        running: true,
        mode: TimerMode.countdown,
        startedAt: DateTime.utc(2026, 10, 11, 9),
        endsAt: endsAt ?? end,
        phaseEndNotification: notify,
      );

  test('fires two seconds after the end, in UTC', () {
    final at = PhaseEndSchedule.fireAt(
      countdown(),
      DateTime.utc(2026, 10, 11, 9),
    );

    expect(at, end.add(const Duration(seconds: 2)));
    expect(at!.isUtc, isTrue);
  });

  test('plans nothing for an end in the past, switched off or a stopwatch', () {
    final now = DateTime.utc(2026, 10, 11, 10);
    expect(PhaseEndSchedule.fireAt(countdown(), now), isNull);
    expect(
      PhaseEndSchedule.fireAt(countdown(notify: false), DateTime.utc(2026)),
      isNull,
    );
    expect(
      PhaseEndSchedule.fireAt(
        const TimerSurfaceState(running: true, phaseEndNotification: true),
        DateTime.utc(2026),
      ),
      isNull,
    );
  });

  test('a zone offset in the input changes nothing', () {
    final local = DateTime.utc(2026, 10, 11, 9).toLocal();
    expect(
      PhaseEndSchedule.fireAt(countdown(), local),
      end.add(const Duration(seconds: 2)),
    );
  });

  group('the planner', () {
    final now = DateTime.utc(2026, 10, 11, 9);

    test('the same state twice plans once', () {
      final planner = PhaseEndPlanner();

      expect(planner.next(countdown(), now), isA<PhaseEndPlan>());
      expect(planner.next(countdown(), now), isA<PhaseEndKeep>());
    });

    test('a new end replaces the plan: there is never a second one', () {
      final planner = PhaseEndPlanner()..next(countdown(), now);
      final later = end.add(const Duration(minutes: 5));

      final action = planner.next(countdown(endsAt: later), now);

      expect(action, isA<PhaseEndPlan>());
      expect((action as PhaseEndPlan).at, later.add(PhaseEndSchedule.grace));
      expect(planner.planned, later.add(PhaseEndSchedule.grace));
    });

    test('a stopped timer withdraws the plan, once', () {
      final planner = PhaseEndPlanner()..next(countdown(), now);

      expect(planner.next(TimerSurfaceState.idle, now), isA<PhaseEndCancel>());
      expect(planner.next(TimerSurfaceState.idle, now), isA<PhaseEndKeep>());
    });

    test('a stopwatch plans nothing', () {
      final planner = PhaseEndPlanner();
      const stopwatch = TimerSurfaceState(
        running: true,
        mode: TimerMode.stopwatch,
        phaseEndNotification: true,
      );

      expect(planner.next(stopwatch, now), isA<PhaseEndKeep>());
      expect(planner.planned, isNull);
    });
  });
}
