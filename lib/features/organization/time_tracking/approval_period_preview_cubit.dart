import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/time_approval_models.dart';
import '../../../core/repositories/time_repository.dart';

/// The approval periods the saved rhythm cuts, as the server computes them.
///
/// Holds no state: the preview keeps the three it shows and whether the read
/// failed, as before. Failures pass through as the repository's `ApiFailure`.
class ApprovalPeriodPreviewCubit extends Cubit<void> {
  ApprovalPeriodPreviewCubit(this._time) : super(null);

  final TimeRepository _time;

  Future<List<ApprovalPeriod>> periods({
    required DateTime from,
    required DateTime to,
  }) => _time.approvalPeriods(from: from, to: to);
}
