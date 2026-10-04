import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/absence_request_models.dart';
import '../../core/models/availability_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/repositories/availability_repository.dart';

/// The absences view's reads and decisions: the reader's absences, the
/// requests on either side, and what can happen to a request.
///
/// Holds no state: the view keeps one list per scope and its filters, and the
/// reader's own pending requests live in `MyAbsencesCubit`. Failures pass
/// through as the repository's `ApiFailure`.
class TimeAbsencesCubit extends Cubit<void> {
  TimeAbsencesCubit(this._availability, this._absences) : super(null);

  final AvailabilityRepository _availability;
  final AbsenceRepository _absences;

  /// One page of the reader's absences, narrowed as the filters say.
  Future<PageResult<TimeOff>> timeOff({
    DateTime? from,
    DateTime? to,
    String? query,
    String? typeId,
    TimeOffType? type,
    bool oldestFirst = false,
    required int page,
    required int size,
  }) => _availability.timeOff(
    from: from,
    to: to,
    query: query,
    typeId: typeId,
    type: type,
    oldestFirst: oldestFirst,
    page: page,
    size: size,
  );

  /// One page of the requests the reader made.
  Future<PageResult<AbsenceRequest>> myRequests({
    required int page,
    required int size,
  }) => _absences.myRequests(page: page, size: size);

  /// One page of the requests waiting for the reader's decision.
  Future<PageResult<AbsenceRequest>> inbox({
    required int page,
    required int size,
  }) => _absences.inbox(page: page, size: size);

  Future<AbsenceRequest> approve(String requestId) =>
      _absences.approve(requestId);

  /// Sends a request back; the reason is required.
  Future<AbsenceRequest> reject(String requestId, {required String note}) =>
      _absences.reject(requestId, note: note);

  Future<AbsenceRequest> withdraw(String requestId) =>
      _absences.withdraw(requestId);

  /// Cancels approved leave that is still ahead; the reason is optional.
  Future<AbsenceRequest> cancel(String requestId, {String? note}) =>
      _absences.cancel(requestId, note: note);
}
