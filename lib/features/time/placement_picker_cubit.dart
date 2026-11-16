import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';

/// The two searches behind the placement picker: projects and issues, both on
/// the server as the reader types.
///
/// Holds no state: the picker keeps its results and its request token.
/// Failures pass through as the repository's `ApiFailure`.
class PlacementPickerCubit extends Cubit<void> {
  PlacementPickerCubit(this._projects, this._issues) : super(null);

  final ProjectRepository _projects;
  final IssueRepository _issues;

  Future<({List<Project> projects, int total})> searchProjects({
    required String query,
    required int size,
    int page = 0,
  }) => _projects.searchProjects(query: query, size: size, page: page);

  /// Issues matching [query]; null lists the newest. [projectId] keeps the
  /// search inside one project — the issue field of an entry that already has
  /// one, where an issue of another project would move the entry with it.
  Future<({List<Issue> issues, int total})> searchIssues({
    String? query,
    required int size,
    int page = 0,
    String? projectId,
  }) => _issues.issues(
    query: query,
    size: size,
    page: page,
    projectId: projectId,
  );
}
