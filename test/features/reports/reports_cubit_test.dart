import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/content_models.dart';
import 'package:hinata/core/models/core_models.dart';
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

  test('reads the projects and the people together', () async {
    const project = Project(id: 'p1', key: 'KULT', name: 'Kultur');
    const uma = DirectoryUser(id: 'u1', username: 'uma', displayName: 'Uma');
    projects.answer(#projects, const [project]);
    users.answer(#users, const [uma]);

    final answer = await cubit.projectsAndUsers();

    expect(answer.projects, [project]);
    expect(answer.users, [uma]);
  });

  test('a failed read passes the failure on', () async {
    projects.answer(#projects, const <Project>[]);
    users.fail(#users, ApiFailure('errors.forbidden'));

    await expectLater(cubit.projectsAndUsers(), throwsA(isA<ApiFailure>()));
  });

  test('asks one report with its query', () async {
    dashboard.answer(#report, const {'OPEN': 4});
    final query = <String, dynamic>{'projectId': 'p1'};

    expect(await cubit.report('issues-by-state', query), {'OPEN': 4});
    expect(dashboard.callTo(#report).positionalArguments, [
      'issues-by-state',
      query,
    ]);
  });

  test('asks the trend over the given days', () async {
    final points = [
      TrendPoint(date: DateTime(2026, 10, 1), created: 2, resolved: 1),
    ];
    dashboard.answer(#createdVsResolved, points);

    expect(await cubit.createdVsResolved('p1', days: 30), points);
    final call = dashboard.callTo(#createdVsResolved);
    expect(call.positionalArguments, ['p1']);
    expect(call.namedArguments, {#days: 30});
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
