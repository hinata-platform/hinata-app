import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/oauth_consent.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/features/oauth/oauth_consent_cubit.dart';

import '../recording_fake.dart';

class _FakeAuth with RecordingFake implements AuthRepository {}

/// The consent page reads the pending request and records the decision
/// through this cubit.
void main() {
  late _FakeAuth auth;
  late OAuthConsentCubit cubit;

  setUp(() {
    auth = _FakeAuth();
    cubit = OAuthConsentCubit(auth);
  });
  tearDown(() => cubit.close());

  test('the request is read by its id', () async {
    const info = OAuthConsentInfo(
      requestId: 'r1',
      clientName: 'Claude',
      redirectHost: 'claude.ai',
      scopes: ['issues:read'],
    );
    auth.answers[#oauthConsentInfo] = () =>
        Future<OAuthConsentInfo>.value(info);

    expect(await cubit.info('r1'), same(info));
    expect(auth.only.positionalArguments, ['r1']);
  });

  test('the decision answers the redirect with what was granted', () async {
    auth.answers[#oauthConsentDecision] = () =>
        Future<String>.value('https://claude.ai/cb?code=x');

    expect(
      await cubit.decide('r1', approved: true, grantedScopes: ['issues:read']),
      'https://claude.ai/cb?code=x',
    );
    expect(auth.only.positionalArguments, ['r1']);
    expect(auth.only.namedArguments, {
      #approved: true,
      #grantedScopes: ['issues:read'],
    });
  });

  test('an expired request comes back as the same failure', () async {
    auth.answers[#oauthConsentInfo] = () =>
        Future<OAuthConsentInfo>.error(failure);

    await expectLater(cubit.info('r1'), throwsA(same(failure)));
  });
}
