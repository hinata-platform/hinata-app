import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/timer_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

/// What the app knows about the running timer, and who is allowed to say it.
///
/// The server owns whether a timer runs; the device owns the number on screen.
/// Both halves are worth pinning, and so is the boundary between them: what is
/// persisted is a cache that the next answer replaces, never an authority.
void main() {
  late _MemoryStorage storage;

  setUp(() {
    storage = _MemoryStorage();
    HydratedBloc.storage = storage;
  });

  RunningTimer timer({
    DateTime? startedAt,
    String? description = 'pairing',
    String? projectId,
  }) => RunningTimer(
    id: 't1',
    startedAt: startedAt ?? DateTime.now().subtract(const Duration(minutes: 3)),
    description: description,
    projectId: projectId,
  );

  group('what the server says', () {
    test('a refresh adopts the running timer and starts counting', () async {
      final repository = _FakeTimeRepository(running: timer());
      final cubit = TimerCubit(repository, storageId: 'server#me');

      await cubit.refresh();

      expect(cubit.state.isRunning, isTrue);
      expect(cubit.state.timer!.description, 'pairing');
      // Counted from the start, not from the moment the answer arrived.
      expect(cubit.state.elapsed.inMinutes, 3);
      await cubit.close();
    });

    test('a refresh that says nothing runs clears a stale timer', () async {
      final repository = _FakeTimeRepository(running: timer());
      final cubit = TimerCubit(repository, storageId: 'server#me');
      await cubit.refresh();

      repository.running = null;
      await cubit.refresh();

      expect(cubit.state.isRunning, isFalse);
      expect(cubit.state.elapsed, Duration.zero);
      await cubit.close();
    });

    test('a failed refresh keeps what we already had', () async {
      // Losing the network for a moment must not make a running timer vanish
      // from the bar — there is a perfectly good previous answer to keep.
      final repository = _FakeTimeRepository(running: timer());
      final cubit = TimerCubit(repository, storageId: 'server#me');
      await cubit.refresh();

      repository.failing = true;
      await cubit.refresh();

      expect(cubit.state.isRunning, isTrue);
      await cubit.close();
    });

    test('stopping returns the entry and clears the timer', () async {
      final repository = _FakeTimeRepository(running: timer());
      final cubit = TimerCubit(repository, storageId: 'server#me');
      await cubit.refresh();

      final saved = await cubit.stop();

      expect(saved, isNotNull);
      expect(saved!.entry.durationMinutes, 30);
      expect(cubit.state.isRunning, isFalse);
      // The stop names the timer it means. Without it a retry after a timeout
      // would end whatever is running by then, which on a flaky link is a
      // timer the person started seconds ago.
      expect(repository.stoppedIds, ['t1']);
      await cubit.close();
    });

    test('stopping when nothing runs asks the server nothing', () async {
      final repository = _FakeTimeRepository(running: null);
      final cubit = TimerCubit(repository, storageId: 'server#me');

      expect(await cubit.stop(), isNull);

      expect(repository.stoppedIds, isEmpty);
      await cubit.close();
    });

    test('a refused start leaves no timer and reports why', () async {
      final repository = _FakeTimeRepository(
        startFailure: 'A timer is already running',
      );
      final cubit = TimerCubit(repository, storageId: 'server#me');

      await cubit.start();

      expect(cubit.state.isRunning, isFalse);
      expect(cubit.state.errorMessage, 'A timer is already running');
      expect(cubit.state.isBusy, isFalse);
      await cubit.close();
    });
  });

  group('what the device persists', () {
    test(
      'the running timer survives a restart, already ticked forward',
      () async {
        final started = DateTime.now().subtract(const Duration(minutes: 12));
        final first = TimerCubit(
          _FakeTimeRepository(running: timer(startedAt: started)),
          storageId: 'server#me',
        );
        await first.refresh();
        await first.close();

        // A fresh launch: the bar is there before the first request comes back.
        final restored = TimerCubit(
          _FakeTimeRepository(running: null),
          storageId: 'server#me',
        );

        expect(restored.state.isRunning, isTrue);
        expect(restored.state.timer!.startedAt, started);
        // Not the twelve minutes that were persisted — the twelve that have
        // actually passed, recomputed from the start.
        expect(restored.state.elapsed.inMinutes, greaterThanOrEqualTo(12));
        await restored.close();
      },
    );

    test('what was restored loses to what the server says', () async {
      final first = TimerCubit(
        _FakeTimeRepository(running: timer()),
        storageId: 'server#me',
      );
      await first.refresh();
      await first.close();

      final restored = TimerCubit(
        _FakeTimeRepository(running: null),
        storageId: 'server#me',
      );
      expect(restored.state.isRunning, isTrue);

      await restored.refresh();

      expect(restored.state.isRunning, isFalse);
      await restored.close();
    });

    test('one account never restores another account\'s timer', () async {
      // The case this guards is a shared machine: signing in as somebody else
      // must not show what the previous person is working on.
      final mine = TimerCubit(
        _FakeTimeRepository(running: timer(description: 'my work')),
        storageId: 'server#me',
      );
      await mine.refresh();
      await mine.close();

      final theirs = TimerCubit(
        _FakeTimeRepository(running: null),
        storageId: 'server#someone-else',
      );

      expect(theirs.state.isRunning, isFalse);
      await theirs.close();
    });

    test('the same account on two servers keeps two timers apart', () async {
      final work = TimerCubit(
        _FakeTimeRepository(running: timer(description: 'day job')),
        storageId: 'https://work.example#me',
      );
      await work.refresh();
      await work.close();

      final other = TimerCubit(
        _FakeTimeRepository(running: null),
        storageId: 'https://other.example#me',
      );

      expect(other.state.isRunning, isFalse);
      await other.close();
    });

    test(
      'a stored blob of the wrong shape does not crash the launch',
      () async {
        storage.write('server#me', {'timer': 'not an object'});

        final cubit = TimerCubit(
          _FakeTimeRepository(running: null),
          storageId: 'server#me',
        );

        expect(cubit.state.isRunning, isFalse);
        await cubit.close();
      },
    );

    test('nothing is persisted once the timer stops', () async {
      final repository = _FakeTimeRepository(running: timer());
      final cubit = TimerCubit(repository, storageId: 'server#me');
      await cubit.refresh();
      await cubit.stop();
      await cubit.close();

      final restored = TimerCubit(
        _FakeTimeRepository(running: null),
        storageId: 'server#me',
      );

      expect(restored.state.isRunning, isFalse);
      await restored.close();
    });
  });

  group('changing a running timer', () {
    test('a re-file keeps everything the caller did not mention', () async {
      // The endpoint takes the timer's whole editable state, so anything this
      // call leaves out would be cleared on the server. What the caller means
      // is "file it here"; the rest has to be carried along for it.
      final repository = _FakeTimeRepository(
        running: timer(description: 'pairing'),
      );
      final cubit = TimerCubit(repository, storageId: 'server#me');
      await cubit.refresh();

      await cubit.patch(projectId: 'p1');

      expect(repository.patched, hasLength(1));
      expect(repository.patched.single.projectId, 'p1');
      expect(repository.patched.single.description, 'pairing');
    });

    test('clearing the project is a choice, not an omission', () async {
      final repository = _FakeTimeRepository(
        running: timer(description: 'pairing', projectId: 'p1'),
      );
      final cubit = TimerCubit(repository, storageId: 'server#me');
      await cubit.refresh();

      await cubit.patch(clearPlacement: true);

      // Without an explicit signal the fallback would put it straight back.
      expect(repository.patched.single.projectId, isNull);
      expect(repository.patched.single.description, 'pairing');
    });

    test('patching with no timer running does nothing at all', () async {
      final repository = _FakeTimeRepository(running: null);
      final cubit = TimerCubit(repository, storageId: 'server#me');

      await cubit.patch(projectId: 'p1');

      expect(repository.patched, isEmpty);
      await cubit.close();
    });
  });

  group('the elapsed reading', () {
    test('a device clock behind the server does not count backwards', () {
      // A phone whose clock is a few seconds slow would otherwise show a timer
      // that has not started yet, counting down towards zero.
      final future = RunningTimer(
        id: 't1',
        startedAt: DateTime.now().add(const Duration(seconds: 30)),
      );

      expect(future.elapsed(DateTime.now()), Duration.zero);
    });
  });

  group('how a timer counts', () {
    RunningTimer pomodoro({
      required TimerPhase phase,
      int cyclesDone = 0,
      Duration ago = Duration.zero,
      PomodoroConfig config = const PomodoroConfig(),
    }) => RunningTimer(
      id: 'p1',
      startedAt: DateTime.now().subtract(ago),
      mode: TimerMode.pomodoro,
      pomodoro: config,
      phase: phase,
      cyclesDone: cyclesDone,
    );

    test(
      'a countdown counts towards its target and a stopwatch does not',
      () async {
        final now = DateTime.now();
        final countdown = RunningTimer(
          id: 'c1',
          startedAt: now.subtract(const Duration(minutes: 10)),
          mode: TimerMode.countdown,
          plannedMinutes: 25,
        );
        expect(countdown.remaining(now)!.inMinutes, 15);
        expect(countdown.hasReachedTarget(now), isFalse);

        final plain = RunningTimer(id: 's1', startedAt: now);
        expect(plain.target, isNull);
        expect(plain.remaining(now), isNull);
        // A stopwatch is never "up": nothing is owed and nothing is over.
        expect(plain.hasReachedTarget(now), isFalse);
      },
    );

    test('a long break falls after a full set, a short one before it', () {
      const config = PomodoroConfig(cycles: 4);
      expect(config.phaseAfter(1), TimerPhase.shortBreak);
      expect(config.phaseAfter(3), TimerPhase.shortBreak);
      expect(config.phaseAfter(4), TimerPhase.longBreak);
      expect(config.breakAfter(4), 15);
      expect(config.breakAfter(3), 5);
    });

    test('a countdown that runs out signals once and stops itself', () async {
      final repository = _FakeTimeRepository(
        running: RunningTimer(
          id: 'c1',
          // Already past its target when the cubit adopts it — which is what a
          // phone that was asleep through the end comes back to.
          startedAt: DateTime.now().subtract(const Duration(minutes: 26)),
          mode: TimerMode.countdown,
          plannedMinutes: 25,
        ),
      );
      final cubit = TimerCubit(repository, storageId: 'server#me');
      final signals = <TimerSignal>[];
      final sub = cubit.stream
          .where((state) => state.signal != null)
          .listen((state) => signals.add(state.signal!));

      await cubit.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(signals, hasLength(1));
      expect(signals.single.mode, TimerMode.countdown);
      // The client reports the end; the server decides what the entry is worth.
      expect(repository.stoppedIds, ['c1']);
      expect(cubit.state.isRunning, isFalse);
      await sub.cancel();
      await cubit.close();
    });

    test(
      'a pomodoro work interval signals but does not turn its own phase',
      () async {
        final repository = _FakeTimeRepository(
          running: pomodoro(
            phase: TimerPhase.work,
            ago: const Duration(minutes: 26),
          ),
        );
        final cubit = TimerCubit(repository, storageId: 'server#me');
        final signals = <TimerSignal>[];
        final sub = cubit.stream
            .where((state) => state.signal != null)
            .listen((state) => signals.add(state.signal!));

        await cubit.refresh();
        await Future<void>.delayed(const Duration(milliseconds: 1200));

        expect(signals, hasLength(1));
        expect(signals.single.phase, TimerPhase.work);
        // The interval that just ended is counted, so the message can say "one
        // interval done" rather than "none".
        expect(signals.single.cyclesDone, 1);
        // Whether the break starts now is the person's to say. Nothing was
        // stopped and nothing was advanced.
        expect(repository.stoppedIds, isEmpty);
        expect(repository.phases, isEmpty);
        expect(cubit.state.isRunning, isTrue);
        await sub.cancel();
        await cubit.close();
      },
    );

    test('the same interval is never announced twice', () async {
      final repository = _FakeTimeRepository(
        running: pomodoro(
          phase: TimerPhase.shortBreak,
          cyclesDone: 1,
          ago: const Duration(minutes: 6),
        ),
      );
      final cubit = TimerCubit(repository, storageId: 'server#me');
      var announcements = 0;
      final sub = cubit.stream
          .where((state) => state.signal != null)
          .listen((_) => announcements++);

      await cubit.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      // A refresh of the same timer is not a new interval.
      await cubit.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(announcements, 1);
      await sub.cancel();
      await cubit.close();
    });

    test('advancing a phase names the timer it means', () async {
      final repository = _FakeTimeRepository(
        running: pomodoro(phase: TimerPhase.work),
      );
      final cubit = TimerCubit(repository, storageId: 'server#me');
      await cubit.refresh();

      await cubit.advancePhase();

      expect(cubit.state.timer!.phase, TimerPhase.shortBreak);
      expect(cubit.state.timer!.cyclesDone, 1);
      // A new document, so the next interval's entry cannot collide with the
      // one the last interval already became.
      expect(cubit.state.timer!.id, isNot('p1'));
      // And the new interval may be announced in its own right.
      expect(repository.phases, hasLength(1));
      await cubit.close();
    });

    test('a start carries the mode and its configuration', () async {
      final repository = _FakeTimeRepository();
      final cubit = TimerCubit(repository, storageId: 'server#me');

      await cubit.start(
        mode: TimerMode.pomodoro,
        plannedMinutes: 45,
        pomodoro: const PomodoroConfig(work: 50, cycles: 3),
      );

      expect(repository.started!.mode, TimerMode.pomodoro);
      expect(repository.started!.pomodoro!.work, 50);
      expect(cubit.state.timer!.phase, TimerPhase.work);
      await cubit.close();
    });

    test('what is persisted carries the run, not just the timer', () async {
      final repository = _FakeTimeRepository(
        running: pomodoro(phase: TimerPhase.longBreak, cyclesDone: 4),
      );
      final first = TimerCubit(repository, storageId: 'server#me');
      await first.refresh();
      await first.close();

      // A relaunch restores the phase as well as the clock: a bar that came
      // back saying "stopwatch" would be wrong for as long as the round trip
      // takes, on the one screen somebody is watching.
      final restored = TimerCubit(repository, storageId: 'server#me');
      expect(restored.state.timer!.mode, TimerMode.pomodoro);
      expect(restored.state.timer!.phase, TimerPhase.longBreak);
      expect(restored.state.timer!.cyclesDone, 4);
      expect(restored.state.timer!.pomodoro!.cycles, 4);
      await restored.close();
    });
  });
}

