import 'package:bloc/bloc.dart';

import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';

/// The reads behind the overview of every board: the boards, the projects
/// they can be filtered by, and the teams that decide who may manage them.
///
/// Holds no state: the overview keeps its own lists, loading flag and error.
/// Failures pass through as the repository's `ApiFailure`.
class BoardListCubit extends Cubit<void> {
  BoardListCubit({
    required BoardRepository boards,
    required ProjectRepository projects,
    required TeamRepository teams,
  }) : _boards = boards,
       _projects = projects,
       _teams = teams,
       super(null);

  final BoardRepository _boards;
  final ProjectRepository _projects;
  final TeamRepository _teams;

  Future<List<Project>> projects() => _projects.projects();

  /// The boards, of the project [projectId] only when one is given.
  Future<List<AgileBoard>> boards({String? projectId}) =>
      _boards.boards(projectId: projectId);

  Future<List<Team>> teams() => _teams.teams();
}
