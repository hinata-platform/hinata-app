import 'dart:async';

import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';

/// An account repository that only knows how to save a tint: records every
/// write, can refuse, and can hold a write open until [gate] completes.
class FakeTintAccountRepository implements AccountRepository {
  bool refuse = false;
  Future<void>? gate;
  final List<TintPreferences> saved = [];

  @override
  Future<Me> updateMyProfile({
    String? displayName,
    String? title,
    String? pronouns,
    String? locale,
    String? timezone,
    TimePreferences? timePreferences,
    TintPreferences? tint,
  }) async {
    if (refuse) throw ApiFailure('nope');
    saved.add(tint!);
    await gate;
    return me(tint);
  }

  static Me me(TintPreferences tint) => Me(
    id: 'u1',
    displayName: 'Me',
    username: 'me',
    email: 'me@example.org',
    emailVerified: true,
    origin: AuthOrigin.local,
    roles: const ['MEMBER'],
    active: true,
    twoFactor: const TwoFactor(
      enabled: false,
      method: 'TOTP',
      recoveryRemaining: 0,
    ),
    notificationPreferences: NotifPrefs.fromJson(const {}),
    tint: tint,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
