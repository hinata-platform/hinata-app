import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/features/teams/team_members_cubit.dart';

import '../../support/recording_fake.dart';

/// The member modals' cubit: the directory search, adding people, and
/// changing or ending one membership.
void main() {
  late FakeTeamRepository teams;
  late FakeUserRepository users;
  late TeamMembersCubit cubit;

  const team = Team(id: 't1', key: 'OPS', name: 'Ops');

  setUp(() {
    teams = FakeTeamRepository();
    users = FakeUserRepository();
    cubit = TeamMembersCubit(teams: teams, users: users);
  });
  tearDown(() => cubit.close());

  test('searches the directory a page at a time', () async {
    const uma = DirectoryUser(id: 'u1', username: 'uma', displayName: 'Uma');
    users.answer(#searchUsers, (items: const [uma], total: 1));

    final answer = await cubit.searchUsers('um', size: 25);

    expect(answer.items, [uma]);
    expect(answer.total, 1);
    final call = users.callTo(#searchUsers);
    expect(call.positionalArguments, ['um']);
    expect(call.namedArguments[#size], 25);
  });

  test('adds people with one role and grant', () async {
    teams.answer(#addTeamMembers, team);
    final knowledge = KnowledgeAccess.some(const ['a1']);

    final answer = await cubit.addMembers(
      't1',
      ['u1', 'u2'],
      role: TeamRole.member,
      access: const ProjectAccess.all(),
      knowledge: knowledge,
    );

    expect(answer, team);
    final call = teams.callTo(#addTeamMembers);
    expect(call.positionalArguments, [
      't1',
      ['u1', 'u2'],
    ]);
    expect(call.namedArguments, {
      #role: TeamRole.member,
      #access: const ProjectAccess.all(),
      #knowledge: knowledge,
    });
  });

  test('changes a membership, leaving knowledge alone when asked', () async {
    teams.answer(#updateTeamMembership, team);

    await cubit.updateMembership(
      't1',
      'u1',
      role: TeamRole.admin,
      access: const ProjectAccess.none(),
    );

    final call = teams.callTo(#updateTeamMembership);
    expect(call.positionalArguments, ['t1', 'u1']);
    expect(call.namedArguments, {
      #role: TeamRole.admin,
      #access: const ProjectAccess.none(),
      #knowledge: null,
    });
  });

  test('removes a member and passes a failure on', () async {
    teams.fail(#removeTeamMember, ApiFailure('teams.lastAdmin'));

    await expectLater(
      cubit.removeMember('t1', 'u1'),
      throwsA(isA<ApiFailure>()),
    );
    expect(teams.callTo(#removeTeamMember).positionalArguments, ['t1', 'u1']);
  });
}
