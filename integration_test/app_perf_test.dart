// Frame-timing benchmark for the main screens on a 120 Hz phone.
//
// Run with:
// flutter drive --profile --no-dds -d <device> \
//   --driver=test_driver/perf_driver.dart \
//   --target=integration_test/app_perf_test.dart \
//   --dart-define=SCREENSHOT_MODE=true
//
// Without a session on the device, pass the connection as for the popover
// benchmark (see support/sign_in.dart).
//
// Each scene scrolls or switches the way a person would and records every
// frame's build and raster time (FrameTiming, the same data DevTools shows).
// The summary counts frames against the 8.33 ms budget of a 120 Hz display
// and lands in build/integration_response_data.json.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hinata/main.dart' as app;

import 'support/sign_in.dart';

const _budgetUs = 8333;

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 8));
  }
}

Map<String, Object> _summary(List<FrameTiming> frames) {
  int pct(List<int> sorted, double p) =>
      sorted.isEmpty ? 0 : sorted[((sorted.length - 1) * p).round()];
  final build = [for (final f in frames) f.buildDuration.inMicroseconds]
    ..sort();
  final raster = [for (final f in frames) f.rasterDuration.inMicroseconds]
    ..sort();
  final total = [for (final f in frames) f.totalSpan.inMicroseconds];
  return {
    'frames': frames.length,
    'build_avg_us': build.isEmpty
        ? 0
        : build.reduce((a, b) => a + b) ~/ build.length,
    'build_p90_us': pct(build, 0.9),
    'build_p99_us': pct(build, 0.99),
    'raster_avg_us': raster.isEmpty
        ? 0
        : raster.reduce((a, b) => a + b) ~/ raster.length,
    'raster_p90_us': pct(raster, 0.9),
    'raster_p99_us': pct(raster, 0.99),
    'over_budget_build': build.where((b) => b > _budgetUs).length,
    'over_budget_raster': raster.where((r) => r > _budgetUs).length,
    'over_budget_total': total.where((t) => t > _budgetUs).length,
  };
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('main screens at 120 Hz', (tester) async {
    // No native permission prompts over the measured frames: with a
    // screenshot route set, the app does not start FCM, so iOS never asks
    // for notifications (run with --dart-define=SCREENSHOT_MODE=true too).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('screenshot_route', '/dashboard');
    // main takes the process arguments; a perf run launches with none.
    // Without Firebase, the push setup and cancelled requests throw
    // asynchronously, which would end the run.
    runZonedGuarded(
      () => app.main(const []),
      (error, stack) => debugPrint('PERF-TEST async error: $error'),
    );
    await ensureSignedIn(tester);
    final bell = find.byIcon(LucideIcons.bell);
    await _pumpFor(tester, const Duration(seconds: 3));

    final results = <String, Object>{};
    // Where the app is after a scene, so a stray tap that opened something
    // else shows up next to the numbers.
    void logScreen(String name) {
      final navigator = find.byType(Navigator);
      final route = tester.any(navigator)
          ? GoRouter.maybeOf(
              tester.element(navigator.first),
            )?.routeInformationProvider.value.uri
          : null;
      final texts = find
          .byType(Text)
          .hitTestable()
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .take(12)
          .toList();
      debugPrint('PERF-ROUTE $name $route $texts');
    }

    Future<void> measure(String name, Future<void> Function() scene) async {
      // A rest without frames before every scene. The scenes draw flat out,
      // and after about 70 s of that the phone throttles its GPU: whichever
      // scene came last then measured three to five times its own cost.
      await Future<void>.delayed(const Duration(seconds: 20));
      // One unmeasured pass, so first-use shader and image work stays out.
      await scene();
      final frames = <FrameTiming>[];
      void collect(List<FrameTiming> t) => frames.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(collect);
      await scene();
      await _pumpFor(tester, const Duration(milliseconds: 600));
      SchedulerBinding.instance.removeTimingsCallback(collect);
      results[name] = _summary(frames);
      debugPrint('PERF $name ${results[name]}');
      logScreen(name);
    }

    final popover = find.byWidgetPredicate(
      (w) => w.runtimeType.toString() == '_NotifPopoverCard',
    );
    late Offset bellAt;
    Future<void> openBell() async {
      bellAt = tester.getCenter(bell.first);
      await tester.tapAt(bellAt);
      await _pumpFor(tester, const Duration(milliseconds: 1000));
      expect(tester.any(popover), isTrue, reason: 'popover did not open');
    }

    // Closes through the popover's barrier, low on the left where the
    // popover never reaches. openBell has checked it is open, so the tap
    // cannot land on the page.
    Future<void> closeBell() async {
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.tapAt(Offset(16, size.height * 0.72));
      await _pumpFor(tester, const Duration(milliseconds: 1200));
      expect(tester.any(popover), isFalse, reason: 'popover did not close');
    }

    Future<void> openTab(IconData icon) async {
      await tester.tap(find.byIcon(icon).last, warnIfMissed: false);
      await _pumpFor(tester, const Duration(milliseconds: 1500));
    }

    Future<void> scroll({bool horizontal = false}) async {
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final centre = Offset(size.width / 2, size.height / 2);
      for (var i = 0; i < 3; i++) {
        for (final dir in [-1.0, 1.0]) {
          final delta = horizontal
              ? Offset(dir * size.width * 0.6, 0)
              : Offset(0, dir * size.height * 0.45);
          await tester.flingFrom(centre, delta, 2500);
          await _pumpFor(tester, const Duration(milliseconds: 900));
        }
      }
    }

    // "More" is a modal sheet over the shell, not a page: open it and close
    // it through its barrier at the top of the screen.
    Future<void> moreSheet() async {
      for (var i = 0; i < 3; i++) {
        await tester.tap(
          find.byIcon(LucideIcons.layoutGrid).last,
          warnIfMissed: false,
        );
        await _pumpFor(tester, const Duration(milliseconds: 1200));
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        await tester.tapAt(Offset(size.width / 2, 80));
        await _pumpFor(tester, const Duration(milliseconds: 900));
      }
    }

    await openTab(LucideIcons.layoutDashboard);
    await measure('bell_popover', () async {
      for (var i = 0; i < 3; i++) {
        await openBell();
        await closeBell();
      }
    });

    await measure('dashboard_scroll', scroll);

    await openTab(LucideIcons.circleCheckBig);
    await measure('issues_scroll', scroll);

    await openTab(LucideIcons.squareKanban);
    await measure('board_scroll', () => scroll(horizontal: true));

    await measure('more_sheet', moreSheet);

    await measure('tab_switch', () async {
      for (final icon in [
        LucideIcons.layoutDashboard,
        LucideIcons.circleCheckBig,
        LucideIcons.squareKanban,
      ]) {
        await tester.tap(find.byIcon(icon).last, warnIfMissed: false);
        await _pumpFor(tester, const Duration(milliseconds: 900));
      }
    });

    binding.reportData = {'app_perf': results};
  }, timeout: const Timeout(Duration(minutes: 8)));
}
