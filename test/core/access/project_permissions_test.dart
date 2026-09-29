import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/access/project_permissions.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';

/// Who may manage a project, mirrored from the server: leads, and Team-Admins
/// of a team owning it. The platform admin role opens nothing.
void main() {
  AuthUser user(String id, {Set<String> roles = const {'USER'}}) => AuthUser(
    id: id,
    email: '$id@example.org',
    username: id,
    displayName: id,
    roles: roles,
  );

  const project = Project(
    id: 'p1',
    key: 'FEST',
    name: 'Sommerfest',
    leadIds: ['lead'],
  );

  Team team({
    String id = 't1',
    List<String> projectIds = const ['p1'],
    required List<TeamMembership> members,
  }) => Team(
    id: id,
    key: 'KULT',
    name: 'Kultur',
    projectIds: projectIds,
    members: members,
  );

  test('a lead manages the project and is its lead', () {
    final me = user('lead');
    expect(canManageProject(project, me, const []), isTrue);
    expect(isProjectLead(project, me), isTrue);
  });

  test('a Team-Admin of an owning team manages it but does not lead it', () {
    final me = user('ta');
    final teams = [
      team(
        members: const [TeamMembership(userId: 'ta', role: TeamRole.admin)],
      ),
    ];
    expect(canManageProject(project, me, teams), isTrue);
    expect(isProjectLead(project, me), isFalse);
  });

  test('a plain member of the owning team does not manage it', () {
    final me = user('member');
    final teams = [
      team(members: const [TeamMembership(userId: 'member')]),
    ];
    expect(canManageProject(project, me, teams), isFalse);
  });

  test('a Team-Admin of a team that does not own the project gets nothing', () {
    final me = user('ta');
    final teams = [
      team(
        projectIds: const ['other'],
        members: const [TeamMembership(userId: 'ta', role: TeamRole.admin)],
      ),
    ];
    expect(canManageProject(project, me, teams), isFalse);
  });

  test('a platform admin without membership gets nothing', () {
    final me = user('boss', roles: const {'USER', 'ADMIN', 'ORG_ADMIN'});
    expect(canManageProject(project, me, const []), isFalse);
    expect(isProjectLead(project, me), isFalse);
  });

  test('nobody signed in manages nothing', () {
    expect(canManageProject(project, null, const []), isFalse);
    expect(isProjectLead(project, null), isFalse);
  });
}
