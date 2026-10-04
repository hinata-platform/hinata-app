import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/git_connection.dart';
import 'package:hinata/core/models/git_dev_info.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/git_repository.dart';
import 'package:hinata/features/git/settings/git_settings_cubit.dart';

import '../recording_fake.dart';

class _FakeGit with RecordingFake implements GitRepository {}

/// The connect wizard, the settings section and the issue rail reach the git
/// endpoints through this cubit; each intent is one repository call with the
/// same arguments, and its answer or failure comes back untouched.
void main() {
  late _FakeGit git;
  late GitSettingsCubit cubit;
  final project = Project.fromJson(const {
    'id': 'p1',
    'key': 'HIN',
    'name': 'x',
  });

  setUp(() {
    git = _FakeGit();
    cubit = GitSettingsCubit(git);
  });
  tearDown(() => cubit.close());

  test(
    'the OAuth round trip forwards the project, provider and state',
    () async {
      const start = GitOAuthStart(available: true, state: 's1');
      git.answers[#gitOAuthStart] = () => Future<GitOAuthStart>.value(start);
      expect(await cubit.oauthStart('p1', 'github'), same(start));
      expect(git.only.positionalArguments, ['p1', 'github']);

      git.calls.clear();
      const status = GitOAuthSessionStatus(status: 'AUTHORIZED');
      git.answers[#gitOAuthSession] = () =>
          Future<GitOAuthSessionStatus>.value(status);
      expect(await cubit.oauthSession('s1'), same(status));
      expect(git.only.positionalArguments, ['s1']);
    },
  );

  test('owners and repositories are read for the chosen provider', () async {
    final owners = <GitOwner>[];
    git.answers[#gitOwners] = () => Future<List<GitOwner>>.value(owners);
    expect(await cubit.owners('p1', 'gitlab', state: 's1'), same(owners));
    expect(git.only.positionalArguments, ['p1', 'gitlab']);
    expect(git.only.namedArguments[#state], 's1');

    git.calls.clear();
    final repos = <GitRepo>[];
    git.answers[#gitRepos] = () => Future<List<GitRepo>>.value(repos);
    expect(await cubit.repos('p1', 'gitlab', 'o1', state: 's1'), same(repos));
    expect(git.only.positionalArguments, ['p1', 'gitlab', 'o1']);
    expect(git.only.namedArguments[#state], 's1');
  });

  test('every write answers with the updated project', () async {
    for (final member in [
      #gitConnect,
      #gitConnectToken,
      #gitDisconnect,
      #gitResync,
      #gitSetAutomation,
      #gitSetBranchTemplate,
    ]) {
      git.answers[member] = () => Future<Project>.value(project);
    }
    const automation = GitAutomation();

    expect(
      await cubit.connect(
        'p1',
        provider: 'github',
        owner: 'o1',
        repo: 'r1',
        state: 's1',
      ),
      same(project),
    );
    expect(
      await cubit.connectToken('p1', repoUrl: 'u', token: 't'),
      same(project),
    );
    expect(await cubit.disconnect('p1', repoId: 'r1'), same(project));
    expect(await cubit.resync('p1', repoId: 'r1'), same(project));
    expect(await cubit.setAutomation('p1', automation), same(project));
    expect(await cubit.setBranchTemplate('p1', '{key}'), same(project));

    expect(git.calls.map((c) => c.memberName), [
      #gitConnect,
      #gitConnectToken,
      #gitDisconnect,
      #gitResync,
      #gitSetAutomation,
      #gitSetBranchTemplate,
    ]);
    expect(git.calls[0].namedArguments, {
      #provider: 'github',
      #owner: 'o1',
      #repo: 'r1',
      #state: 's1',
    });
    expect(git.calls[1].namedArguments, {#repoUrl: 'u', #token: 't'});
    expect(git.calls[2].namedArguments, {#repoId: 'r1'});
    expect(git.calls[3].namedArguments, {#repoId: 'r1'});
    expect(git.calls[4].positionalArguments, ['p1', same(automation)]);
    expect(git.calls[5].positionalArguments, ['p1', '{key}']);
  });

  test('a refused write comes back as the same failure', () async {
    git.answers[#gitSetBranchTemplate] = () => Future<Project>.error(failure);

    await expectLater(
      cubit.setBranchTemplate('p1', '{key}'),
      throwsA(same(failure)),
    );
  });
}
