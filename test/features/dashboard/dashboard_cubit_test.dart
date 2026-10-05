import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/content_models.dart';
import 'package:hinata/core/models/team_models.dart' show Team;
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/dashboard/dashboard_cubit.dart';

import '../../support/recording_fake.dart';

/// The dashboard previews unsaved personalisation while it is edited: every
/// load asks the page which prefs, if any, it previews right now.
void main() {
  late FakeDashboardRepository dashboard;
  late FakeProjectRepository projects;
  late FakeTeamRepository teams;
  late DashboardCubit cubit;

  setUp(() {
    dashboard = FakeDashboardRepository();
    projects = FakeProjectRepository();
    teams = FakeTeamRepository();
    cubit = DashboardCubit(dashboard, projects, teams);
    // The payload is not what is under test here; its absence is reported the
    // way the page shows it.
    dashboard.fail(#dashboard, failure);
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
    projects.answer<List<Project>>(#projects, projectList);
    teams.answer<List<Team>>(#teams, teamList);

    final data = await cubit.pickerData();

    expect(data.projects, same(projectList));
    expect(data.teams, same(teamList));
  });

  test('without projects the teams are not asked', () async {
    projects.fail(#projects, failure);

    await expectLater(cubit.pickerData(), throwsA(same(failure)));
    expect(teams.calls, isEmpty);
  });

  test('saving sends the draft and passes a failure back', () async {
    const draft = DashboardPrefs(projectIds: ['p1']);
    dashboard.fail(#saveDashboardPrefs, failure);

    await expectLater(cubit.savePrefs(draft), throwsA(same(failure)));
    expect(dashboard.only.positionalArguments, [same(draft)]);
  });
}
