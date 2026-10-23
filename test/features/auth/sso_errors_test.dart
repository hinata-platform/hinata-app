import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/auth/sso_errors.dart';

/// The sign-in screen says why an SSO sign-in failed only in our own words
/// (HIN-179): the reason travels in an address any page can link to.
void main() {
  test('every reason the server refuses with has its own sentence', () {
    for (final reason in ssoRefusalReasons) {
      expect(ssoErrorKey(reason), 'auth.ssoRefused.$reason');
    }
  });

  test('where nobody signs in with a password, nobody is told to', () {
    expect(
      ssoErrorKey('ssoAccountNotLinked', passwordSignIn: false),
      'auth.ssoRefused.ssoAccountNotLinkedSsoOnly',
    );
    expect(
      ssoErrorKey('accountDeactivated', passwordSignIn: false),
      'auth.ssoRefused.accountDeactivated',
    );
  });

  test('the app keeps its own reasons', () {
    expect(ssoErrorKey('auth.ssoExchangeFailed'), 'auth.ssoExchangeFailed');
    expect(ssoErrorKey('auth.ssoTimedOut'), 'auth.ssoTimedOut');
  });

  test('anything else is the general sentence', () {
    expect(ssoErrorKey(null), 'auth.ssoProviderFailed');
    expect(ssoErrorKey(''), 'auth.ssoProviderFailed');
    expect(
      ssoErrorKey('[invalid_token_response] An error occurred'),
      'auth.ssoProviderFailed',
    );
    expect(
      ssoErrorKey('Server moved, sign in at evil.example'),
      'auth.ssoProviderFailed',
    );
    expect(
      ssoErrorKey('auth.ssoRefused.ssoAccountNotLinked'),
      'auth.ssoProviderFailed',
    );
  });
}
