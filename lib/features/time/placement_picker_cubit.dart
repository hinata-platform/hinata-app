import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';

/// The searches behind the placement pickers — projects and issues, on the
/// server as the reader types — and the names for a placement known only by
/// its ids.
///
/// Holds no state: the pickers keep their pages and the form its labels.
/// Search failures pass through as the repository's `ApiFailure`.
class PlacementPickerCubit extends Cubit<void> {
  PlacementPickerCubit(this._projects, this._issues) : super(null);

  final ProjectRepository _projects;
  final IssueRepository _issues;

  /// Projects matching [query]. [cancelToken] aborts the request once a newer
  /// search supersedes it.
  Future<({List<Project> projects, int total})> searchProjects({
    required String query,
    required int size,
    int page = 0,
    CancelToken? cancelToken,
  }) => _projects.searchProjects(
    query: query,
    size: size,
    page: page,
    cancelToken: cancelToken,
  );

  /// Issues matching [query]; null lists the newest. [projectId] keeps the
  /// search inside one project — the issue field of an entry that already has
  /// one, where an issue of another project would move the entry with it.
  Future<({List<Issue> issues, int total})> searchIssues({
    String? query,
    required int size,
    int page = 0,
    String? projectId,
    CancelToken? cancelToken,
  }) => _issues.issues(
    query: query,
    size: size,
    page: page,
    projectId: projectId,
    cancelToken: cancelToken,
  );

  /// The names to show for a project and an issue known only by their ids:
  /// the project's name, and the issue's "KEY · title" from the slim ref
  /// lookup rather than the whole issue. Either is null when it is not set,
  /// cannot be read (the reader has since left the project) or the read
  /// failed: the field then says that something is assigned without naming it,
  /// and the entry is no less editable for it.
  Future<({String? project, String? issue})> placementLabels({
    String? projectId,
    String? issueId,
  }) async {
    Future<String?> projectName() async {
      if (projectId == null) return null;
      try {
        final found = await _projects.resolveProjects([projectId]);
        return found.isEmpty ? null : found.first.name;
      } on ApiFailure {
        return null;
      }
    }

    Future<String?> issueName() async {
      if (issueId == null) return null;
      try {
        final found = await _issues.issueRefs([issueId]);
        return found.isEmpty
            ? null
            : '${found.first.readableId} · ${found.first.title}';
      } on ApiFailure {
        return null;
      }
    }

    final names = await Future.wait([projectName(), issueName()]);
    return (project: names[0], issue: names[1]);
  }
}
