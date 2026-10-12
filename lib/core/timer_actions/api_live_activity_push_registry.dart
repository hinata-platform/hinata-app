import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../timer_surfaces/live_activity_push_registry.dart';

/// [LiveActivityPushRegistry] over `/api/v1/me/devices`.
///
/// The server needs the phone's FCM token beside the activity's: FCM routes
/// a Live Activity update to the app it belongs to by that token.
class ApiLiveActivityPushRegistry implements LiveActivityPushRegistry {
  ApiLiveActivityPushRegistry(this._api, {Future<String?> Function()? fcmToken})
    : _fcmToken = fcmToken ?? (() => FirebaseMessaging.instance.getToken());

  final ApiClient _api;
  final Future<String?> Function() _fcmToken;

  /// The tokens this run registered and has not removed yet.
  final Set<String> _held = {};

  @override
  Future<bool> register(LiveActivityPushToken token) async {
    try {
      final fcm = await _fcmToken();
      if (fcm == null || fcm.isEmpty) return false;
      await _api.post(
        '/api/v1/me/devices',
        body: {
          'token': token.token,
          'platform': 'ios',
          'kind': 'liveActivityUpdate',
          'activityId': token.ref,
          'contentKey': token.key,
          'fcmToken': fcm,
        },
      );
      _held.add(token.token);
      return true;
    } catch (error) {
      debugPrint('Live Activity registration failed: $error');
      return false;
    }
  }

  @override
  Future<void> unregister(String token) async {
    _held.remove(token);
    try {
      await _api.delete('/api/v1/me/devices', body: {'token': token});
    } catch (_) {
      // The server drops it with the end of the activity anyway.
    }
  }

  /// Removes every token this run registered, while the session can still
  /// say so (a sign-out). The server would otherwise keep them for the
  /// account that left until they expire.
  Future<void> unregisterAll() => Future.wait([
    for (final token in {..._held}) unregister(token),
  ]);
}
