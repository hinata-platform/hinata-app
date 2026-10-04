import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/time_models.dart';
import '../../core/repositories/time_repository.dart';

/// The calendar's reads and its one write: a window of entries, and an entry
/// dragged to another time.
///
/// Holds no state: the calendar keeps its months, the way it scrolled and the
/// moves it shows before the server answers. Failures pass through as the
/// repository's `ApiFailure`.
class TimeCalendarCubit extends Cubit<void> {
  TimeCalendarCubit(this._time) : super(null);

  final TimeRepository _time;

  /// The entries and markings of the days [from] to [to].
  Future<CalendarWindow> calendar(DateTime from, DateTime to) =>
      _time.calendar(from, to);

  /// Moves the entry [id] to what [draft] says.
  Future<SavedTimeEntry> update(String id, TimeEntryDraft draft) =>
      _time.update(id, draft);
}
