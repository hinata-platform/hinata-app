import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/core_models.dart';
import '../../../core/models/project_template_models.dart';
import '../../../core/models/team_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/project_repository.dart';
import '../../../core/repositories/team_repository.dart';
import '../../../core/repositories/user_repository.dart';

/// Everything the settings page reads before it can show a project.
typedef ProjectSettingsData = ({
  Project project,
  List<DirectoryUser> users,
  Map<String, int> stateUsage,
  List<Team> teams,
});

/// The requests of one project's settings page.
///
/// The page keeps its draft, its saved copy and its busy flags itself, as it
/// did before: a draft edited field by field behind a save bar is the page's
/// own business. This stands between the page and the repositories, and every
/// method answers what the repository answered and throws what it threw.
class ProjectSettingsCubit extends Cubit<void> {
  ProjectSettingsCubit({
    required this.projectId,
    required ProjectRepository projects,
    required UserRepository users,
    required TeamRepository teams,
  }) : _projects = projects,
       _users = users,
       _teams = teams,
       super(null);

  final String projectId;
  final ProjectRepository _projects;
  final UserRepository _users;
  final TeamRepository _teams;

  /// The project, the directory, the issue count per workflow state and the
  /// teams I am in, all at once.
  Future<ProjectSettingsData> load() async {
    final results = await Future.wait([
      _projects.project(projectId),
      _users.users(),
      _projects.projectStateUsage(projectId),
      // One list call: the teams I am in, membership scoped on the server.
      _teams.teams(),
    ]);
    return (
      project: results[0] as Project,
      users: results[1] as List<DirectoryUser>,
      stateUsage: results[2] as Map<String, int>,
      teams: results[3] as List<Team>,
    );
  }

  // The writes below name the project the page loaded rather than the one in
  // the route: the route may name it another way, and these always went to the
  // id the server answered with.

  /// Writes the draft's changed fields.
  Future<Project> update(String id, Map<String, dynamic> patch) =>
      _projects.updateProject(id, patch);

  /// The issue count per workflow state, read again after a save moved issues.
  Future<Map<String, int>> stateUsage(String id) =>
      _projects.projectStateUsage(id);

  /// What moving the event date to [eventDate] would do, without doing it.
  Future<SchedulePreview> previewSchedule(
    String id, {
    required DateTime eventDate,
    required int limit,
  }) => _projects.previewSchedule(id, eventDate: eventDate, limit: limit);

  /// Sets the event date, or takes it away with null.
  Future<ScheduleResult> applySchedule(String id, {DateTime? eventDate}) =>
      _projects.applySchedule(id, eventDate: eventDate);

  Future<String> uploadAvatar(MultipartFile file) =>
      _projects.uploadProjectAvatar(projectId, file);

  Future<void> removeAvatar() => _projects.deleteProjectAvatar(projectId);
}
