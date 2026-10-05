import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/git_connection.dart';
import 'package:hinata/core/models/git_dev_info.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/git/settings/git_settings_cubit.dart';

import '../../support/recording_fake.dart';

/// The connect wizard, the settings section and the issue rail reach the git
/// endpoints through this cubit; each intent is one repository call with the
/// same arguments, and its answer or failure comes back untouched.
void main() {
  late FakeGitRepository git;
  late GitSettingsCubit cubit;
  final project = Project.fromJson(const {
    'id': 'p1',
    'key': 'HIN',
    'name': 'x',
  });

  setUp(() {
    git = FakeGitRepository();
    cubit = GitSettingsCubit(git);
  });
  tearDown(() => cubit.close());

  test(
    'the OAuth round trip forwards the project, provider and state',
    () async {
      const start = GitOAuthStart(available: true, state: 's1');
      git.answer<GitOAuthStart>(#gitOAuthStart, start);
      expect(await cubit.oauthStart('p1', 'github'), same(start));
      expect(git.only.positionalArguments, ['p1', 'github']);

      git.calls.clear();
      const status = GitOAuthSessionStatus(status: 'AUTHORIZED');
      git.answer<GitOAuthSessionStatus>(#gitOAuthSession, status);
      expect(await cubit.oauthSession('s1'), same(status));
      expect(git.only.positionalArguments, ['s1']);
    },
  );

  test('owners and repositories are read for the chosen provider', () async {
    final owners = <GitOwner>[];
    git.answer<List<GitOwner>>(#gitOwners, owners);
    expect(await cubit.owners('p1', 'gitlab', state: 's1'), same(owners));
    expect(git.only.positionalArguments, ['p1', 'gitlab']);
    expect(git.only.namedArguments[#state], 's1');

    git.calls.clear();
    final repos = <GitRepo>[];
    git.answer<List<GitRepo>>(#gitRepos, repos);
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
      git.answer<Project>(member, project);
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
    git.fail(#gitSetBranchTemplate, failure);

    await expectLater(
      cubit.setBranchTemplate('p1', '{key}'),
      throwsA(same(failure)),
    );
  });
}
