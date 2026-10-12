import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/adapters/live_activity_surface.dart';
import 'package:hinata/core/timer_surfaces/live_activity_push_registry.dart';
import 'package:hinata/core/timer_surfaces/timer_surface.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

/// The Live Activity (HIN-102) against a fake channel: one activity per timer,
/// started only for what the server confirmed, ended on every way out.
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
    bool confirmed = true,
  }) => deriveTimerSurfaceState(
    t,
    prefs,
    gated: false,
    texts: texts,
    confirmed: confirmed,
  );

  late FakeLiveActivityChannel channel;
  late LiveActivitySurface surface;

  setUp(() {
    channel = FakeLiveActivityChannel();
    surface = LiveActivitySurface(channel: channel);
  });

  test('a running timer starts one activity, a change updates it', () async {
    await surface.apply(state(timer()));
    await surface.apply(
      state(timer(mode: TimerMode.pomodoro, phase: TimerPhase.shortBreak)),
    );

    expect(channel.calls, ['start', 'update']);
    expect(channel.last['title'], 'Break');
  });

  test('a timer read back from the cache puts nothing up until the server '
      'confirms it', () async {
    await surface.apply(state(timer(), confirmed: false));
    expect(channel.calls, isEmpty);

    await surface.apply(state(timer()));
    expect(channel.calls, ['start']);
  });

  test('stopping ends the activity at once', () async {
    await surface.apply(state(timer()));
    await surface.apply(state(null));

    expect(channel.calls, ['start', 'end:ref-1']);
  });

  test(
    'without an activity of this run, a stop still ends any left over',
    () async {
      await surface.apply(state(null));

      expect(channel.calls, ['endAll']);
    },
  );

  test('switching the running timer off ends the activity', () async {
    await surface.apply(state(timer()));
    await surface.apply(
      state(
        timer(),
        prefs: TimerSurfacePrefs.suggested.copyWith(runningSurface: false),
      ),
    );

    expect(channel.calls.last, 'end:ref-1');
  });

  test('clearing ends every activity, also of an earlier run', () async {
    await surface.apply(state(timer()));
    await surface.clear();
    await surface.apply(state(timer()));

    expect(channel.calls, ['start', 'endAll', 'start']);
  });

  test('a system that refuses leaves nothing to update, the next state asks '
      'again', () async {
    channel.refuse = true;
    await surface.apply(state(timer()));
    channel.refuse = false;
    await surface.apply(state(timer(mode: TimerMode.countdown, planned: 25)));

    expect(channel.calls, ['start', 'start']);
  });

  test(
    'an activity swiped away stays away for this timer, not the next',
    () async {
      await surface.apply(state(timer()));
      channel.alive = false;
      await surface.apply(state(timer(mode: TimerMode.countdown, planned: 25)));
      await surface.apply(state(timer(mode: TimerMode.countdown, planned: 30)));
      expect(channel.calls, ['start', 'update']);

      final next = RunningTimer(
        id: 'timer-2',
        startedAt: start.add(const Duration(minutes: 1)),
      );
      await surface.apply(state(next));
      expect(channel.calls, ['start', 'update', 'start']);
    },
  );

  group('content', () {
    test('a stopwatch counts up and goes away a day after its start', () {
      final content = liveActivityContent(state(timer()))!;

      expect(content['mode'], 'stopwatch');
      expect(content['endsAt'], isNull);
      expect(content['staleTitle'], isNull);
      expect(
        content['dismissAt'],
        start.add(const Duration(hours: 24)).millisecondsSinceEpoch,
      );
    });

    test('a countdown turns stale at its end and goes an hour later', () {
      final content = liveActivityContent(
        state(timer(mode: TimerMode.countdown, planned: 25)),
      )!;
      final end = start.add(const Duration(minutes: 25));

      expect(content['endsAt'], end.millisecondsSinceEpoch);
      expect(content['staleTitle'], 'Countdown over');
      expect(
        content['dismissAt'],
        end.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
    });

    test('a Pomodoro break says so and turns stale with "break over"', () {
      final content = liveActivityContent(
        state(timer(mode: TimerMode.pomodoro, phase: TimerPhase.shortBreak)),
      )!;

      expect(content['phase'], 'shortBreak');
      expect(content['title'], 'Break');
      expect(content['staleTitle'], 'Break over');
    });

    test('the description only with details on the lock screen', () {
      expect(liveActivityContent(state(timer()))!['label'], isNull);
      expect(
        liveActivityContent(
          state(
            timer(),
            prefs: TimerSurfacePrefs.suggested.copyWith(surfaceDetails: true),
          ),
        )!['label'],
        isNull,
      );
      expect(
        liveActivityContent(
          state(
            timer(),
            prefs: TimerSurfacePrefs.suggested.copyWith(
              lockScreenDetails: true,
            ),
          ),
        )!['label'],
        'Quarterly report for the client',
      );
    });

    test('a long description is cut to fit the 4 KB of an activity', () {
      final long = 'x' * 5000;
      expect(clipLockScreenLabel(long)!.runes.length, lockScreenLabelMax);
      expect(clipLockScreenLabel('short'), 'short');
    });

    test('no ids: nothing names the timer, project, issue or tags', () {
      final printed = liveActivityContent(
        state(
          timer(),
          prefs: TimerSurfacePrefs.suggested.copyWith(lockScreenDetails: true),
        ),
      ).toString();

      expect(printed, isNot(contains('timer-1')));
      expect(printed, isNot(contains('project-1')));
      expect(printed, isNot(contains('issue-1')));
      expect(printed, isNot(contains('Review')));
    });

    test('past its dismissal there is nothing to show', () {
      final old = deriveTimerSurfaceState(
        timer(mode: TimerMode.countdown, planned: 1),
        TimerSurfacePrefs.suggested,
        gated: false,
      );
      expect(
        liveActivityContent(old, now: start.add(const Duration(minutes: 62))),
        isNull,
      );
    });
  });

  group('background updates (HIN-103)', () {
    late FakeRegistry registry;
    late LiveActivitySurface pushing;
    const background = TimerSurfacePrefs(
      consented: true,
      introSeen: true,
      runningSurface: true,
      backgroundLiveActivity: true,
    );

    setUp(() async {
      registry = FakeRegistry();
      pushing = LiveActivitySurface(channel: channel, registry: registry);
      await pushing.init(NoHost());
    });

    LiveActivityPushToken token(String value, {String ref = 'ref-1'}) =>
        LiveActivityPushToken(ref: ref, token: value, key: 'a2V5');

    test(
      'switched off, an activity is local and nothing is registered',
      () async {
        await pushing.apply(state(timer()));
        channel.tokens?.call(token('aa11'));
        await pumpEventQueue();

        expect(channel.push, isFalse);
        expect(registry.calls, isEmpty);
      },
    );

    test('switched on, the activity asks for pushes and its token is '
        'registered with its key', () async {
      await pushing.apply(state(timer(), prefs: background));
      channel.tokens!(token('aa11'));
      await pumpEventQueue();

      expect(channel.push, isTrue);
      expect(registry.calls, ['register:aa11']);
      expect(registry.registered.single.key, 'a2V5');
    });

    test('a rotated token replaces the old one', () async {
      await pushing.apply(state(timer(), prefs: background));
      channel.tokens!(token('aa11'));
      await pumpEventQueue();
      channel.tokens!(token('bb22'));
      await pumpEventQueue();

      expect(registry.calls, [
        'register:aa11',
        'unregister:aa11',
        'register:bb22',
      ]);
    });

    test('a token of another activity is not registered', () async {
      await pushing.apply(state(timer(), prefs: background));
      channel.tokens!(token('cc33', ref: 'ref-other'));
      await pumpEventQueue();

      expect(registry.calls, isEmpty);
    });

    test('switching off takes the token back at once', () async {
      await pushing.apply(state(timer(), prefs: background));
      channel.tokens!(token('aa11'));
      await pumpEventQueue();

      await pushing.apply(state(timer()));

      expect(registry.calls, ['register:aa11', 'unregister:aa11']);
    });

    test('stopping and signing out take the token back', () async {
      await pushing.apply(state(timer(), prefs: background));
      channel.tokens!(token('aa11'));
      await pumpEventQueue();
      await pushing.apply(state(null));
      expect(registry.calls.last, 'unregister:aa11');

      await pushing.apply(state(timer(), prefs: background));
      channel.tokens!(token('dd44', ref: 'ref-2'));
      await pumpEventQueue();
      await pushing.clear();
      expect(registry.calls.last, 'unregister:dd44');
    });

    test('the content carries the words for a sealed state, and no id or '
        'description without the lock-screen switch', () async {
      await pushing.apply(state(timer(), prefs: background));

      expect(channel.last['words'], {
        'running': 'Timer running',
        'onBreak': 'Break',
        'countdownOver': 'Countdown over',
        'workOver': 'Interval over',
        'breakOver': 'Break over',
      });
      expect(channel.last.toString(), isNot(contains('timer-1')));
      expect(channel.last.toString(), isNot(contains('Quarterly')));
      expect(channel.last.toString(), isNot(contains('project-1')));
    });
  });
}

