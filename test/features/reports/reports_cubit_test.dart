import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/content_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/reports/reports_cubit.dart';

import '../projects/repository_recorders.dart';

/// The reports page's cubit: each request sent as the page asked, each answer
/// and failure handed back unchanged.
void main() {
  late RecordingProjects projects;
  late RecordingUsers users;
  late RecordingDashboard dashboard;
  late RecordingMeta meta;
  late ReportsCubit cubit;

  setUp(() {
    projects = RecordingProjects();
    users = RecordingUsers();
    dashboard = RecordingDashboard();
    meta = RecordingMeta();
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
    projects.answers[#projects] = () async => const [project];
    users.answers[#users] = () async => const [uma];

    final answer = await cubit.projectsAndUsers();

    expect(answer.projects, [project]);
    expect(answer.users, [uma]);
  });

  test('a failed read passes the failure on', () async {
    projects.answers[#projects] = () async => const <Project>[];
    users.answers[#users] = () async => throw ApiFailure('errors.forbidden');

    await expectLater(cubit.projectsAndUsers(), throwsA(isA<ApiFailure>()));
  });

  test('asks one report with its query', () async {
    dashboard.answers[#report] = () async => const {'OPEN': 4};
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
    dashboard.answers[#createdVsResolved] = () async => points;

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
      ..answers[#meta] = (() async => server)
      ..answers[#organizationLogo] = () async =>
          (bytes: const [1, 2], isSvg: false);

    expect(await cubit.meta(), server);
    final logo = await cubit.organizationLogo();
    expect(logo?.bytes, [1, 2]);
    expect(logo?.isSvg, isFalse);
  });

  test('no logo is null, not a failure', () async {
    meta.answers[#organizationLogo] = () async => null;

    expect(await cubit.organizationLogo(), isNull);
  });
}
