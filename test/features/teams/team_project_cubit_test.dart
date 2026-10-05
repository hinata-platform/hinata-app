import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/teams/team_project_cubit.dart';

import '../../support/recording_fake.dart';

/// The add-project modal's cubit: attach, or create a project for the team.
void main() {
  late FakeTeamRepository teams;
  late FakeProjectRepository projects;
  late TeamProjectCubit cubit;

  const team = Team(id: 't1', key: 'OPS', name: 'Ops');
  const created = Project(id: 'p9', key: 'NEW', name: 'New');

  setUp(() {
    teams = FakeTeamRepository();
    projects = FakeProjectRepository();
    cubit = TeamProjectCubit(teams: teams, projects: projects);
  });
  tearDown(() => cubit.close());

  test('attaches the picked projects', () async {
    teams.answer(#attachTeamProjects, team);

    expect(await cubit.attach('t1', ['p1', 'p2']), team);
    expect(teams.callTo(#attachTeamProjects).positionalArguments, [
      't1',
      ['p1', 'p2'],
    ]);
  });

  test('creates a project that belongs to the team', () async {
    teams.answer(#createTeamProject, created);

    final answer = await cubit.create(
      't1',
      key: 'NEW',
      name: 'New',
      description: 'About',
      color: '#00aaff',
      leadId: 'u1',
      deadlineBasis: RelativeDateBasis.working,
    );

    expect(answer, created);
    final call = teams.callTo(#createTeamProject);
    expect(call.positionalArguments, ['t1']);
    expect(call.namedArguments, {
      #key: 'NEW',
      #name: 'New',
      #description: 'About',
      #color: '#00aaff',
      #leadId: 'u1',
      #deadlineBasis: RelativeDateBasis.working,
    });
  });

  test('passes a refused creation on', () async {
    teams.fail(#createTeamProject, ApiFailure('projects.keyTaken'));

    await expectLater(
      cubit.create('t1', key: 'NEW', name: 'New'),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('uploads the picture to the new project', () async {
    projects.answer(#uploadProjectAvatar, 'https://x/p9.png');
    final file = MultipartFile.fromBytes(const [1], filename: 'p.png');

    expect(await cubit.uploadProjectAvatar('p9', file), 'https://x/p9.png');
    expect(projects.callTo(#uploadProjectAvatar).positionalArguments, [
      'p9',
      file,
    ]);
  });
}