class _FakeTimeRepository implements TimeRepository {
  _FakeTimeRepository({this.running, this.startFailure});

  RunningTimer? running;
  String? startFailure;

  /// Every patch the cubit sent, so a test can state what it carried along as
  /// well as what it changed.
  final List<RunningTimer> patched = [];

  /// The timer id each stop named, or null when it named none.
  final List<String?> stoppedIds = [];

  /// Flipped mid-test rather than passed in: what these tests are about is what
  /// happens when a server that *was* answering stops.
  bool failing = false;

  @override
  Future<RunningTimer?> timer() async {
    if (failing) throw ApiFailure('offline');
    return running;
  }

  @override
  Future<RunningTimer> startTimer({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String> tags = const [],
    bool? billable,
    TimerMode mode = TimerMode.stopwatch,
    int? plannedMinutes,
    PomodoroConfig? pomodoro,
  }) async {
    if (startFailure != null) {
      throw ApiFailure(startFailure!, statusCode: 409);
    }
    started = (mode: mode, plannedMinutes: plannedMinutes, pomodoro: pomodoro);
    running = RunningTimer(
      id: 't1',
      startedAt: DateTime.now(),
      mode: mode,
      plannedMinutes: mode == TimerMode.countdown ? plannedMinutes : null,
      pomodoro: mode == TimerMode.pomodoro ? pomodoro : null,
      phase: mode == TimerMode.pomodoro ? TimerPhase.work : null,
    );
    return running!;
  }

