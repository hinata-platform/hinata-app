import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/content_models.dart';
import 'package:hinata/core/models/team_models.dart' show Team;
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/dashboard_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/features/dashboard/dashboard_cubit.dart';

import '../recording_fake.dart';

class _FakeDashboard with RecordingFake implements DashboardRepository {}

class _FakeProjects with RecordingFake implements ProjectRepository {}

class _FakeTeams with RecordingFake implements TeamRepository {}

/// The dashboard previews unsaved personalisation while it is edited: every
/// load asks the page which prefs, if any, it previews right now.
void main() {
  late _FakeDashboard dashboard;
  late _FakeProjects projects;
  late _FakeTeams teams;
  late DashboardCubit cubit;

  setUp(() {
    dashboard = _FakeDashboard();
    projects = _FakeProjects();
    teams = _FakeTeams();
    cubit = DashboardCubit(dashboard, projects, teams);
    // The payload is not what is under test here; its absence is reported the
    // way the page shows it.
    dashboard.answers[#dashboard] = () => Future<DashboardData>.error(failure);
  });
  tearDown(() => cubit.close());

  test('without a preview source the saved prefs are read', () async {
    await cubit.load();

    expect(dashboard.only.namedArguments, {#override: null});
    expect(cubit.state.errorKey, 'errors.test');
  });

  test('each load asks the page for the prefs it previews', () async {
    DashboardPrefs? preview;
    cubit.previewSource = () => preview;
    const draft = DashboardPrefs(boardId: 'b1', hiddenCards: ['git']);

    await cubit.load();
    preview = draft;
    await cubit.load();

    expect(dashboard.calls[0].namedArguments, {#override: null});
    expect(dashboard.calls[1].namedArguments, {#override: draft});
  });

  test('the pickers read projects, then teams', () async {
    final projectList = <Project>[];
    final teamList = <Team>[];
    projects.answers[#projects] = () =>
        Future<List<Project>>.value(projectList);
    teams.answers[#teams] = () => Future<List<Team>>.value(teamList);

    final data = await cubit.pickerData();

    expect(data.projects, same(projectList));
    expect(data.teams, same(teamList));
  });

  test('without projects the teams are not asked', () async {
    projects.answers[#projects] = () => Future<List<Project>>.error(failure);

    await expectLater(cubit.pickerData(), throwsA(same(failure)));
    expect(teams.calls, isEmpty);
  });

  test('saving sends the draft and passes a failure back', () async {
    const draft = DashboardPrefs(projectIds: ['p1']);
    dashboard.answers[#saveDashboardPrefs] = () =>
        Future<DashboardPrefs>.error(failure);

    await expectLater(cubit.savePrefs(draft), throwsA(same(failure)));
    expect(dashboard.only.positionalArguments, [same(draft)]);
  });
}
