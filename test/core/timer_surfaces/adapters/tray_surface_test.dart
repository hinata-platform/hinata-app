import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/timer_surfaces/adapters/tray_gateway.dart';
import 'package:hinata/core/timer_surfaces/adapters/tray_surface.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

import 'fake_host.dart';

class _FakeTray implements TrayGateway {
  final List<String> log = [];
  bool? running;
  String title = '';
  String tooltip = '';
  List<TrayMenuEntry> menu = const [];
  void Function(String key)? select;
  bool fail = false;

  @override
  Future<void> setIcon({required bool running}) async {
    if (fail) throw StateError('no host');
    this.running = running;
    log.add('icon $running');
  }

  @override
  Future<void> setTitle(String title) async => this.title = title;

  @override
  Future<void> setTooltip(String text) async => tooltip = text;

  @override
  Future<void> setMenu(List<TrayMenuEntry> entries) async => menu = entries;

  @override
  Future<void> remove() async {
    running = null;
    log.add('remove');
  }

  @override
  void onSelected(void Function(String key) handler) => select = handler;
}

const _texts = TimerSurfaceTexts(
  appName: 'Hinata',
  countdownOver: '',
  workOver: '',
  breakOver: '',
  running: 'Timer running',
  onBreak: 'Break',
  stop: 'Stop',
  takeBreak: '',
  resume: '',
  start: 'Start timer',
  nextPhase: 'Next interval',
  openFocus: 'Open focus view',
  showWindow: 'Show window',
  quit: 'Quit Hinata',
  idle: 'No timer running',
  stopwatch: 'Stopwatch running',
  countdown: 'Countdown running',
  focusPhase: 'Pomodoro, focus',
  breakPhase: 'Pomodoro, break',
);

TimerSurfaceState _running({
  TimerMode mode = TimerMode.pomodoro,
  TimerPhase phase = TimerPhase.work,
  String? label,
}) => TimerSurfaceState(
  running: true,
  mode: mode,
  phase: phase,
  startedAt: DateTime.utc(2026, 10, 11, 9),
  label: label,
  runningSurface: true,
  texts: _texts,
);

const _idle = TimerSurfaceState(
  running: false,
  runningSurface: true,
  texts: _texts,
);

