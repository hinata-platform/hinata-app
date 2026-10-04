import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/core_models.dart';
import '../../core/models/time_approval_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/repositories/user_repository.dart';

/// The approvals page's reads: a page of submissions, and the people and
/// projects the loaded rows mention.
///
/// Holds no state: the page keeps its own list, scope and labels. Failures pass
/// through as the repository's `ApiFailure`.
class ApprovalsCubit extends Cubit<void> {
  ApprovalsCubit(this._time, this._users, this._projects) : super(null);

  final TimeRepository _time;
  final UserRepository _users;
  final ProjectRepository _projects;

  /// One page of the submissions in [scope]: `mine` or `inbox`.
  Future<PageResult<TimesheetApproval>> approvals({
    required String scope,
    required int page,
    required int size,
  }) => _time.approvals(scope: scope, page: page, size: size);

  Future<List<DirectoryUser>> usersByIds(List<String> ids) =>
      _users.usersByIds(ids);

  Future<List<Project>> resolveProjects(List<String> ids) =>
      _projects.resolveProjects(ids);
}
