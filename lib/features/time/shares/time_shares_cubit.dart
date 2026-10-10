import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/models/core_models.dart' show DirectoryUser;
import '../../../core/models/time_share_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/time_repository.dart';

/// Shared entries (HIN-95) as calls: the people an entry may go to, offering
/// and taking back, the two lists, and the two answers.
///
/// Holds no state: each list keeps its own pages and the actions on their way.
/// Failures pass through as the repository's `ApiFailure`.
class TimeSharesCubit extends Cubit<void> {
  TimeSharesCubit(this._time) : super(null);

  final TimeRepository _time;

  Future<PageResult<DirectoryUser>> candidates(
    String projectId, {
    String query = '',
    required int page,
    required int size,
  }) => _time.shareCandidates(projectId, query: query, page: page, size: size);

  Future<List<TimeEntryShare>> entryShares(String entryId) =>
      _time.entryShares(entryId);

  Future<List<TimeEntryShare>> share(String entryId, List<String> userIds) =>
      _time.shareEntry(entryId, userIds);

  Future<void> revoke(String entryId, String userId) =>
      _time.revokeShare(entryId, userId);

  Future<PageResult<TimeEntryShare>> page(
    TimeShareBox box, {
    required int page,
    required int size,
  }) => _time.shares(box, page: page, size: size);

  Future<WorkItem> accept(
    String id, {
    TimeShareAcceptance acceptance = const TimeShareAcceptance(),
  }) => _time.acceptShare(id, acceptance: acceptance);

  Future<void> decline(String id) => _time.declineShare(id);
}
