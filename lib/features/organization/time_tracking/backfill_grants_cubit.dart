import '../../../core/blocs/paged_cubit.dart';
import '../../../core/models/time_privacy_models.dart';
import '../../../core/repositories/time_repository.dart';

/// The openings for single people that are still open, 25 to a page, and
/// closing one sooner than its two weeks.
class BackfillGrantsCubit extends PagedCubit<TimeBackfillGrant> {
  BackfillGrantsCubit(this._time)
    : super(
        (page, size) => _time.backfillGrants(page: page, size: size),
        pageSize: 25,
        keyOf: (grant) => grant.id,
      );

  final TimeRepository _time;

  /// Closes one opening. The card drops the row itself once this lands, so a
  /// failure passes through as the repository's `ApiFailure` and leaves the
  /// list as it was.
  Future<void> revoke(String id) => _time.revokeBackfillGrant(id);
}
