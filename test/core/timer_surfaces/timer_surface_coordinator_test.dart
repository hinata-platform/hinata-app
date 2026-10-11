import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_coordinator.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';

import '../../support/timer_surface_fakes.dart';

void main() {
  const running = TimerSurfaceState(running: true, phaseEndNotification: true);

  test('applies a state only when it changed', () async {
    final surface = RecordingSurface('a');
    final coordinator = TimerSurfaceCoordinator([surface]);

    await coordinator.apply(running);
    await coordinator.apply(running);

    expect(surface.applied, hasLength(1));
  });

  test('invalidate draws the same state again', () async {
    final surface = RecordingSurface('a');
    final coordinator = TimerSurfaceCoordinator([surface]);

    await coordinator.apply(running);
    coordinator.invalidate();
    await coordinator.apply(running);

    expect(surface.applied, hasLength(2));
  });

  test('a surface that fails twice is left alone, the others go on', () async {
    final broken = RecordingSurface('broken', failing: true);
    final fine = RecordingSurface('fine');
    final coordinator = TimerSurfaceCoordinator([broken, fine]);

    await coordinator.apply(running);
    coordinator.tick(const Duration(seconds: 3));
    await coordinator.apply(const TimerSurfaceState(running: true));

    expect(coordinator.isQuarantined(broken), isTrue);
    expect(coordinator.isQuarantined(fine), isFalse);
    expect(fine.applied, hasLength(2));
    expect(fine.ticks, [const Duration(seconds: 3)]);
  });

  test('clearing reaches every surface, also a quarantined one', () async {
    final broken = RecordingSurface('broken', failing: true);
    final coordinator = TimerSurfaceCoordinator([broken]);
    await coordinator.apply(running);
    await coordinator.apply(const TimerSurfaceState(running: true));

    await coordinator.clearAll();

    expect(broken.clears, 1);
  });

  test('the end of a phase says whether the app is in front', () async {
    final surface = RecordingSurface('a');
    final coordinator = TimerSurfaceCoordinator([surface]);

    await coordinator.phaseEnded(running, foreground: true);
    await coordinator.phaseEnded(running, foreground: false);

    expect(surface.ended, [true, false]);
  });
}
