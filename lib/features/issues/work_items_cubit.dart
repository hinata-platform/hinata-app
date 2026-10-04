import '../../core/blocs/paged_cubit.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';

/// Every work entry of one issue, newest first, paged the way the server
/// pages them — the "all entries" sheet's list.
class WorkItemsPageCubit extends PagedCubit<WorkItem> {
  WorkItemsPageCubit(
    IssueRepository issues, {
    required String issueId,
    super.pageSize,
  }) : _issues = issues,
       super(
         (page, size) => issues.workItemsPage(issueId, page: page, size: size),
         keyOf: (item) => item.id,
       );

  final IssueRepository _issues;

  /// Deletes the entry [id]. The sheet drops the row itself once this lands,
  /// so a failure leaves the list as it was.
  Future<void> delete(String id) => _issues.deleteWorkItem(id);
}
