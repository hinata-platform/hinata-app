import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/timer_actions/api_live_activity_push_registry.dart';
import 'package:hinata/core/timer_surfaces/live_activity_push_registry.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/features/time/timer_surface_options.dart';

/// Background updates of the Live Activity (HIN-103) are an opt-in of their
/// own: off by default, never offered in passing, only on an iPhone, and
/// switched off with the running timer.
void main() {
  test('off by default, off for a store that never heard of it, kept when '
      'switched on', () {
    expect(const TimerSurfacePrefs().backgroundLiveActivity, isFalse);
    expect(TimerSurfacePrefs.suggested.backgroundLiveActivity, isFalse);
    expect(
      TimerSurfacePrefs.fromJson(const {
        'consented': true,
      }).backgroundLiveActivity,
      isFalse,
    );
    final on = TimerSurfacePrefs.suggested.copyWith(
      backgroundLiveActivity: true,
    );
    expect(TimerSurfacePrefs.fromJson(on.toJson()), on);
  });

  test(
    'only on iOS, never in the introduction, gone with the running timer',
    () {
      const option = TimerSurfaceOption.backgroundUpdates;
      expect(option.availableOn(SurfacePlatform.ios), isTrue);
      for (final platform in SurfacePlatform.values) {
        if (platform == SurfacePlatform.ios) continue;
        expect(option.availableOn(platform), isFalse, reason: '$platform');
      }
      expect(option.inIntro, isFalse);
      expect(option.needsPermission(SurfacePlatform.ios), isFalse);
      final on = withOption(TimerSurfacePrefs.suggested, option, true);
      expect(on.backgroundLiveActivity, isTrue);
      expect(
        withOption(
          on,
          TimerSurfaceOption.running,
          false,
        ).backgroundLiveActivity,
        isFalse,
      );
    },
  );

  test('the state asks for updates only with consent, the running timer and '
      'the switch', () {
    final timer = RunningTimer(
      id: 't',
      startedAt: DateTime.now().toUtc(),
      mode: TimerMode.stopwatch,
    );
    TimerSurfaceState derive(TimerSurfacePrefs prefs) =>
        deriveTimerSurfaceState(timer, prefs, gated: false);
    final on = TimerSurfacePrefs.suggested.copyWith(
      backgroundLiveActivity: true,
    );

    expect(derive(on).backgroundUpdates, isTrue);
    expect(derive(on.copyWith(consented: false)).backgroundUpdates, isFalse);
    expect(
      derive(on.copyWith(runningSurface: false)).backgroundUpdates,
      isFalse,
    );
    expect(derive(TimerSurfacePrefs.suggested).backgroundUpdates, isFalse);
  });

  test('the registration names the activity, its key and the phone, and '
      'nothing of the timer', () async {
    final api = _RecordingApi();
    final registry = ApiLiveActivityPushRegistry(
      api,
      fcmToken: () async => 'fcm-1',
    );

    final ok = await registry.register(
      const LiveActivityPushToken(ref: 'ref-1', token: 'aa11', key: 'a2V5'),
    );
    await registry.unregister('aa11');

    expect(ok, isTrue);
    expect(api.posts.single, {
      'token': 'aa11',
      'platform': 'ios',
      'kind': 'liveActivityUpdate',
      'activityId': 'ref-1',
      'contentKey': 'a2V5',
      'fcmToken': 'fcm-1',
    });
    expect(api.deletes.single, {'token': 'aa11'});
  });

  test('without an FCM token nothing is registered', () async {
    final api = _RecordingApi();
    final registry = ApiLiveActivityPushRegistry(
      api,
      fcmToken: () async => null,
    );

    expect(
      await registry.register(
        const LiveActivityPushToken(ref: 'r', token: 't', key: 'k'),
      ),
      isFalse,
    );
    expect(api.posts, isEmpty);
  });
}

class _RecordingApi implements ApiClient {
  final List<Object?> posts = [];
  final List<Object?> deletes = [];

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    expect(path, '/api/v1/me/devices');
    posts.add(body);
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    expect(path, '/api/v1/me/devices');
    deletes.add(body);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
