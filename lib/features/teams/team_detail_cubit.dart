import 'package:dio/dio.dart' show MultipartFile;

import '../../core/blocs/fetch_cubit.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/user_repository.dart';

/// Bundles everything the detail tabs need in one fetch (team + directory +
/// projects + activity), so the panels render without further round-trips.
typedef TeamDetailData = ({
  Team team,
  Map<String, DirectoryUser> usersById,
  Map<String, Project> projectsById,
  List<TeamActivity> activity,
  int activityTotal,
});

/// One team's page: the bundle its tabs render, and the writes the tabs make
/// in place (the modals have cubits of their own).
///
/// The writes answer what the repository answered and throw what it threw; the
/// tab that asked reloads the bundle and says what went wrong.
class TeamDetailCubit extends FetchCubit<TeamDetailData> {
  TeamDetailCubit({
    required String teamId,
    required TeamRepository teams,
    required UserRepository users,
    required ProjectRepository projects,
  }) : _teams = teams,
       super(() => _read(teamId, teams, users, projects));

  final TeamRepository _teams;

  static Future<TeamDetailData> _read(
    String teamId,
    TeamRepository teamRepository,
    UserRepository userRepository,
    ProjectRepository projectRepository,
  ) async {
    final results = await Future.wait([
      teamRepository.team(teamId),
      userRepository.users(),
      projectRepository.projects(),
      teamRepository.teamActivityPage(teamId),
    ]);
    final team = results[0] as Team;
    final users = results[1] as List<DirectoryUser>;
    final projects = results[2] as List<Project>;
    final activity = results[3] as ({List<TeamActivity> items, int total});
    return (
      team: team,
      usersById: {for (final u in users) u.id: u},
      projectsById: {for (final p in projects) p.id: p},
      activity: activity.items,
      activityTotal: activity.total,
    );
  }

  /// An older page of the team's activity; the bundle carries page 0.
  Future<({List<TeamActivity> items, int total})> activityPage(
    String teamId, {
    required int page,
  }) => _teams.teamActivityPage(teamId, page: page);

  /// Takes a project off the team; the project itself stays.
  Future<Team> detachProject(String teamId, String projectId) =>
      _teams.detachTeamProject(teamId, projectId);

  Future<String> uploadAvatar(String teamId, MultipartFile file) =>
      _teams.uploadTeamAvatar(teamId, file);

  Future<void> removeAvatar(String teamId) => _teams.deleteTeamAvatar(teamId);
}
