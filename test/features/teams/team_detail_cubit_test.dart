import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/teams/team_detail_cubit.dart';

import '../../support/recording_fake.dart';

/// One team's page: the bundle the tabs render, and the writes the tabs make.
void main() {
  late FakeTeamRepository teams;
  late FakeUserRepository users;
  late FakeProjectRepository projects;
  late TeamDetailCubit cubit;

  const team = Team(id: 't1', key: 'OPS', name: 'Ops');
  const uma = DirectoryUser(id: 'u1', username: 'uma', displayName: 'Uma');
  const project = Project(id: 'p1', key: 'KULT', name: 'Kultur');
  const created = TeamActivity(id: 'a1', verb: 'CREATED');

  setUp(() {
    teams = FakeTeamRepository()
      ..answer(#team, team)
      ..answer(#teamActivityPage, (items: const [created], total: 7));
    users = FakeUserRepository()..answer(#users, const [uma]);
    projects = FakeProjectRepository()..answer(#projects, const [project]);
    cubit = TeamDetailCubit(
      teamId: 't1',
      teams: teams,
      users: users,
      projects: projects,
    );
  });
  tearDown(() => cubit.close());

  test(
    'loads the team, the directory, the projects and the activity',
    () async {
      await cubit.load();

      final data = cubit.state.data!;
      expect(data.team, team);
      expect(data.usersById, {'u1': uma});
      expect(data.projectsById, {'p1': project});
      expect(data.activity, [created]);
      expect(data.activityTotal, 7);
      expect(teams.callTo(#team).positionalArguments, ['t1']);
      expect(teams.callTo(#teamActivityPage).positionalArguments, ['t1']);
    },
  );

  test('a failed load keeps the server\'s message', () async {
    teams.fail(#team, ApiFailure('errors.notFound'));

    await cubit.load();

    expect(cubit.state.data, isNull);
    expect(cubit.state.errorKey, 'errors.notFound');
  });

  test('reads an older page of the activity', () async {
    final page = await cubit.activityPage('t1', page: 2);

    expect(page.items, [created]);
    expect(page.total, 7);
    final call = teams.callTo(#teamActivityPage);
    expect(call.positionalArguments, ['t1']);
    expect(call.namedArguments[#page], 2);
  });

  test('detaches a project', () async {
    teams.answer(#detachTeamProject, team);

    expect(await cubit.detachProject('t1', 'p1'), team);
    expect(teams.callTo(#detachTeamProject).positionalArguments, ['t1', 'p1']);
  });

  test('passes a refused detach on', () async {
    teams.fail(#detachTeamProject, ApiFailure('errors.forbidden'));

    await expectLater(
      cubit.detachProject('t1', 'p1'),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('uploads and removes the team picture', () async {
    teams
      ..answer(#uploadTeamAvatar, 'https://x/t1.png?v=3')
      ..answer<void>(#deleteTeamAvatar, null);
    final file = MultipartFile.fromBytes(const [1], filename: 't.png');

    expect(await cubit.uploadAvatar('t1', file), 'https://x/t1.png?v=3');
    await cubit.removeAvatar('t1');

    expect(teams.callTo(#uploadTeamAvatar).positionalArguments, ['t1', file]);
    expect(teams.callTo(#deleteTeamAvatar).positionalArguments, ['t1']);
  });
}
