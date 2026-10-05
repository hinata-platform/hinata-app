import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/project_template_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/projects/settings/project_settings_cubit.dart';

import '../../support/recording_fake.dart';

/// The settings page's cubit: the load that opens the page, and each write the
/// page makes, sent as the page asked and answered as the server answered.
void main() {
  late FakeProjectRepository projects;
  late FakeUserRepository users;
  late FakeTeamRepository teams;
  late ProjectSettingsCubit cubit;

  const project = Project(id: 'p1', key: 'KULT', name: 'Kultur');

  setUp(() {
    projects = FakeProjectRepository();
    users = FakeUserRepository();
    teams = FakeTeamRepository();
    cubit = ProjectSettingsCubit(
      projectId: 'p1',
      projects: projects,
      users: users,
      teams: teams,
    );
  });
  tearDown(() => cubit.close());

  test('loads the project, the people, the usage and my teams', () async {
    const uma = DirectoryUser(id: 'u1', username: 'uma', displayName: 'Uma');
    const team = Team(id: 't1', key: 'OPS', name: 'Ops');
    projects
      ..answer(#project, project)
      ..answer(#projectStateUsage, const {'Done': 2});
    users.answer(#users, const [uma]);
    teams.answer(#teams, const [team]);

    final data = await cubit.load();

    expect(data.project, project);
    expect(data.users, [uma]);
    expect(data.stateUsage, {'Done': 2});
    expect(data.teams, [team]);
    expect(projects.callTo(#project).positionalArguments, ['p1']);
    expect(projects.callTo(#projectStateUsage).positionalArguments, ['p1']);
  });

  test('a failed load passes the failure on', () async {
    projects
      ..fail(#project, ApiFailure('errors.notFound'))
      ..answer(#projectStateUsage, const <String, int>{});
    users.answer(#users, const <DirectoryUser>[]);
    teams.answer(#teams, const <Team>[]);

    await expectLater(cubit.load(), throwsA(isA<ApiFailure>()));
  });

  test(
    'writes the patch and reads the usage of the project it names',
    () async {
      projects
        ..answer(#updateProject, project)
        ..answer(#projectStateUsage, const {'Open': 1});

      expect(await cubit.update('p1', const {'name': 'Kultur'}), project);
      expect(await cubit.stateUsage('p1'), {'Open': 1});
      expect(projects.callTo(#updateProject).positionalArguments, [
        'p1',
        {'name': 'Kultur'},
      ]);
      expect(projects.callTo(#projectStateUsage).positionalArguments, ['p1']);
    },
  );

  test('previews and applies the event date', () async {
    const preview = SchedulePreview(moved: 3);
    const result = ScheduleResult(project: project, deadlinesMoved: 3);
    projects
      ..answer(#previewSchedule, preview)
      ..answer(#applySchedule, result);
    final date = DateTime(2026, 11, 7);

    expect(
      await cubit.previewSchedule('p1', eventDate: date, limit: 8),
      preview,
    );
    expect(await cubit.applySchedule('p1', eventDate: date), result);

    final asked = projects.callTo(#previewSchedule);
    expect(asked.positionalArguments, ['p1']);
    expect(asked.namedArguments, {#eventDate: date, #limit: 8});
    final applied = projects.callTo(#applySchedule);
    expect(applied.positionalArguments, ['p1']);
    expect(applied.namedArguments, {#eventDate: date});
  });

  test('clearing the date applies null', () async {
    projects.answer(#applySchedule, const ScheduleResult(project: project));

    await cubit.applySchedule('p1');

    expect(projects.callTo(#applySchedule).namedArguments, {#eventDate: null});
  });

  test('uploads and removes the picture of the route\'s project', () async {
    projects
      ..answer(#uploadProjectAvatar, 'https://x/p1.png?v=2')
      ..answer<void>(#deleteProjectAvatar, null);
    final file = MultipartFile.fromBytes(const [1], filename: 'p.png');

    expect(await cubit.uploadAvatar(file), 'https://x/p1.png?v=2');
    await cubit.removeAvatar();

    expect(projects.callTo(#uploadProjectAvatar).positionalArguments, [
      'p1',
      file,
    ]);
    expect(projects.callTo(#deleteProjectAvatar).positionalArguments, ['p1']);
  });
}
