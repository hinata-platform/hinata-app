import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/issue_move.dart';
import '../../core/repositories/issue_repository.dart';

/// Where the move wizard sends its analysis and the move itself.
///
/// Holds no state of its own: the wizard keeps the target, the preflight it
/// shows, the status mapping being edited and its busy and error state.
class IssueMoveCubit extends Cubit<void> {
  IssueMoveCubit(this._issues) : super(null);

  final IssueRepository _issues;

  /// What moving [issueIds] into [targetProjectId] would take: the statuses
  /// to map, with the server's suggestions, and what travels along.
  Future<MovePreflight> analyse(
    List<String> issueIds,
    String targetProjectId, {
    bool includeEpicChildren = false,
  }) => _issues.movePreflight(
    issueIds,
    targetProjectId,
    includeEpicChildren: includeEpicChildren,
  );

  /// Moves [issueIds] into [targetProjectId], each status re-pointed by
  /// [stateMap].
  Future<void> move(
    List<String> issueIds,
    String targetProjectId, {
    required Map<String, String> stateMap,
    bool includeEpicChildren = false,
    bool keepSprint = true,
  }) => _issues.moveIssues(
    issueIds,
    targetProjectId,
    stateMap: stateMap,
    includeEpicChildren: includeEpicChildren,
    keepSprint: keepSprint,
  );
}
