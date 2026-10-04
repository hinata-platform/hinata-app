import 'package:bloc/bloc.dart';

import '../../core/models/board_page_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/board_repository.dart';
import '../../core/repositories/project_repository.dart';

/// The reads and writes behind the column editor of the board [boardId].
///
/// Holds no state: the editor keeps its own draft, busy flag and error.
/// Failures pass through as the repository's `ApiFailure`.
class BoardColumnsEditorCubit extends Cubit<void> {
  BoardColumnsEditorCubit({
    required BoardRepository boards,
    required ProjectRepository projects,
    required this.boardId,
  }) : _boards = boards,
       _projects = projects,
       super(null);

  final BoardRepository _boards;
  final ProjectRepository _projects;
  final String boardId;

  /// The board's columns as the wall has them, without cards: the editor
  /// arranges columns and never shows what is in them.
  Future<BoardWallPage> layout() => _boards.wall(boardId, size: 0);

  /// The projects behind [ids], whose states the columns are made of.
  Future<List<Project>> projects(List<String> ids) =>
      _projects.resolveProjects(ids);

  /// Stores [columns] as the board's own layout.
  Future<AgileBoard> save(List<BoardColumnLayout> columns) =>
      _boards.updateBoardColumns(boardId, columns);

  /// Drops the hand-made layout, back to the automatic merge.
  Future<AgileBoard> reset() => _boards.resetBoardColumns(boardId);
}
