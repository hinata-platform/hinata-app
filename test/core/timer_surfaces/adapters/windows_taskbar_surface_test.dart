import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/adapters/windows_taskbar_surface.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

import 'fake_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hinata/taskbar');
  final calls = <MethodCall>[];
  final start = DateTime.utc(2026, 10, 11, 9);
  var now = start;

  setUp(() {
    calls.clear();
    now = start;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  WindowsTaskbarSurface surface() =>
      WindowsTaskbarSurface(channel: channel, now: () => now);

  TimerSurfaceState countdown() => TimerSurfaceState(
    running: true,
    mode: TimerMode.countdown,
    startedAt: start,
    endsAt: start.add(const Duration(minutes: 25)),
    runningSurface: true,
  );

  test('the progress is the share of the interval behind', () {
    final s = surface();
    now = start.add(const Duration(minutes: 5));
    expect(s.progressOf(countdown()), 200);
    now = start.add(const Duration(hours: 1));
    expect(s.progressOf(countdown()), 1000);
    expect(
      s.progressOf(
        TimerSurfaceState(
          running: true,
          startedAt: start,
          runningSurface: true,
        ),
      ),
      isNull,
    );
  });

  TimerSurfaceState pomodoro(TimerPhase phase) => TimerSurfaceState(
    running: true,
    mode: TimerMode.pomodoro,
    phase: phase,
    startedAt: start,
    endsAt: start.add(const Duration(minutes: 5)),
    runningSurface: true,
  );

  test('work and a break draw the same overlay, tooltip and no bar', () async {
    final s = surface();
    await s.init(FakeHost());
    await s.apply(pomodoro(TimerPhase.work));
    final work = [for (final c in calls) '${c.method} ${c.arguments}'];
    calls.clear();
    final b = surface();
    await b.init(FakeHost());
    await b.apply(pomodoro(TimerPhase.shortBreak));
    b.tick(const Duration(minutes: 3));
    expect([for (final c in calls) '${c.method} ${c.arguments}'], work);
    expect(s.progressOf(pomodoro(TimerPhase.shortBreak)), isNull);
  });

  test('only a change reaches the runner', () async {
    final s = surface();
    await s.init(FakeHost());
    await s.apply(countdown());
    calls.clear();
    await s.apply(countdown());
    s.tick(const Duration(minutes: 1));
    await pumpEventQueue();
    expect(calls.map((c) => c.method), ['setTooltip']);
  });

  test('a click on buttons that are not shown starts nothing', () async {
    final host = FakeHost();
    final s = surface();
    await s.init(host);
    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'hinata/taskbar',
          codec.encodeMethodCall(const MethodCall('thumbClicked', 'toggle')),
          (_) {},
        );
    expect(host.calls, isEmpty);
  });

  test('switched off clears the button', () async {
    final s = surface();
    await s.init(FakeHost());
    await s.apply(countdown());
    calls.clear();
    await s.apply(const TimerSurfaceState(running: false));
    expect(calls.map((c) => c.method), ['clear']);
  });

  test('the thumbnail buttons reach the app', () async {
    final host = FakeHost();
    final s = surface();
    await s.init(host);
    await s.apply(countdown());
    const codec = StandardMethodCodec();
    for (final id in ['toggle', 'focus']) {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'hinata/taskbar',
            codec.encodeMethodCall(MethodCall('thumbClicked', id)),
            (_) {},
          );
    }
    expect(host.calls, ['end', 'show', 'focus']);
  });
}