  /// What the last start asked for, so a test can say what it meant rather than
  /// reading it back off the timer the fake invented.
  ({TimerMode mode, int? plannedMinutes, PomodoroConfig? pomodoro})? started;

  /// Timers the phase route has handed back, oldest first.
  final List<RunningTimer> phases = [];

  @override
  Future<RunningTimer> advancePhase({String? timerId}) async {
    final current = running!;
    final wasBreak = current.isBreak;
    final done = wasBreak ? current.cyclesDone : current.cyclesDone + 1;
    running = RunningTimer(
      // A new document per phase, as the server does — the old id belongs to
      // the entry the work interval became.
      id: 't${phases.length + 2}',
      startedAt: DateTime.now(),
      mode: TimerMode.pomodoro,
      pomodoro: current.pomodoro,
      phase: wasBreak ? TimerPhase.work : current.pomodoro!.phaseAfter(done),
      cyclesDone: done,
    );
    phases.add(running!);
    return running!;
  }

  @override
  Future<RunningTimer> patchTimer({
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String>? tags,
    bool? billable,
  }) async {
    final updated = RunningTimer(
      id: 't1',
      startedAt: running?.startedAt ?? DateTime.now(),
      projectId: projectId,
      issueId: issueId,
      description: description,
      activityType: activityType,
      tags: tags ?? const [],
      billable: billable ?? false,
    );
    patched.add(updated);
    running = updated;
    return updated;
  }

  @override
  Future<SavedTimeEntry> stopTimer({
    String? timerId,
    String? projectId,
    String? issueId,
    String? description,
    String? activityType,
    List<String>? tags,
    bool? billable,
  }) async {
    stoppedIds.add(timerId);
    running = null;
    return const SavedTimeEntry(
      entry: WorkItem(
        id: 't1',
        durationMinutes: 30,
        activityType: 'Development',
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// A hydrated-bloc store that lives for one test.
class _MemoryStorage implements Storage {
  final Map<String, dynamic> _values = {};

  @override
  dynamic read(String key) => _values[key];

  @override
  Future<void> write(String key, dynamic value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<void> close() async {}
}
