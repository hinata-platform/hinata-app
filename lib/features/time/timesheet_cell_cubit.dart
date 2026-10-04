import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/models/time_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/time_repository.dart';

/// One opened timesheet cell's reads and writes: the entries behind its
/// number, another one added, one removed.
///
/// Holds no state: the sheet keeps the entries, what is typed and whether it
/// changed anything. Failures pass through as the repository's `ApiFailure`.
class TimesheetCellCubit extends Cubit<void> {
  TimesheetCellCubit(this._time) : super(null);

  final TimeRepository _time;

  /// The reader's entries matching [filter], up to [size].
  Future<PageResult<WorkItem>> entries({
    required TimeEntryFilter filter,
    required int size,
  }) => _time.entries(filter: filter, size: size);

  Future<SavedTimeEntry> create(TimeEntryDraft draft) => _time.create(draft);

  Future<void> delete(String entryId) => _time.delete(entryId);
}