void main() {
  late _FakeTray tray;
  late FakeHost host;

  Future<TraySurface> surface(SurfacePlatform platform) async {
    tray = _FakeTray();
    host = FakeHost();
    final s = TraySurface(platform, gateway: tray);
    await s.init(host);
    return s;
  }

  test('work and a break look the same outside the open menu', () async {
    final s = await surface(SurfacePlatform.macos);
    await s.apply(_running());
    s.tick(const Duration(minutes: 12, seconds: 5));
    final work = (tray.running, tray.title, tray.log.length);

    final b = await surface(SurfacePlatform.macos);
    await b.apply(_running(phase: TimerPhase.shortBreak));
    b.tick(const Duration(minutes: 12, seconds: 5));
    expect((tray.running, tray.title, tray.log.length), work);
    // Only the open menu names the phase.
    expect(tray.menu.first, const TrayMenuEntry.label('Pomodoro, break'));
  });

  test('the Mac title ticks every second, only while a timer runs', () async {
    final s = await surface(SurfacePlatform.macos);
    await s.apply(_running(mode: TimerMode.stopwatch));
    s.tick(const Duration(seconds: 61));
    await pumpEventQueue();
    expect(tray.title, ' 1:01');
    await s.apply(_idle);
    expect(tray.title, '');
    s.tick(const Duration(seconds: 62));
    await pumpEventQueue();
    expect(tray.title, '');
  });

  test('the Windows tooltip changes once a minute', () async {
    final s = await surface(SurfacePlatform.windows);
    await s.apply(_running(mode: TimerMode.countdown));
    s.tick(const Duration(minutes: 3, seconds: 1));
    await pumpEventQueue();
    expect(tray.tooltip, 'Hinata · 0:03 · Timer running');
    tray.tooltip = 'untouched';
    s.tick(const Duration(minutes: 3, seconds: 40));
    await pumpEventQueue();
    expect(tray.tooltip, 'untouched');
  });

  test('the menu follows the timer and stays at six entries or fewer', () {
    final idle = trayMenu(_idle).where((e) => e.key != null);
    expect(idle.map((e) => e.key), ['toggle', 'focus', 'show', 'quit']);
    expect(
      trayMenu(_idle).firstWhere((e) => e.key == 'toggle').label,
      'Start timer',
    );

    final pomodoro = trayMenu(_running()).where((e) => e.key != null);
    expect(pomodoro.map((e) => e.key), [
      'toggle',
      'next',
      'focus',
      'show',
      'quit',
    ]);
    expect(pomodoro.length, lessThanOrEqualTo(6));

    final stopwatch = trayMenu(_running(mode: TimerMode.stopwatch));
    expect(stopwatch.any((e) => e.key == 'next'), isFalse);
  });

  test('a Pomodoro shows no clock outside the app, work or break', () async {
    for (final phase in [TimerPhase.work, TimerPhase.shortBreak]) {
      final s = await surface(SurfacePlatform.macos);
      await s.apply(_running(phase: phase));
      s.tick(const Duration(minutes: 4, seconds: 59));
      await pumpEventQueue();
      expect(tray.title, '', reason: '$phase');
    }
    final w = await surface(SurfacePlatform.windows);
    await w.apply(_running(phase: TimerPhase.shortBreak));
    w.tick(const Duration(minutes: 4));
    await pumpEventQueue();
    expect(tray.tooltip, 'Hinata · Timer running');
  });

  test('the menu shows the description the state carries', () {
    expect(
      trayMenu(_running()).where((e) => e.label == 'Quarterly report'),
      isEmpty,
    );
    expect(
      trayMenu(_running(label: 'Quarterly report')),
      contains(const TrayMenuEntry.label('Quarterly report')),
    );
  });

  test('Linux writes no tooltip, which its tray has no call for', () async {
    final s = await surface(SurfacePlatform.linux);
    await s.apply(_running());
    s.tick(const Duration(minutes: 2));
    await s.apply(_idle);
    await pumpEventQueue();
    expect(tray.tooltip, '');
    expect(tray.title, '');
  });

  test(
    'a timer started in the minute the last stopped gets its tooltip',
    () async {
      final s = await surface(SurfacePlatform.windows);
      await s.apply(_running());
      s.tick(const Duration(seconds: 10));
      await pumpEventQueue();
      await s.apply(_idle);
      expect(tray.tooltip, 'Hinata · No timer running');
      await s.apply(
        TimerSurfaceState(
          running: true,
          mode: TimerMode.stopwatch,
          startedAt: DateTime.utc(2026, 10, 11, 10),
          runningSurface: true,
          texts: _texts,
        ),
      );
      s.tick(const Duration(seconds: 3));
      await pumpEventQueue();
      expect(tray.tooltip, 'Hinata · 0:00 · Timer running');
    },
  );

  test('menu entries reach the app', () async {
    final s = await surface(SurfacePlatform.windows);
    await s.apply(_running());
    tray.select!('toggle');
    tray.select!('next');
    tray.select!('show');
    tray.select!('quit');
    tray.select!('focus');
    await pumpEventQueue();
    expect(host.calls, ['end', 'advance', 'show', 'quit', 'show', 'focus']);

    host.calls.clear();
    await s.apply(_idle);
    tray.select!('toggle');
    await pumpEventQueue();
    expect(host.calls, ['start']);
  });

  test('switched off it removes the icon and says it is gone', () async {
    final s = await surface(SurfacePlatform.macos);
    await s.apply(_running());
    expect(s.available.value, isTrue);
    await s.apply(const TimerSurfaceState(running: false));
    expect(tray.running, isNull);
    expect(s.available.value, isFalse);
  });

  test('a desktop without a tray host leaves it unavailable', () async {
    final s = await surface(SurfacePlatform.linux);
    tray.fail = true;
    await expectLater(s.apply(_running()), throwsStateError);
    expect(s.available.value, isFalse);
  });
}
