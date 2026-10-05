import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/models/personal_access_token.dart';
import 'package:hinata/features/account/account_cubit.dart';

import '../../support/recording_fake.dart';

/// The account page, its modals, the token section and the shell's avatar
/// menu reach `/me` through this cubit: one repository call per intent, with
/// the same arguments, and its answer or failure handed back.
void main() {
  late FakeAccountRepository account;
  late AccountCubit cubit;

  setUp(() {
    account = FakeAccountRepository();
    cubit = AccountCubit(account);
  });
  tearDown(() => cubit.close());

  test('the reads answer what the repository answered', () async {
    final teams = <AccessTeam>[];
    final projects = <AccessProject>[];
    final pats = <PersonalAccessToken>[];
    final page = (items: <DeviceSession>[], total: 0);
    account.answer<List<AccessTeam>>(#myTeams, teams);
    account.answer<List<AccessProject>>(#myProjects, projects);
    account.answer<List<PersonalAccessToken>>(#listPats, pats);
    account.answer<({List<DeviceSession> items, int total})>(
      #sessionsPage,
      page,
    );

    expect(await cubit.myTeams(), same(teams));
    expect(await cubit.myProjects(), same(projects));
    expect(await cubit.pats(), same(pats));
    expect(await cubit.sessionsPage(size: 5), page);
    expect(account.calls[3].namedArguments, {#page: 0, #size: 5});
  });

  test('the profile and the session reads pass a failure back', () async {
    account.fail(#meAccount, failure);
    account.fail(#updateMyProfile, failure);

    await expectLater(cubit.me(), throwsA(same(failure)));
    await expectLater(
      cubit.updateProfile(locale: 'de'),
      throwsA(same(failure)),
    );
    expect(account.calls.last.namedArguments, {
      #displayName: null,
      #title: null,
      #pronouns: null,
      #locale: 'de',
      #timezone: null,
      #timePreferences: null,
    });
  });

  test('every write goes out with its argument', () async {
    for (final member in [
      #deleteAvatar,
      #requestEmailChange,
      #sendPasswordReset,
      #revokeSession,
      #revokeOtherSessions,
      #disableTotp,
      #requestDataReport,
      #deleteMyAccount,
      #revokePat,
      #deletePat,
    ]) {
      account.answer<void>(member, null);
    }
    final codes = <String>['c1'];
    account.answer<List<String>>(#verifyTotpSetup, codes);
    account.answer<List<String>>(#regenerateRecoveryCodes, codes);

    await cubit.deleteAvatar();
    await cubit.requestEmailChange('new@example.org');
    await cubit.sendPasswordReset();
    await cubit.revokeSession('s1');
    await cubit.revokeOtherSessions();
    expect(await cubit.verifyTotpSetup('123456'), same(codes));
    expect(await cubit.regenerateRecoveryCodes('654321'), same(codes));
    await cubit.disableTotp('111111');
    await cubit.requestDataReport();
    await cubit.deleteAccount();
    await cubit.revokePat('t1');
    await cubit.deletePat('t2');

    expect(account.calls.map((c) => c.memberName), [
      #deleteAvatar,
      #requestEmailChange,
      #sendPasswordReset,
      #revokeSession,
      #revokeOtherSessions,
      #verifyTotpSetup,
      #regenerateRecoveryCodes,
      #disableTotp,
      #requestDataReport,
      #deleteMyAccount,
      #revokePat,
      #deletePat,
    ]);
    expect(account.calls.map((c) => c.positionalArguments), [
      [],
      ['new@example.org'],
      [],
      ['s1'],
      [],
      ['123456'],
      ['654321'],
      ['111111'],
      [],
      [],
      ['t1'],
      ['t2'],
    ]);
  });

  test('a token is minted with its name, scopes and lifetime', () async {
    account.fail(#createPat, failure);

    await expectLater(
      cubit.createPat(name: 'ci', scopes: ['read'], ttlDays: 30),
      throwsA(same(failure)),
    );
    expect(account.only.namedArguments, {
      #name: 'ci',
      #scopes: ['read'],
      #ttlDays: 30,
    });
  });

  test('preferences, the avatar and 2FA setup pass their argument and failure '
      'on', () async {
    const prefs = NotifPrefs(
      emailEnabled: true,
      pushEnabled: false,
      events: {},
    );
    final file = MultipartFile.fromBytes(const [1, 2, 3], filename: 'a.png');
    account.fail(#saveNotificationPrefs, failure);
    account.fail(#uploadAvatar, failure);
    account.fail(#beginTotpSetup, failure);

    await expectLater(
      cubit.saveNotificationPrefs(prefs),
      throwsA(same(failure)),
    );
    await expectLater(cubit.uploadAvatar(file), throwsA(same(failure)));
    await expectLater(cubit.beginTotpSetup(), throwsA(same(failure)));
    expect(account.calls[0].positionalArguments, [same(prefs)]);
    expect(account.calls[1].positionalArguments, [same(file)]);
    expect(account.calls[2].memberName, #beginTotpSetup);
  });
}
