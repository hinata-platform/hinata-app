// Frame-timing benchmark for the shift planning surfaces (HIN-27).
//
// Run on the desktop in profile mode:
// flutter drive --profile --no-dds -d macos \
//   --driver=test_driver/perf_driver.dart \
//   --target=integration_test/shifts_perf_test.dart \
//   --dart-define=SCREENSHOT_MODE=true \
//   --dart-define=HINATA_SERVER_URL=<server> \
//   --dart-define=HINATA_USER=<user> --dart-define=HINATA_PASSWORD=<password>
//
// The server needs shift planning on and events to show; the demo seed of a
// server started with HINATA_SHIFTS_ENABLED=true and HINATA_DEMO_SEED=true has
// a trade fair over five days and a club's summer party.
//
// Scrolling goes through mouse-wheel events, the way a desktop is scrolled.
// Every frame's build and raster time is recorded (FrameTiming, the data
// DevTools shows) and counted against 16.7 ms (60 Hz) and 8.3 ms (120 Hz);
// the summary lands in build/integration_response_data.json.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hinata/core/router/app_router.dart' show rootNavigatorKey;
import 'package:hinata/main.dart' as app;

import 'support/sign_in.dart';

const _server = String.fromEnvironment('HINATA_SERVER_URL');
const _user = String.fromEnvironment('HINATA_USER');
const _password = String.fromEnvironment('HINATA_PASSWORD');
const _only = String.fromEnvironment('PERF_ONLY');
const _budget60Us = 16667;
const _budget120Us = 8333;

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
  int avg(List<int> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) ~/ v.length;
  return {
    'frames': frames.length,
    'build_avg_us': avg(build),
    'build_p90_us': pct(build, 0.9),
    'build_p99_us': pct(build, 0.99),
    'raster_avg_us': avg(raster),
    'raster_p90_us': pct(raster, 0.9),
    'raster_p99_us': pct(raster, 0.99),
    'over_60hz_total': total.where((t) => t > _budget60Us).length,
    'over_120hz_build': build.where((b) => b > _budget120Us).length,
    'over_120hz_raster': raster.where((r) => r > _budget120Us).length,
  };
}

