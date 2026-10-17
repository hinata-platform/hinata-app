import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/report_overview_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/reports/reports_cubit.dart';

import '../../support/recording_fake.dart';

/// The reports page's cubit: each request sent as the page asked, each answer
/// and failure handed back unchanged.
void main() {
  late FakeProjectRepository projects;
  late FakeUserRepository users;
  late FakeDashboardRepository dashboard;
  late FakeMetaRepository meta;
  late ReportsCubit cubit;

  setUp(() {
    projects = FakeProjectRepository();
    users = FakeUserRepository();
    dashboard = FakeDashboardRepository();
    meta = FakeMetaRepository();
    cubit = ReportsCubit(
      projects: projects,
      users: users,
      dashboard: dashboard,
      meta: meta,
    );
  });
  tearDown(() => cubit.close());

  test('opens on the project the link names', () async {
    const project = Project(id: 'p1', key: 'KULT', name: 'Kultur');
    projects.answer<Project>(#project, project);

    expect(await cubit.project('p1'), project);
    expect(projects.callTo(#project).positionalArguments, ['p1']);
  });

  test(
    'without a link, on the first project, asked as a page of one',
    () async {
      const project = Project(id: 'p1', key: 'KULT', name: 'Kultur');
      projects.answer<({List<Project> projects, int total})>(#searchProjects, (
        projects: const [project],
        total: 7,
      ));

      expect(await cubit.project(null), project);
      expect(projects.callTo(#searchProjects).namedArguments[#size], 1);
    },
  );

  test('no project at all is null, not a failure', () async {
    projects.answer<({List<Project> projects, int total})>(#searchProjects, (
      projects: const <Project>[],
      total: 0,
    ));

    expect(await cubit.project(null), isNull);
  });

  test('asks the overview over the given days', () async {
    const overview = ReportOverview(projectId: 'p1', days: 90);
    dashboard.answer(#overview, overview);

    expect(await cubit.overview('p1', days: 90), overview);
    final call = dashboard.callTo(#overview);
    expect(call.positionalArguments, ['p1']);
    expect(call.namedArguments, {#days: 90});
  });

  test('names only the people asked for, and passes a failure on', () async {
    const uma = DirectoryUser(id: 'u1', username: 'uma', displayName: 'Uma');
    users.answer(#usersByIds, const [uma]);

    expect(await cubit.usersByIds(['u1']), [uma]);
    expect(users.callTo(#usersByIds).positionalArguments, [
      ['u1'],
    ]);

    users.fail(#usersByIds, ApiFailure('errors.forbidden'));
    await expectLater(cubit.usersByIds(['u1']), throwsA(isA<ApiFailure>()));
  });

  test('reads the meta and the logo for a PDF', () async {
    const server = ServerMeta(
      serverVersion: '1.0.0',
      minAppVersion: '1.0.0',
      setupCompleted: true,
    );
    meta
      ..answer(#meta, server)
      ..answer(#organizationLogo, (bytes: const [1, 2], isSvg: false));

    expect(await cubit.meta(), server);
    final logo = await cubit.organizationLogo();
    expect(logo?.bytes, [1, 2]);
    expect(logo?.isSvg, isFalse);
  });

  test('no logo is null, not a failure', () async {
    meta.answer(#organizationLogo, null);

    expect(await cubit.organizationLogo(), isNull);
  });
}
