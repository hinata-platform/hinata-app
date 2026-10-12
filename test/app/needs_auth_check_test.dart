import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/app.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';

/// A server that comes back after a start against it failed takes the person
/// back in with the session they still hold, instead of to the sign-in.
void main() {
  test('a new server is always checked', () {
    expect(
      needsAuthCheck(
        checkedServer: 'https://a.example',
        server: 'https://b.example',
        status: AuthStatus.authenticated,
        hasToken: true,
      ),
      isTrue,
    );
  });

  test('the same server again is checked when a session is stranded', () {
    expect(
      needsAuthCheck(
        checkedServer: 'https://a.example',
        server: 'https://a.example',
        status: AuthStatus.unauthenticated,
        hasToken: true,
      ),
      isTrue,
    );
  });

  test('the same server again is left alone otherwise', () {
    for (final (status, token) in const [
      (AuthStatus.authenticated, true),
      (AuthStatus.unauthenticated, false),
      (AuthStatus.authenticating, true),
    ]) {
      expect(
        needsAuthCheck(
          checkedServer: 'https://a.example',
          server: 'https://a.example',
          status: status,
          hasToken: token,
        ),
        isFalse,
        reason: '$status $token',
      );
    }
  });
}
