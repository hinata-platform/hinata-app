import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/timer_surfaces/adapters/local_notifications_surface.dart';
import 'package:hinata/core/timer_actions/timer_background_action.dart';
import 'package:hinata/core/timer_surfaces/background/timer_surface_snapshot.dart';
import 'package:hinata/core/timer_surfaces/timer_surface.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';
import 'package:hinata_device_lock/hinata_device_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stop and the next phase from a notification, a widget or the tile, without
/// the app (HIN-103): the server's answer is what counts, the token is never
/// refreshed in the background, and a locked phone does nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding answers every request with 400; this one talks to the
  // server below, on the loopback address.
  HttpOverrides.global = _RealNetwork();

  late HttpServer server;
  late List<String> requests;
  late Map<String, dynamic>? running;
  late int timerStatus;

  setUp(() async {
    requests = [];
    timerStatus = 200;
    running = {
      'id': 'timer-1',
      'startedAt': DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 10))
          .toIso8601String(),
      'mode': 'POMODORO',
      'pomodoro': {'work': 25, 'shortBreak': 5, 'longBreak': 15, 'cycles': 4},
      'phase': 'WORK',
      'description': 'Quarterly report',
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      requests.add('${request.method} ${request.uri.path} $body'.trim());
      final response = request.response..headers.contentType = ContentType.json;
      switch ('${request.method} ${request.uri.path}') {
        case 'GET /api/v1/me/timer':
          response.statusCode = timerStatus;
          if (timerStatus == 200 && running != null) {
            response.write(jsonEncode(running));
          } else if (timerStatus == 200) {
            response.statusCode = 204;
          }
        case 'POST /api/v1/me/timer/stop':
          response.write(
            jsonEncode({
              'entry': {'id': 'timer-1', 'durationMinutes': 10},
            }),
          );
        case 'POST /api/v1/me/timer/phase':
          response.write(
            jsonEncode({
              ...running!,
              'id': 'timer-2',
              'phase': 'BREAK',
              'startedAt': DateTime.now().toUtc().toIso8601String(),
            }),
          );
        default:
          response.statusCode = 404;
      }
      await response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Future<AppStorage> signedIn() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    await storage.setServerUrl('http://127.0.0.1:${server.port}');
    await storage.setTokens(access: 'access', refresh: 'refresh');
    return storage;
  }

  const snapshot = TimerSurfaceSnapshot(
    prefs: TimerSurfacePrefs.suggested,
    texts: TimerSurfaceTexts(
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
    ),
  );

  Future<(TimerBackgroundAction, RecordingSurface, AppStorage)> action({
    bool locked = false,
  }) async {
    final storage = await signedIn();
    final surface = RecordingSurface();
    return (
      TimerBackgroundAction(
        time: TimeRepository(ApiClient(storage, refreshOnUnauthorized: false)),
        surfaces: [surface],
        snapshot: snapshot,
        lock: FakeLock(locked),
      ),
      surface,
      storage,
    );
  }

  test(
    'stop files the running timer by its id and clears the surfaces',
    () async {
      final (run, surface, _) = await action();

      expect(
        await run.run(TimerBackgroundCommand.stop),
        TimerBackgroundOutcome.done,
      );

      final stop = requests.singleWhere((r) => r.contains('/timer/stop'));
      expect(stop, contains('"timerId":"timer-1"'));
      expect(surface.applied.single.running, isFalse);
    },
  );

  test('the next phase turns the phase it saw and draws the break', () async {
    final (run, surface, _) = await action();

    await run.run(TimerBackgroundCommand.advancePhase);

    expect(
      requests.singleWhere((r) => r.contains('/timer/phase')),
      contains('"timerId":"timer-1"'),
    );
    expect(surface.applied.single.isBreak, isTrue);
    expect(surface.applied.single.texts.onBreak, 'Break');
  });

  test('nothing running: no stop is sent, the surfaces go idle', () async {
    running = null;
    final (run, surface, _) = await action();

    expect(
      await run.run(TimerBackgroundCommand.stop),
      TimerBackgroundOutcome.nothingRunning,
    );
    expect(requests.where((r) => r.contains('/timer/stop')), isEmpty);
    expect(surface.applied.single.running, isFalse);
  });

  test('a 401 ends the attempt without a refresh and without signing the '
      'app out', () async {
    timerStatus = 401;
    final (run, surface, storage) = await action();

    expect(
      await run.run(TimerBackgroundCommand.stop),
      TimerBackgroundOutcome.signedOut,
    );
    expect(requests.where((r) => r.contains('/auth/refresh')), isEmpty);
    expect(storage.accessToken, 'access');
    expect(storage.refreshToken, 'refresh');
    expect(surface.applied, isEmpty);
  });

  test('a locked phone does nothing', () async {
    final (run, surface, _) = await action(locked: true);

    expect(
      await run.run(TimerBackgroundCommand.stop),
      TimerBackgroundOutcome.locked,
    );
    expect(requests, isEmpty);
    expect(surface.applied, isEmpty);
  });

  test('only stop, the next phase and discard exist, and only from our '
      'own links and buttons', () {
    expect(
      TimerBackgroundCommand.fromUri(Uri.parse('hinata://timer/stop')),
      TimerBackgroundCommand.stop,
    );
    expect(
      TimerBackgroundCommand.fromUri(Uri.parse('hinata://timer/advancePhase')),
      TimerBackgroundCommand.advancePhase,
    );
    expect(
      TimerBackgroundCommand.fromUri(Uri.parse('hinata://timer/start')),
      isNull,
    );
    expect(
      TimerBackgroundCommand.fromUri(Uri.parse('https://evil/timer/stop')),
      isNull,
    );
    expect(
      TimerBackgroundCommand.fromNotificationAction(
        TimerNotificationAction.stop,
      ),
      TimerBackgroundCommand.stop,
    );
    expect(TimerBackgroundCommand.fromNotificationAction('other'), isNull);
  });

  test('the snapshot keeps switches and words and nothing of the timer', () {
    final encoded = snapshot.encode();

    expect(TimerSurfaceSnapshot.decode(encoded)!.texts.stop, 'Stop');
    expect(
      TimerSurfaceSnapshot.decode(encoded)!.prefs,
      TimerSurfacePrefs.suggested,
    );
    expect(TimerSurfaceSnapshot.decode('not json'), isNull);
    expect(encoded, isNot(contains('timer-1')));
  });
}

class FakeLock extends HinataDeviceLock {
  const FakeLock(this.locked);

  final bool locked;

  @override
  Future<bool> isLocked() async => locked;
}

class RecordingSurface extends TimerSurface {
  final List<TimerSurfaceState> applied = [];

  @override
  String get id => 'recording';

  @override
  TimerSurfaceCapabilities get capabilities => TimerSurfaceCapabilities.none;

  @override
  Future<void> init(TimerSurfaceHost host) async {}

  @override
  Future<void> apply(TimerSurfaceState state) async => applied.add(state);

  @override
  Future<void> phaseEnded(
    TimerSurfaceState state, {
    required bool foreground,
  }) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}

class _RealNetwork extends HttpOverrides {}