class FakeLiveActivityChannel extends LiveActivityChannel {
  FakeLiveActivityChannel();

  final List<String> calls = [];
  Map<String, Object?> last = {};
  bool refuse = false;
  int _next = 0;

  @override
  Future<bool> areActivitiesEnabled() async => true;

  /// Whether the last start asked for server updates (HIN-103).
  bool? push;

  void Function(LiveActivityPushToken token)? tokens;

  @override
  Future<String?> start(
    Map<String, Object?> content, {
    bool push = false,
  }) async {
    calls.add('start');
    last = content;
    this.push = push;
    if (refuse) return null;
    return 'ref-${++_next}';
  }

  @override
  void onPushToken(void Function(LiveActivityPushToken token) handler) =>
      tokens = handler;

  /// Whether the activity is still there; false once swiped away.
  bool alive = true;

  @override
  Future<bool> update(String ref, Map<String, Object?> content) async {
    calls.add('update');
    last = content;
    return alive;
  }

  @override
  Future<void> end(String ref) async => calls.add('end:$ref');

  @override
  Future<void> endAll() async => calls.add('endAll');
}

class FakeRegistry implements LiveActivityPushRegistry {
  final List<String> calls = [];
  final List<LiveActivityPushToken> registered = [];

  @override
  Future<bool> register(LiveActivityPushToken token) async {
    calls.add('register:${token.token}');
    registered.add(token);
    return true;
  }

  @override
  Future<void> unregister(String token) async => calls.add('unregister:$token');
}

class NoHost implements TimerSurfaceHost {
  @override
  bool get isForeground => true;
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
