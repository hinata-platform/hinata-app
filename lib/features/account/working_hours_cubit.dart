import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart' show PageResult;
import '../../core/models/availability_models.dart';
import '../../core/repositories/availability_repository.dart';

/// Settings → Working hours: the reader's weekday pattern and the holiday
/// calendars it can follow.
///
/// Holds no state of its own: the section keeps its draft over the stored
/// pattern, and these calls answer or fail as the repository does.
class WorkingHoursCubit extends Cubit<void> {
  WorkingHoursCubit(this._availability) : super(null);

  final AvailabilityRepository _availability;

  Future<WorkingSchedule> schedule() => _availability.schedule();

  Future<PageResult<HolidayCalendar>> calendars({int size = 50}) =>
      _availability.calendars(size: size);

  Future<WorkingPattern?> saveSchedule({
    DateTime? validFrom,
    required List<int> minutesPerWeekday,
    String? holidayCalendarId,
  }) => _availability.saveSchedule(
    validFrom: validFrom,
    minutesPerWeekday: minutesPerWeekday,
    holidayCalendarId: holidayCalendarId,
  );
}
