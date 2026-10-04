import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/features/time/reports/report_filter_cubit.dart';

import '../recording_repository.dart';

/// The filter sheet's team list comes through this cubit as the repository
/// answered it, refusal included.
void main() {
  const team = Team(id: 't1', key: 'OPS', name: 'Operations');

  test('reads the teams', () async {
    final teams = _FakeTeams()..answers[#teams] = Future.value([team]);
    final cubit = ReportFilterCubit(teams);
    addTearDown(cubit.close);

    expect(await cubit.teams(), [team]);
    expect(teams.calls.single, invoked(#teams));
  });

  test('passes a refusal through', () async {
    final cubit = ReportFilterCubit(_FakeTeams()..failure = refusal);
    addTearDown(cubit.close);

    await expectLater(cubit.teams, throwsRefusal);
  });
}

class _FakeTeams with RecordingRepository implements TeamRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
