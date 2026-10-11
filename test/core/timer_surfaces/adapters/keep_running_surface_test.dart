import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/timer_surfaces/adapters/keep_running_surface.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

import 'fake_host.dart';

class _FakeWindow implements WindowGateway {
  final List<String> log = [];
  void Function()? requestClose;

  @override
  Future<void> setPreventClose(bool prevent) async =>
      log.add('prevent $prevent');

  @override
  Future<void> hide() async => log.add('hide');

  @override
  Future<void> show() async => log.add('show');

  @override
  Future<void> close() async => log.add('close');

  @override
  void onCloseRequested(void Function() handler) => requestClose = handler;
}

void main() {
  late _FakeWindow window;
  late ValueNotifier<bool> tray;
  late KeepRunningSurface surface;

  setUp(() async {
    window = _FakeWindow();
    tray = ValueNotifier(true);
    surface = KeepRunningSurface(
      SurfacePlatform.windows,
      trayAvailable: tray,
      window: window,
    );
    await surface.init(FakeHost());
  });

  const keep = TimerSurfaceState(running: true, keepInTray: true);

  test('never touches the window until the switch is on', () async {
    await surface.apply(const TimerSurfaceState(running: true));
    await surface.apply(TimerSurfaceState.idle);
    expect(window.log, isEmpty);
  });

  test(
    'a close hides the window while a timer runs into a visible tray',
    () async {
      await surface.apply(keep);
      expect(window.log, ['prevent true']);
      window.requestClose!();
      await pumpEventQueue();
      expect(window.log.last, 'hide');
    },
  );

  test('without a timer the window closes as always', () async {
    await surface.apply(keep);
    await surface.apply(
      const TimerSurfaceState(running: false, keepInTray: true),
    );
    expect(window.log, ['prevent true', 'prevent false']);
  });

  test('no tray, no hiding', () async {
    await surface.apply(keep);
    tray.value = false;
    await pumpEventQueue();
    expect(window.log.last, 'prevent false');
    // A close that raced the tray going away still closes.
    window.requestClose!();
    await pumpEventQueue();
    expect(window.log.last, 'close');
  });
}
