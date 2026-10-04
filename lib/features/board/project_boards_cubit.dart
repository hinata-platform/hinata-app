import '../../core/access/project_permissions.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';

/// What a project's list of boards shows.
typedef ProjectBoardsData = ({
  String projectName,
  List<AgileBoard> boards,
  bool canManageProject,
});

/// The boards of the project [projectId], its name, and whether the person
/// signed in may manage every board of it.
///
/// [me] is asked at every read, so a read after signing in again judges the
/// person signed in then.
class ProjectBoardsCubit extends FetchCubit<ProjectBoardsData> {
  ProjectBoardsCubit({
    required BoardRepository boards,
    required ProjectRepository projects,
    required TeamRepository teams,
    required String projectId,
    required AuthUser? Function() me,
  }) : super(() async {
         final user = me();
         final results = await Future.wait([
           boards.boards(projectId: projectId),
           projects.project(projectId),
           teams.teams(),
         ]);
         final project = results[1] as Project;
         return (
           projectName: project.name,
           boards: results[0] as List<AgileBoard>,
           // Project leads and Team-Admins of an owning team may manage every
           // board of this project; the board owner is handled per-card. The
           // platform admin role adds nothing.
           canManageProject: canManageProject(
             project,
             user,
             results[2] as List<Team>,
           ),
         );
       });
}
