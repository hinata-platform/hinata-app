import 'package:flutter/foundation.dart';

/// What iOS hands over once an activity may take updates from the server
/// (HIN-103): the activity's push token and the key its state is sealed with.
///
/// [ref] is the app's own reference of the activity and names nothing on the
/// server; [key] is 32 random bytes made on this phone, as Base64.
@immutable
class LiveActivityPushToken {
  const LiveActivityPushToken({
    required this.ref,
    required this.token,
    required this.key,
  });

  final String ref;
  final String token;
  final String key;

  @override
  bool operator ==(Object other) =>
      other is LiveActivityPushToken &&
      other.ref == ref &&
      other.token == token &&
      other.key == key;

  @override
  int get hashCode => Object.hash(ref, token, key);
}

/// Tells the server which Live Activity may take updates, and when it may
/// not any more.
abstract class LiveActivityPushRegistry {
  /// Registers [token]; false when the server refused or was not reached.
  Future<bool> register(LiveActivityPushToken token);

  /// Removes [token] on the server. Best effort: the server drops a token by
  /// itself at the end of its activity and a few hours after.
  Future<void> unregister(String token);
}
