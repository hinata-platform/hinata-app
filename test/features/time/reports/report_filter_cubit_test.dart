import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/features/time/reports/report_filter_cubit.dart';

import '../../../support/recording_fake.dart';

/// The filter sheet's team list comes through this cubit as the repository
/// answered it, failure included.
void main() {
  const team = Team(id: 't1', key: 'OPS', name: 'Operations');

  test('reads the teams', () async {
    final teams = FakeTeamRepository()..answer(#teams, [team]);
    final cubit = ReportFilterCubit(teams);
    addTearDown(cubit.close);

    expect(await cubit.teams(), [team]);
    expect(teams.calls.single, invoked(#teams));
  });

  test('passes a failure through', () async {
    final cubit = ReportFilterCubit(
      FakeTeamRepository()..fail(#teams, failure),
    );
    addTearDown(cubit.close);

    await expectLater(cubit.teams, throwsFailure);
  });
}
