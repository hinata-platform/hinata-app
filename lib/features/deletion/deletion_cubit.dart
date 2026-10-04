import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/deletion_models.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';

/// What the cascading-delete flow asks of the server: what a delete would
/// touch, and the delete itself as a stream of progress frames.
///
/// Holds no state: the flow keeps its stage, the choice for a project's issues
/// and the progress it reads from the stream, as before. Failures pass through
/// untouched.
class DeletionCubit extends Cubit<void> {
  DeletionCubit({
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

  Future<BoardDeletionImpact> boardImpact(String boardId) =>
      _boards.boardDeletionImpact(boardId);

  Future<Stream<List<int>>> deleteBoard(
    String boardId, {
    CancelToken? cancelToken,
  }) => _boards.boardDeleteStream(boardId, cancelToken: cancelToken);

  Future<ProjectDeletionImpact> projectImpact(String projectId) =>
      _projects.projectDeletionImpact(projectId);

  /// [strategy] and [migrateToProjectId] are needed only while the project
  /// still has issues.
  Future<Stream<List<int>>> deleteProject(
    String projectId, {
    IssueStrategy? strategy,
    String? migrateToProjectId,
    CancelToken? cancelToken,
  }) => _projects.projectDeleteStream(
    projectId,
    strategy: strategy,
    migrateToProjectId: migrateToProjectId,
    cancelToken: cancelToken,
  );

  Future<TeamDeletionImpact> teamImpact(String teamId) =>
      _teams.teamDeletionImpact(teamId);

  Future<Stream<List<int>>> deleteTeam(
    String teamId, {
    CancelToken? cancelToken,
  }) => _teams.teamDeleteStream(teamId, cancelToken: cancelToken);
}
