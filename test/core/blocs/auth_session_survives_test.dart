import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The check that runs at boot, and after a server switch, must not end a
/// session it could not reach.
///
/// It used to: any `ApiFailure` from `/me` counted as "the server refused this
/// token", and `ApiFailure` is what the client throws for a timeout, a 429 and
/// a 503 alike. So a server restarting under a developer, or a dead keep-alive
/// socket, signed them out mid-session — at no particular moment, which is what
/// made it so hard to place.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStorage> signedIn() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    await storage.setServerUrl('https://hinata.example');
    await storage.setTokens(access: 'access', refresh: 'refresh');
    return storage;
  }

  Future<AuthState> check(AppStorage storage, _FakeAuth repository) async {
    final bloc = AuthBloc(repository: repository, storage: storage)
      ..add(const AuthChecked());
    final state = await bloc.stream.firstWhere(
      (s) => s.status != AuthStatus.unknown,
    );
    await bloc.close();
    return state;
  }

  test('a server that is not answering does not end the session', () async {
    for (final status in const [null, 429, 500, 502, 503, 504]) {
      final storage = await signedIn();
      final state = await check(
        storage,
        _FakeAuth(ApiFailure('errors.unexpected', statusCode: status)),
      );

      expect(state.status, AuthStatus.unauthenticated, reason: '$status');
      // The one thing that matters: the tokens are still there, so the next
      // request — or the next boot — signs back in without anybody typing.
      expect(storage.accessToken, 'access', reason: '$status');
      expect(storage.refreshToken, 'refresh', reason: '$status');
    }
  });

  test('signing out removes the push registration while the tokens still '
      'hold, then drops them', () async {
    final storage = await signedIn();
    String? accessDuringUnregister;
    final bloc = AuthBloc(
      repository: _FakeAuth(ApiFailure('errors.unexpected')),
      storage: storage,
      beforeSignOut: () async => accessDuringUnregister = storage.accessToken,
    )..add(const LogoutRequested());
    await bloc.stream.firstWhere((s) => s.status == AuthStatus.unauthenticated);
    await bloc.close();

    expect(accessDuringUnregister, 'access');
    expect(storage.accessToken, isNull);
  });

  test('a failing unregister does not block the sign-out', () async {
    final storage = await signedIn();
    final bloc = AuthBloc(
      repository: _FakeAuth(ApiFailure('errors.unexpected')),
      storage: storage,
      beforeSignOut: () => Future<void>.error(StateError('offline')),
    )..add(const LogoutRequested());
    await bloc.stream.firstWhere((s) => s.status == AuthStatus.unauthenticated);
    await bloc.close();

    expect(storage.accessToken, isNull);
  });

  test('a sign-out waits only its grace on an unregister that never '
      'answers', () async {
    final storage = await signedIn();
    final bloc = AuthBloc(
      repository: _FakeAuth(ApiFailure('errors.unexpected')),
      storage: storage,
      beforeSignOut: () => Completer<void>().future,
      signOutGrace: const Duration(milliseconds: 200),
    )..add(const LogoutRequested());

    final signedOut = await bloc.stream
        .firstWhere((s) => s.status == AuthStatus.unauthenticated)
        .timeout(const Duration(seconds: 2));
    await bloc.close();

    expect(signedOut.status, AuthStatus.unauthenticated);
    expect(storage.accessToken, isNull);
  });

  test('a refused token is dropped', () async {
    for (final status in const [400, 401, 403]) {
      final storage = await signedIn();
      await check(
        storage,
        _FakeAuth(ApiFailure('errors.unauthorized', statusCode: status)),
      );

      expect(storage.accessToken, isNull, reason: '$status');
      expect(storage.refreshToken, isNull, reason: '$status');
    }
  });
}

/// An auth repository whose `/me` always fails the same way.
class _FakeAuth implements AuthRepository {
  _FakeAuth(this.failure);

  final ApiFailure failure;

  @override
  Future<AuthUser> me() async => throw failure;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
