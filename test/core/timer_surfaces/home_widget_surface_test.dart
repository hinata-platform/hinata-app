import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/adapters/home_widget_surface.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

/// The widgets' shared store (HIN-102): one record, no ids, the description
/// only with details on the lock screen, and gone on clear.
void main() {
  final start = DateTime.now().toUtc().subtract(const Duration(minutes: 5));

  RunningTimer timer({
    TimerMode mode = TimerMode.stopwatch,
    int? planned,
    TimerPhase? phase,
  }) => RunningTimer(
    id: 'timer-1',
    startedAt: start,
    projectId: 'project-1',
    issueId: 'issue-1',
    description: 'Quarterly report for the client',
    tags: const ['Review'],
    billable: true,
    mode: mode,
    plannedMinutes: planned,
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
    idle: 'No timer running',
  );

  TimerSurfaceState state(
    RunningTimer? t, {
    TimerSurfacePrefs prefs = TimerSurfacePrefs.suggested,
  }) => deriveTimerSurfaceState(t, prefs, gated: false, texts: texts);

  Map<String, dynamic> read(String? record) =>
      jsonDecode(record!) as Map<String, dynamic>;

  late FakeWidgetStore store;
  late HomeWidgetSurface surface;

  setUp(() {
    store = FakeWidgetStore();
    surface = HomeWidgetSurface(SurfacePlatform.ios, store: store);
  });

  test('a running stopwatch: start, direction, expiry, words', () async {
    await surface.apply(state(timer()));
    final record = read(store.records.single);

    expect(record['startedAt'], start.millisecondsSinceEpoch);
    expect(record.containsKey('endsAt'), isFalse);
    expect(record['countsDown'], isFalse);
    expect(
      record['validUntil'],
      start.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
    expect(record['title'], 'Timer running');
    expect(record['idle'], 'No timer running');
  });

  test('a countdown counts down and expires an hour after its end', () async {
    await surface.apply(state(timer(mode: TimerMode.countdown, planned: 25)));
    final record = read(store.records.single);
    final end = start.add(const Duration(minutes: 25));

    expect(record['endsAt'], end.millisecondsSinceEpoch);
    expect(record['countsDown'], isTrue);
    expect(record['over'], 'Countdown over');
    expect(
      record['validUntil'],
      end.add(const Duration(hours: 1)).millisecondsSinceEpoch,
    );
  });

  test('a Pomodoro break is a break, without naming the phase', () async {
    await surface.apply(
      state(timer(mode: TimerMode.pomodoro, phase: TimerPhase.longBreak)),
    );

    expect(read(store.records.single)['phaseKind'], 'break');
  });

  test('the store carries no ids', () async {
    await surface.apply(
      state(
        timer(),
        prefs: TimerSurfacePrefs.suggested.copyWith(lockScreenDetails: true),
      ),
    );
    final record = store.records.single!;

    expect(record, isNot(contains('timer-1')));
    expect(record, isNot(contains('project-1')));
    expect(record, isNot(contains('issue-1')));
    expect(record, isNot(contains('Review')));
    expect(read(record).keys, isNot(contains('id')));
  });

  test('the description only with details on the lock screen', () async {
    await surface.apply(
      state(
        timer(),
        prefs: TimerSurfacePrefs.suggested.copyWith(surfaceDetails: true),
      ),
    );
    expect(read(store.records.last).containsKey('label'), isFalse);

    await surface.apply(
      state(
        timer(),
        prefs: TimerSurfacePrefs.suggested.copyWith(lockScreenDetails: true),
      ),
    );
    expect(
      read(store.records.last)['label'],
      'Quarterly report for the client',
    );
  });

  test('with the running timer switched off the widget is idle', () async {
    await surface.apply(
      state(
        timer(),
        prefs: TimerSurfacePrefs.suggested.copyWith(runningSurface: false),
      ),
    );

    expect(read(store.records.single).keys, ['idle']);
  });

  test('a stop leaves an idle record in the last language', () async {
    await surface.apply(state(timer()));
    await surface.apply(TimerSurfaceState.idle);

    expect(read(store.records.last), {'idle': 'No timer running'});
  });

  test('an unchanged record is not written again', () async {
    await surface.apply(state(timer()));
    await surface.apply(state(timer()));

    expect(store.records, hasLength(1));
  });

  test('clear removes the record, also after nothing changed', () async {
    await surface.apply(state(timer()));
    await surface.clear();
    await surface.clear();

    expect(store.records, [isNotNull, null, null]);
  });
}

class FakeWidgetStore extends TimerWidgetStore {
  final List<String?> records = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> write(String? record) async => records.add(record);
}