/// The trade fair's event id, read over the API, so the scenes open the same
/// event every run.
Future<String?> _fairId() async {
  final client = HttpClient();
  try {
    Future<dynamic> call(
      String method,
      String path, {
      Object? body,
      String? token,
    }) async {
      final request = await client.openUrl(method, Uri.parse('$_server$path'));
      request.headers.contentType = ContentType.json;
      if (token != null) request.headers.set('Authorization', 'Bearer $token');
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      return jsonDecode(await response.transform(utf8.decoder).join());
    }

    final login = await call(
      'POST',
      '/api/v1/auth/login',
      body: {'identifier': _user, 'password': _password},
    );
    final token = (login as Map)['accessToken'] as String;
    final now = DateTime.now().toUtc();
    final events = await call(
      'GET',
      '/api/v1/shifts/events?from=${now.subtract(const Duration(days: 1)).toIso8601String()}'
          '&to=${now.add(const Duration(days: 60)).toIso8601String()}&size=50',
      token: token,
    );
    for (final e in (events as Map)['content'] as List) {
      if ((e['title'] as String).startsWith('Trade fair')) {
        return e['id'] as String;
      }
    }
    return null;
  } finally {
    client.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('shift surfaces', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('screenshot_route', '/shifts');
    await prefs.setString('server_url', _server);
    await prefs.setString(
      'servers.v1',
      jsonEncode([
        {'url': _server},
      ]),
    );
    await prefs.setBool('onboarding_done', true);
    await prefs.setString('locale', 'de');
    String? fair;
    await tester.runAsync(() async => fair = await _fairId());
    expect(fair, isNotNull, reason: 'the server has no trade fair event');

    runZonedGuarded(
      () => app.main(const []),
      (error, stack) => debugPrint('PERF-TEST async error: $error'),
    );
    await ensureSignedIn(tester);
    await _pumpFor(tester, const Duration(seconds: 3));

    final results = <String, Object>{};

    Future<void> go(String route) async {
      rootNavigatorKey.currentState?.popUntil(
        (r) => r.settings is Page || r.isFirst,
      );
      GoRouter.of(rootNavigatorKey.currentContext!).go(route);
      await _pumpFor(tester, const Duration(seconds: 3));
    }

    Future<void> measure(String name, Future<void> Function() scene) async {
      // PERF_ONLY=a,b measures just those scenes (an A/B run of one change).
      if (_only.isNotEmpty && !_only.split(',').contains(name)) return;
      await Future<void>.delayed(const Duration(seconds: 5));
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
    }

    /// Wheel scrolling down and back up over the middle of [at], about the
    /// speed of a trackpad flick: 60 px per event, one event per frame.
    Future<void> wheel({
      Offset? at,
      int steps = 40,
      bool horizontal = false,
    }) async {
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      final position = at ?? Offset(size.width * 0.62, size.height * 0.55);
      for (final dir in [1.0, -1.0, 1.0, -1.0]) {
        for (var i = 0; i < steps; i++) {
          tester.binding.handlePointerEvent(
            PointerScrollEvent(
              position: position,
              scrollDelta: horizontal
                  ? Offset(dir * 60, 0)
                  : Offset(0, dir * 60),
            ),
          );
          await tester.pump(const Duration(milliseconds: 8));
        }
        await _pumpFor(tester, const Duration(milliseconds: 400));
      }
    }

    final view = tester.view;
    debugPrint(
      'PERF-VIEW ${view.physicalSize} dpr ${view.devicePixelRatio} '
      '${view.display.refreshRate} Hz',
    );

    // The same wheel over two pages outside the module, as the yardstick:
    // what the shell and its glass cost on this machine and window.
    await go('/issues');
    await measure('baseline_issues_scroll', wheel);
    await go('/dashboard');
    await measure('baseline_dashboard_scroll', wheel);

    await go('/shifts');
    await measure('mine_scroll', wheel);

    await go('/shifts/events');
    await measure('events_scroll', wheel);

    await go('/shifts/events/$fair');
    await measure('event_detail_scroll', wheel);

    await measure('shift_popover', () async {
      for (var i = 0; i < 3; i++) {
        final row = find.text('Stand duty, afternoon');
        await tester.tap(row.first, warnIfMissed: false);
        await _pumpFor(tester, const Duration(milliseconds: 1200));
        await rootNavigatorKey.currentState?.maybePop();
        await _pumpFor(tester, const Duration(milliseconds: 900));
      }
    });

    await go('/shifts/calendar?span=week&date=2026-10-26');
    await measure('calendar_week_scroll', () => wheel(steps: 25));

    await measure('calendar_week_paging', () async {
      for (final route in [
        '/shifts/calendar?span=week&date=2026-11-02',
        '/shifts/calendar?span=week&date=2026-10-26',
        '/shifts/calendar?span=week&date=2026-11-02',
        '/shifts/calendar?span=week&date=2026-10-26',
      ]) {
        GoRouter.of(rootNavigatorKey.currentContext!).go(route);
        await _pumpFor(tester, const Duration(milliseconds: 900));
      }
    });

    await go('/shifts/calendar?span=month&date=2026-10-26');
    await measure('calendar_month_scroll', wheel);

    await measure('view_switch', () async {
      for (final route in [
        '/shifts',
        '/shifts/calendar',
        '/shifts/events',
        '/shifts',
      ]) {
        GoRouter.of(rootNavigatorKey.currentContext!).go(route);
        await _pumpFor(tester, const Duration(milliseconds: 1500));
      }
    });

    binding.reportData = {'shifts': results};
  }, timeout: const Timeout(Duration(minutes: 15)));
}
