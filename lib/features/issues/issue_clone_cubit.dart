import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';

/// Where the clone dialog sends the copy it asks for.
///
/// Holds no state of its own: the dialog keeps the summary, the switches and
/// the busy flag, and stays open on a failure so the summary survives it.
class IssueCloneCubit extends Cubit<void> {
  IssueCloneCubit(this._issues) : super(null);

  final IssueRepository _issues;

  /// Copies the issue [id] under [title]; answers the new issue.
  Future<Issue> clone(
    String id, {
    required String title,
    required List<String> assigneeIds,
    required bool includeAttachments,
    required bool includeLinks,
    required bool includeSprint,
  }) => _issues.cloneIssue(
    id,
    title: title,
    assigneeIds: assigneeIds,
    includeAttachments: includeAttachments,
    includeLinks: includeLinks,
    includeSprint: includeSprint,
  );
}
