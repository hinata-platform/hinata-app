// Frame-timing benchmark for the notification bell popover.
//
// Run with:
// flutter drive --profile --no-dds -d emulator-5554 \
//   --driver=test_driver/perf_driver.dart \
//   --target=integration_test/notification_popover_perf_test.dart

// A fresh install boots into the connect screen, so the test walks the full
// flow (server URL → login → onboarding) before measuring. Every step is
// skipped automatically when the app restores a persisted session. Frame
// timings are recorded with integration_test's watchPerformance — the same
// FrameTiming data DevTools shows.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:hinata/main.dart' as app;

import 'support/sign_in.dart';

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final steps = duration.inMilliseconds ~/ 100;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('notification popover open/close frame timings', (tester) async {
    // main now takes the process arguments (a Linux deep link arrives that
    // way); a perf run launches with none.
    await app.main(const []);
    await ensureSignedIn(tester);
    final bell = find.byIcon(LucideIcons.bell);

    // Warm-up round (shader/pipeline compilation must not skew the measure).
    await tester.tap(bell.first, warnIfMissed: false);
    await _pumpFor(tester, const Duration(milliseconds: 1200));
    await tester.tapAt(const Offset(50, 500));
    await _pumpFor(tester, const Duration(milliseconds: 1000));

    await binding.watchPerformance(() async {
      for (var i = 0; i < 6; i++) {
        await tester.tap(bell.first, warnIfMissed: false);
        await _pumpFor(tester, const Duration(milliseconds: 1200));
        await tester.tapAt(const Offset(50, 500));
        await _pumpFor(tester, const Duration(milliseconds: 1000));
      }
    }, reportKey: 'popover_perf');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
