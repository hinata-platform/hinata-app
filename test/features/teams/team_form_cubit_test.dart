import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/features/teams/team_form_cubit.dart';

import '../projects/repository_recorders.dart';

/// The create- and edit-team modal's cubit.
void main() {
  late RecordingTeams teams;
  late TeamFormCubit cubit;

  const team = Team(id: 't1', key: 'OPS', name: 'Ops');

  setUp(() {
    teams = RecordingTeams();
    cubit = TeamFormCubit(teams);
  });
  tearDown(() => cubit.close());

  test('creates a team as the form filled it in', () async {
    teams.answers[#createTeam] = () async => team;

    final answer = await cubit.create(
      name: 'Ops',
      key: 'OPS',
      description: 'Keeps things running',
      colorHue: 210,
      icon: 'wrench',
    );

    expect(answer, team);
    expect(teams.callTo(#createTeam).namedArguments, {
      #name: 'Ops',
      #key: 'OPS',
      #description: 'Keeps things running',
      #colorHue: 210,
      #icon: 'wrench',
    });
  });

  test('writes the edited fields', () async {
    teams.answers[#updateTeam] = () async => team;
    final patch = <String, dynamic>{'name': 'Ops', 'colorHue': 30};

    expect(await cubit.update('t1', patch), team);
    expect(teams.callTo(#updateTeam).positionalArguments, ['t1', patch]);
  });

  test('passes a taken key on', () async {
    teams.answers[#createTeam] = () async => throw ApiFailure('teams.keyTaken');

    await expectLater(
      cubit.create(name: 'Ops', key: 'OPS', colorHue: 0, icon: 'users'),
      throwsA(
        isA<ApiFailure>().having((f) => f.message, 'message', 'teams.keyTaken'),
      ),
    );
  });

  test('uploads and removes the picture', () async {
    teams
      ..answers[#uploadTeamAvatar] = (() async => 'https://x/t1.png?v=1')
      ..answers[#deleteTeamAvatar] = () async {};
    final file = MultipartFile.fromBytes(const [1], filename: 't.png');

    expect(await cubit.uploadAvatar('t1', file), 'https://x/t1.png?v=1');
    await cubit.removeAvatar('t1');

    expect(teams.callTo(#uploadTeamAvatar).positionalArguments, ['t1', file]);
    expect(teams.callTo(#deleteTeamAvatar).positionalArguments, ['t1']);
  });
}
