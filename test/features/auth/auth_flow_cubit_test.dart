import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart' show SsoProvider;
import 'package:hinata/features/auth/auth_flow_cubit.dart';

import '../../support/recording_fake.dart';

typedef _Tokens = ({String access, String refresh});

/// The signed-out screens reach the auth endpoints through this cubit: one
/// call per intent, with the same arguments, and the answer handed back.
void main() {
  late FakeAuthRepository auth;
  late AuthFlowCubit cubit;
  const tokens = (access: 'a', refresh: 'r');

  setUp(() {
    auth = FakeAuthRepository();
    cubit = AuthFlowCubit(auth);
  });
  tearDown(() => cubit.close());

  test('the token flows answer the pair the server issued', () async {
    for (final member in [#exchangeSso, #acceptInvite, #acceptPasswordReset]) {
      auth.answer<_Tokens>(member, tokens);
    }

    expect(await cubit.exchangeSso('c1'), tokens);
    expect(await cubit.acceptInvite('t1', 'pw1'), tokens);
    expect(await cubit.acceptPasswordReset('t2', 'pw2'), tokens);
    expect(auth.calls.map((c) => c.positionalArguments), [
      ['c1'],
      ['t1', 'pw1'],
      ['t2', 'pw2'],
    ]);
  });

  test(
    'the SSO buttons, the invitation and the verification are read',
    () async {
      final providers = <SsoProvider>[];
      const invite = (email: 'a@example.org', displayName: 'A');
      const verified = (pendingApproval: true, access: null, refresh: null);
      auth.answer<List<SsoProvider>>(#ssoProviders, providers);
      auth.answer<({String email, String displayName})>(#inviteInfo, invite);
      auth.answer<({bool pendingApproval, String? access, String? refresh})>(
        #verifyEmail,
        verified,
      );

      expect(await cubit.ssoProviders(), same(providers));
      expect(await cubit.inviteInfo('t1'), invite);
      expect(await cubit.verifyEmail('t2'), verified);
      expect(auth.calls[1].positionalArguments, ['t1']);
      expect(auth.calls[2].positionalArguments, ['t2']);
    },
  );

  test(
    'registration, its resend and a reset request go out as typed',
    () async {
      for (final member in [
        #register,
        #resendVerification,
        #requestPasswordReset,
      ]) {
        auth.answer<void>(member, null);
      }

      await cubit.register(
        email: 'a@example.org',
        username: 'a',
        displayName: 'A',
        password: 'pw',
      );
      await cubit.resendVerification('a@example.org');
      await cubit.requestPasswordReset('b@example.org');

      expect(auth.calls[0].namedArguments, {
        #email: 'a@example.org',
        #username: 'a',
        #displayName: 'A',
        #password: 'pw',
      });
      expect(auth.calls[1].positionalArguments, ['a@example.org']);
      expect(auth.calls[2].positionalArguments, ['b@example.org']);
    },
  );

  test('a refused redemption comes back as the same failure', () async {
    auth.fail(#exchangeSso, failure);

    await expectLater(cubit.exchangeSso('c1'), throwsA(same(failure)));
  });
}
