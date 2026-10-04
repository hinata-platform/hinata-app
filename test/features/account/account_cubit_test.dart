import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/models/personal_access_token.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/features/account/account_cubit.dart';

import '../recording_fake.dart';

class _FakeAccount with RecordingFake implements AccountRepository {}

/// The account page, its modals, the token section and the shell's avatar
/// menu reach `/me` through this cubit: one repository call per intent, with
/// the same arguments, and its answer or failure handed back.
void main() {
  late _FakeAccount account;
  late AccountCubit cubit;

  setUp(() {
    account = _FakeAccount();
    cubit = AccountCubit(account);
  });
  tearDown(() => cubit.close());

  test('the reads answer what the repository answered', () async {
    final teams = <AccessTeam>[];
    final projects = <AccessProject>[];
    final pats = <PersonalAccessToken>[];
    final page = (items: <DeviceSession>[], total: 0);
    account.answers[#myTeams] = () => Future<List<AccessTeam>>.value(teams);
    account.answers[#myProjects] = () =>
        Future<List<AccessProject>>.value(projects);
    account.answers[#listPats] = () =>
        Future<List<PersonalAccessToken>>.value(pats);
    account.answers[#sessionsPage] = () =>
        Future<({List<DeviceSession> items, int total})>.value(page);

    expect(await cubit.myTeams(), same(teams));
    expect(await cubit.myProjects(), same(projects));
    expect(await cubit.pats(), same(pats));
    expect(await cubit.sessionsPage(size: 5), page);
    expect(account.calls[3].namedArguments, {#page: 0, #size: 5});
  });

  test('the profile and the session reads pass a failure back', () async {
    account.answers[#meAccount] = () => Future<Me>.error(failure);
    account.answers[#updateMyProfile] = () => Future<Me>.error(failure);

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
      account.answers[member] = () => Future<void>.value();
    }
    final codes = <String>['c1'];
    account.answers[#verifyTotpSetup] = () => Future<List<String>>.value(codes);
    account.answers[#regenerateRecoveryCodes] = () =>
        Future<List<String>>.value(codes);

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
    account.answers[#createPat] = () => Future<CreatedPat>.error(failure);

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
    account.answers[#saveNotificationPrefs] = () =>
        Future<NotifPrefs>.error(failure);
    account.answers[#uploadAvatar] = () => Future<String>.error(failure);
    account.answers[#beginTotpSetup] = () => Future<TotpSetup>.error(failure);

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
