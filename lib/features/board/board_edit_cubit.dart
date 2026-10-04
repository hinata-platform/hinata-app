import 'package:bloc/bloc.dart';

import '../../core/models/work_models.dart';
import '../../core/repositories/board_repository.dart';

/// The changes made to a board as a whole: creating it, renaming it and
/// changing the projects it spans.
///
/// Holds no state: the dialogs keep their own busy flag and error. Each change
/// announces itself on `BoardEvents` from the repository, and failures pass
/// through as the repository's `ApiFailure`.
class BoardEditCubit extends Cubit<void> {
  BoardEditCubit(this._boards) : super(null);

  final BoardRepository _boards;

  Future<AgileBoard> create(
    String name,
    List<String> projectIds, {
    BoardType type = BoardType.kanban,
  }) => _boards.createBoard(name, projectIds, type: type);

  Future<AgileBoard> rename(String boardId, String name) =>
      _boards.renameBoard(boardId, name);

  Future<AgileBoard> updateProjects(String boardId, List<String> projectIds) =>
      _boards.updateBoardProjects(boardId, projectIds);
}
