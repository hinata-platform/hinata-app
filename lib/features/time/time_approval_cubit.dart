import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/time_approval_models.dart';
import '../../core/repositories/time_repository.dart';

/// The five things that can happen to a submission, as calls: what
/// [ApprovalActions] runs once it asked for what the server requires.
///
/// Holds no state: the timesheet and the inbox that offer these keep their own.
/// Failures pass through as the repository's `ApiFailure`, which is what the
/// actions turn into a toast.
class TimeApprovalCubit extends Cubit<void> {
  TimeApprovalCubit(this._time) : super(null);

  final TimeRepository _time;

  /// Hands the span in, for [projectIds] or for every project in it.
  Future<List<TimesheetApproval>> submit({
    required DateTime periodStart,
    required DateTime periodEnd,
    List<String>? projectIds,
  }) => _time.submitPeriod(
    periodStart: periodStart,
    periodEnd: periodEnd,
    projectIds: projectIds,
  );

  Future<TimesheetApproval> withdraw(String approvalId) =>
      _time.withdrawApproval(approvalId);

  Future<TimesheetApproval> approve(String approvalId) =>
      _time.approve(approvalId);

  Future<TimesheetApproval> reject(String approvalId, {required String note}) =>
      _time.reject(approvalId, note: note);

  Future<TimesheetApproval> reopen(String approvalId, {required String note}) =>
      _time.reopen(approvalId, note: note);
}
