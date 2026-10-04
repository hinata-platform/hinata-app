import 'package:dio/dio.dart' show MultipartFile;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';

/// The add-project modal's requests: attaching projects the team does not own
/// yet, or creating one that belongs to it from the start.
///
/// The modal keeps its draft, busy flag and error text itself, as it did
/// before; this only stands between it and the repositories. Every method
/// answers what the repository answered and throws what it threw.
class TeamProjectCubit extends Cubit<void> {
  TeamProjectCubit({
    required TeamRepository teams,
    required ProjectRepository projects,
  }) : _teams = teams,
       _projects = projects,
       super(null);

  final TeamRepository _teams;
  final ProjectRepository _projects;

  Future<Team> attach(String teamId, List<String> projectIds) =>
      _teams.attachTeamProjects(teamId, projectIds);

  Future<Project> create(
    String teamId, {
    required String key,
    required String name,
    String? description,
    String? color,
    String? leadId,
    RelativeDateBasis? deadlineBasis,
  }) => _teams.createTeamProject(
    teamId,
    key: key,
    name: name,
    description: description,
    color: color,
    leadId: leadId,
    deadlineBasis: deadlineBasis,
  );

  /// Uploads the picture picked before the project existed.
  Future<String> uploadProjectAvatar(String projectId, MultipartFile file) =>
      _projects.uploadProjectAvatar(projectId, file);
}
