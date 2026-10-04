import 'package:bloc/bloc.dart';

import '../models/work_models.dart';
import '../repositories/issue_repository.dart';

/// Reads an issue's direct sub-tasks for the expander on board cards.
///
/// Holds no state: the expander keeps its own open/loading/failed flags and
/// the children it read, and drops them when an issue changes elsewhere.
class SubtaskExpanderCubit extends Cubit<void> {
  SubtaskExpanderCubit(this._issues) : super(null);

  final IssueRepository _issues;

  /// The direct children of the issue [issueId].
  Future<List<Issue>> children(String issueId) async =>
      (await _issues.issueHierarchy(issueId)).children;
}
