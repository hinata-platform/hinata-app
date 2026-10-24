import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/auth/sso_launch.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sign-in by SSO is bound to the device that starts it: the start carries
/// the challenge of a verifier only this device keeps, and the server hands
/// the code of that sign-in to no one without the verifier.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://server.test',
    });
    storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  });

  test('the challenge is the S256 of the verifier', () {
    // RFC 7636, appendix B: the server checks against the same pair.
    expect(
      ssoChallengeOf('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('every sign-in gets a verifier of its own', () {
    final verifier = newSsoVerifier();

    expect(verifier, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    expect(newSsoVerifier(), isNot(verifier));
  });

  test('the start keeps the verifier and carries its challenge', () async {
    final uri = await prepareSso(storage, _provider, invite: 'i1');

    final verifier = storage.pendingSsoVerifier();
    expect(verifier, isNotNull);
    expect(uri.path, '/api/v1/auth/sso/start/oidc');
    expect(uri.queryParameters, {
      'invite': 'i1',
      'challenge': ssoChallengeOf(verifier!),
    });
  });

  test('a sign-in waits for its callback for a while, not for ever', () async {
    final started = DateTime(2026, 10, 24, 12);
    final verifier = 'v' * 43;
    await storage.setPendingSsoVerifier(verifier, now: started);

    expect(
      storage.pendingSsoVerifier(
        now: started.add(AppStorage.ssoPendingFor - const Duration(minutes: 1)),
      ),
      verifier,
    );
    expect(
      storage.pendingSsoVerifier(now: started.add(AppStorage.ssoPendingFor)),
      isNull,
    );

    await storage.clearPendingSsoVerifier();
    expect(storage.pendingSsoVerifier(now: started), isNull);
  });
}

const _provider = SsoProvider(
  id: 'oidc',
  displayName: 'Staff',
  loginUrl: '/api/v1/auth/sso/start/oidc',
);
