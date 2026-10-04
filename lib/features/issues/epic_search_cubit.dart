import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';

/// Where the epic/parent picker sends its searches.
///
/// Holds no state of its own: the panel keeps the results, the paging and the
/// request token that discards a search overtaken by a newer one.
class EpicSearchCubit extends Cubit<void> {
  EpicSearchCubit(this._issues, {required this.projectId}) : super(null);

  final IssueRepository _issues;

  /// The project the parent is picked from.
  final String projectId;

  /// One page of [projectId]'s issues of [type] (any type when null) matching
  /// [query] (every issue, newest first, when null).
  Future<({List<Issue> issues, int total})> search({
    String? type,
    String? query,
    required int page,
    required int size,
  }) => _issues.issues(
    projectId: projectId,
    type: type,
    query: query,
    page: page,
    size: size,
  );
}
