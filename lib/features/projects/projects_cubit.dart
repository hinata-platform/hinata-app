import 'package:dio/dio.dart' show MultipartFile;

import '../../core/blocs/fetch_cubit.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/user_repository.dart';

/// What the project list shows: the running projects (templates among them),
/// the archive, the names and pictures of the people on the cards, and the
/// teams I am in.
typedef ProjectsData = ({
  List<Project> active,
  List<Project> archived,
  Map<String, String> names,
  Map<String, String> avatars,
  List<Team> teams,
});

/// The project list, and the "new project" modal it opens.
class ProjectsCubit extends FetchCubit<ProjectsData> {
  ProjectsCubit({
    required ProjectRepository projects,
    required UserRepository users,
    required TeamRepository teams,
  }) : _projects = projects,
       super(() => _read(projects, users, teams));

  final ProjectRepository _projects;

  static Future<ProjectsData> _read(
    ProjectRepository projects,
    UserRepository users,
    TeamRepository teams,
  ) async {
    final results = await Future.wait([
      projects.projects(),
      projects.projects(archived: true),
      users.users(),
      // The teams I am in, once per load: a Team-Admin of a team owning a
      // project may open its settings, and the cards ask that of this list
      // rather than each asking the server.
      teams.teams(),
    ]);
    final active = results[0] as List<Project>;
    final archived = results[1] as List<Project>;
    final people = results[2] as List<DirectoryUser>;
    final mine = results[3] as List<Team>;
    final names = {for (final u in people) u.id: u.displayName};
    final avatars = {
      for (final u in people)
        if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty) u.id: u.avatarUrl!,
    };
    return (
      active: active,
      archived: archived,
      names: names,
      avatars: avatars,
      teams: mine,
    );
  }

  /// Creates a project as the modal filled it in. Answers what the server
  /// created and throws what it threw; the modal reloads the list on close.
  Future<Project> createProject({
    required String key,
    required String name,
    String? description,
    String? color,
    String? leadId,
    RelativeDateBasis? deadlineBasis,
  }) => _projects.createProject(
    key: key,
    name: name,
    description: description,
    color: color,
    leadId: leadId,
    deadlineBasis: deadlineBasis,
  );

  /// Uploads the picture picked before the project existed.
  Future<String> uploadAvatar(String projectId, MultipartFile file) =>
      _projects.uploadProjectAvatar(projectId, file);
}
