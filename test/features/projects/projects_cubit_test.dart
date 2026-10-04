import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/projects/projects_cubit.dart';

import 'repository_recorders.dart';

/// The project list's cubit: one load of the four lists the page shows, and
/// the two requests of the "new project" modal.
void main() {
  late RecordingProjects projects;
  late RecordingUsers users;
  late RecordingTeams teams;
  late ProjectsCubit cubit;

  const running = Project(id: 'p1', key: 'RUN', name: 'Running');
  const archived = Project(id: 'p2', key: 'OLD', name: 'Old', archived: true);
  const team = Team(id: 't1', key: 'OPS', name: 'Ops');

  setUp(() {
    projects = RecordingProjects()
      ..answers[#projects] = () async => const [running];
    users = RecordingUsers()
      ..answers[#users] = () async => const [
        DirectoryUser(
          id: 'u1',
          username: 'uma',
          displayName: 'Uma',
          avatarUrl: 'https://example.org/u1.png',
        ),
        DirectoryUser(id: 'u2', username: 'ugo', displayName: 'Ugo'),
      ];
    teams = RecordingTeams()..answers[#teams] = () async => const [team];
    cubit = ProjectsCubit(projects: projects, users: users, teams: teams);
  });
  tearDown(() => cubit.close());

  test('loads the projects, the archive, the people and my teams', () async {
    projects.answers[#projects] = () async {
      final archive =
          projects.calls.last.namedArguments[#archived] as bool? ?? false;
      return archive ? const [archived] : const [running];
    };

    await cubit.load();

    final data = cubit.state.data!;
    expect(data.active, [running]);
    expect(data.archived, [archived]);
    expect(data.names, {'u1': 'Uma', 'u2': 'Ugo'});
    // Only people with a picture have one in the map.
    expect(data.avatars, {'u1': 'https://example.org/u1.png'});
    expect(data.teams, [team]);
  });

  test('a failed load keeps the server\'s message', () async {
    teams.answers[#teams] = () async => throw ApiFailure('errors.forbidden');

    await cubit.load();

    expect(cubit.state.data, isNull);
    expect(cubit.state.errorKey, 'errors.forbidden');
  });

  test('creates a project as the modal filled it in', () async {
    const created = Project(id: 'p3', key: 'NEW', name: 'New');
    projects.answers[#createProject] = () async => created;

    final answer = await cubit.createProject(
      key: 'NEW',
      name: 'New',
      description: 'About',
      color: '#ffaa00',
      leadId: 'u1',
      deadlineBasis: RelativeDateBasis.calendar,
    );

    expect(answer, created);
    expect(projects.callTo(#createProject).namedArguments, {
      #key: 'NEW',
      #name: 'New',
      #description: 'About',
      #color: '#ffaa00',
      #leadId: 'u1',
      #deadlineBasis: RelativeDateBasis.calendar,
    });
  });

  test('uploads the picture to the new project', () async {
    projects.answers[#uploadProjectAvatar] = () async => 'https://x/a.png?v=1';
    final file = MultipartFile.fromBytes(const [1, 2, 3], filename: 'a.png');

    expect(await cubit.uploadAvatar('p3', file), 'https://x/a.png?v=1');
    expect(projects.callTo(#uploadProjectAvatar).positionalArguments, [
      'p3',
      file,
    ]);
  });

  test('passes a refused creation on', () async {
    projects.answers[#createProject] = () async =>
        throw ApiFailure('projects.keyTaken');

    await expectLater(
      cubit.createProject(key: 'NEW', name: 'New'),
      throwsA(isA<ApiFailure>()),
    );
  });
}
