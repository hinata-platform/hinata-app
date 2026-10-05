import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/features/teams/teams_cubit.dart';

import '../../support/recording_fake.dart';

/// The team list's cubit: the teams and the people on their cards, in one load.
void main() {
  late FakeTeamRepository teams;
  late FakeUserRepository users;
  late TeamsCubit cubit;

  const team = Team(id: 't1', key: 'OPS', name: 'Ops');

  setUp(() {
    teams = FakeTeamRepository()..answer(#teams, const [team]);
    users = FakeUserRepository()
      ..answer(#users, const [
        DirectoryUser(
          id: 'u1',
          username: 'uma',
          displayName: 'Uma',
          avatarUrl: 'https://example.org/u1.png',
        ),
        DirectoryUser(id: 'u2', username: 'ugo', displayName: 'Ugo'),
      ]);
    cubit = TeamsCubit(teams: teams, users: users);
  });
  tearDown(() => cubit.close());

  test('loads the teams with names and pictures', () async {
    await cubit.load();

    final data = cubit.state.data!;
    expect(data.teams, [team]);
    expect(data.names, {'u1': 'Uma', 'u2': 'Ugo'});
    expect(data.avatars, {'u1': 'https://example.org/u1.png'});
  });

  test('a failed load keeps the server\'s message', () async {
    users.fail(#users, ApiFailure('errors.forbidden'));

    await cubit.load();

    expect(cubit.state.data, isNull);
    expect(cubit.state.errorKey, 'errors.forbidden');
  });
}
