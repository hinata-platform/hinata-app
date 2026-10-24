import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/app.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';

/// A demand to accept new house rules reaches a running app with its next
/// `/meta` (HIN-175): the session is read again when the version in force is
/// not the one it knows, and only then.
void main() {
  AuthState signedIn({int? rulesVersion}) => AuthState(
    status: AuthStatus.authenticated,
    user: AuthUser(
      id: 'u1',
      email: 'u1@example.org',
      username: 'u1',
      displayName: 'U One',
      roles: const {'USER'},
      rulesVersion: rulesVersion,
    ),
  );

  test('a new version in force reads the session again', () {
    expect(
      houseRulesMoved(inForce: 4, auth: signedIn(rulesVersion: 3)),
      isTrue,
    );
  });

  test('the version the session knows changes nothing', () {
    expect(
      houseRulesMoved(inForce: 3, auth: signedIn(rulesVersion: 3)),
      isFalse,
    );
  });

  test('nobody signed in, or a server without rules, changes nothing', () {
    expect(
      houseRulesMoved(
        inForce: 4,
        auth: const AuthState(status: AuthStatus.unauthenticated),
      ),
      isFalse,
    );
    expect(
      houseRulesMoved(inForce: null, auth: signedIn(rulesVersion: 3)),
      isFalse,
    );
  });
}
