import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/models/core_models.dart' show DirectoryUser;
import '../../core/models/time_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/time_repository.dart';

/// The entry sheet's writes: a new entry, an edit, a removal, and taking a
/// calendar event over.
///
/// Holds no state: the form keeps what is typed, whether it is saving and the
/// refusal it shows. Stopping a timer goes through `TimerCubit`, which owns
/// that transition. Failures pass through as the repository's `ApiFailure`.
class TimeEntrySheetCubit extends Cubit<void> {
  TimeEntrySheetCubit(this._time) : super(null);

  final TimeRepository _time;

  Future<SavedTimeEntry> create(TimeEntryDraft draft) => _time.create(draft);

  Future<SavedTimeEntry> update(String id, TimeEntryDraft draft) =>
      _time.update(id, draft);

  Future<void> delete(String id) => _time.delete(id);

  /// Offers the saved entry to the people mentioned with `+` (HIN-95).
  Future<void> share(String entryId, List<String> userIds) =>
      _time.shareEntry(entryId, userIds);

  /// The people of [projectId] a `+` may name.
  Future<PageResult<DirectoryUser>> shareCandidates(
    String projectId,
    String query,
    int page,
    int size,
  ) => _time.shareCandidates(projectId, query: query, page: page, size: size);

  /// Whether [projectId] bills its entries by default, or null when it follows
  /// the instance (HIN-158). Null too when the settings cannot be read: the
  /// switch then shows the instance's default, and the server decides anyway.
  Future<bool?> projectDefaultBillable(String projectId) async {
    try {
      return (await _time.projectSettings(projectId)).defaultBillable;
    } on ApiFailure {
      return null;
    }
  }

  /// Takes a calendar event over as an entry (HIN-94).
  Future<WorkItem> convert(String eventId, CalendarConversion conversion) =>
      _time.convertCalendarEvent(eventId, conversion);
}
