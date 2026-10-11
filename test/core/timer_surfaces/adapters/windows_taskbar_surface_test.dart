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

  TimerSurfaceState countdown(TimerPhase phase) => TimerSurfaceState(
    running: true,
    mode: TimerMode.pomodoro,
    phase: phase,
    startedAt: start,
    endsAt: start.add(const Duration(minutes: 25)),
    runningSurface: true,
  );

  test('the progress is the share of the interval behind', () {
    final s = surface();
    now = start.add(const Duration(minutes: 5));
    expect(s.progressOf(countdown(TimerPhase.work)), 200);
    now = start.add(const Duration(hours: 1));
    expect(s.progressOf(countdown(TimerPhase.work)), 1000);
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

  test('work and a break draw the same overlay', () async {
    final s = surface();
    await s.init(FakeHost());
    await s.apply(countdown(TimerPhase.work));
    final work = calls.where((c) => c.method == 'setOverlay').single.arguments;
    calls.clear();
    await s.apply(countdown(TimerPhase.shortBreak));
    final rest = calls.where((c) => c.method == 'setOverlay').single.arguments;
    expect(rest, work);
  });

  test('switched off clears the button', () async {
    final s = surface();
    await s.init(FakeHost());
    await s.apply(countdown(TimerPhase.work));
    calls.clear();
    await s.apply(const TimerSurfaceState(running: false));
    expect(calls.map((c) => c.method), ['clear']);
  });

  test('the thumbnail buttons reach the app', () async {
    final host = FakeHost();
    final s = surface();
    await s.init(host);
    await s.apply(countdown(TimerPhase.work));
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
