import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';

/// Where the linked-issues panel and its editor send their requests.
///
/// Holds no state of its own: the panel keeps the links it shows (removing one
/// optimistically and restoring it on failure), the editor its candidates.
/// Each call answers what the repository answers and fails the same way.
class IssueLinksCubit extends Cubit<void> {
  IssueLinksCubit(this._issues) : super(null);

  final IssueRepository _issues;

  /// The live `changed` pings for [issueId]'s links.
  Future<Stream<List<int>>> events(
    String issueId, {
    CancelToken? cancelToken,
  }) => _issues.issueLinkEventStream(issueId, cancelToken: cancelToken);

  Future<List<IssueLink>> links(String issueId) => _issues.issueLinks(issueId);

  /// Links [issueId] to every one of [targetIds] the one way; answers the
  /// issue's links afterwards.
  Future<List<IssueLink>> add(
    String issueId, {
    required String type,
    required bool outward,
    required List<String> targetIds,
  }) => _issues.addIssueLinks(
    issueId,
    type: type,
    outward: outward,
    targetIds: targetIds,
  );

  /// Removes the link [linkId]; answers the issue's links afterwards.
  Future<List<IssueLink>> remove(String issueId, String linkId) =>
      _issues.deleteIssueLink(issueId, linkId);

  /// The first [size] issues of [projectId] matching [query] (the most recent
  /// ones when null) — what the editor offers to link.
  Future<({List<Issue> issues, int total})> candidates(
    String projectId, {
    String? query,
    required int size,
  }) => _issues.issues(projectId: projectId, query: query, size: size);
}
