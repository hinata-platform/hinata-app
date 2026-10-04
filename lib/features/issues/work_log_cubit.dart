import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';

/// Where the work-log sheet sends what it saves.
///
/// Holds no state of its own: the form keeps its fields, the busy flag and the
/// error line, and awaits these calls the way it awaited the repository, so a
/// failure still arrives as the same [ApiFailure].
class WorkLogCubit extends Cubit<void> {
  WorkLogCubit(this._issues) : super(null);

  final IssueRepository _issues;

  /// Logs [minutes] of new work on [issueId].
  Future<WorkItem> log(
    String issueId, {
    required int minutes,
    String? description,
    DateTime? date,
  }) => _issues.addWorkItem(
    issueId,
    minutes: minutes,
    description: description,
    date: date,
  );

  /// Corrects the entry [id]; a null field is left as it is on the server.
  Future<WorkItem> correct(
    String id, {
    int? minutes,
    String? description,
    DateTime? date,
  }) => _issues.updateWorkItem(
    id,
    minutes: minutes,
    description: description,
    date: date,
  );
}
