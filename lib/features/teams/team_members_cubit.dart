import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/user_repository.dart';

/// The member modals' requests: the directory search that offers people to
/// add, adding them, and changing or ending one membership.
///
/// The modals keep their picks, busy flags and error texts themselves, as they
/// did before; this only stands between them and the repositories. Every
/// method answers what the repository answered and throws what it threw.
class TeamMembersCubit extends Cubit<void> {
  TeamMembersCubit({
    required TeamRepository teams,
    required UserRepository users,
  }) : _teams = teams,
       _users = users,
       super(null);

  final TeamRepository _teams;
  final UserRepository _users;

  /// One page of the directory matching [query].
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    required int size,
  }) => _users.searchUsers(query, size: size);

  Future<Team> addMembers(
    String teamId,
    List<String> userIds, {
    required TeamRole role,
    required ProjectAccess access,
    required KnowledgeAccess knowledge,
  }) => _teams.addTeamMembers(
    teamId,
    userIds,
    role: role,
    access: access,
    knowledge: knowledge,
  );

  /// Changes one membership. A null [knowledge] keeps what is stored.
  Future<Team> updateMembership(
    String teamId,
    String userId, {
    required TeamRole role,
    required ProjectAccess access,
    KnowledgeAccess? knowledge,
  }) => _teams.updateTeamMembership(
    teamId,
    userId,
    role: role,
    access: access,
    knowledge: knowledge,
  );

  Future<Team> removeMember(String teamId, String userId) =>
      _teams.removeTeamMember(teamId, userId);
}
