import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/blocs/paged_cubit.dart';
import '../../../core/models/availability_models.dart';
import '../../../core/repositories/availability_repository.dart';

/// What Organisation → Holidays and its two forms ask of the server: the
/// calendars, their days, an import, and every change to either.
///
/// Holds no state: the page keeps its calendars, selection, year and import
/// polling, the forms their fields, as before. Failures pass through as the
/// repository's `ApiFailure`.
class OrgHolidaysCubit extends Cubit<void> {
  OrgHolidaysCubit(this._availability) : super(null);

  final AvailabilityRepository _availability;

  Future<PageResult<HolidayCalendar>> calendars({
    int page = 0,
    int size = 50,
  }) => _availability.calendars(page: page, size: size);

  Future<HolidayCalendar> createCalendar({
    required String name,
    String? region,
    String? icsUrl,
    bool defaultCalendar = false,
  }) => _availability.createCalendar(
    name: name,
    region: region,
    icsUrl: icsUrl,
    defaultCalendar: defaultCalendar,
  );

  /// An edit; a null field is left alone, an empty [icsUrl] removes the feed.
  Future<HolidayCalendar> updateCalendar(
    String id, {
    String? name,
    String? region,
    String? icsUrl,
    bool? defaultCalendar,
  }) => _availability.updateCalendar(
    id,
    name: name,
    region: region,
    icsUrl: icsUrl,
    defaultCalendar: defaultCalendar,
  );

  Future<void> deleteCalendar(String id) => _availability.deleteCalendar(id);

  /// Starts importing a year of the calendar's feed; answers at once with the
  /// calendar importing.
  Future<HolidayCalendar> importHolidays(String id, {int? year}) =>
      _availability.importHolidays(id, year: year);

  Future<List<Holiday>> holidays(String calendarId, {int? year}) =>
      _availability.holidays(calendarId, year: year);

  Future<Holiday?> addHoliday({
    required String calendarId,
    required DateTime date,
    required String name,
    bool halfDay = false,
  }) => _availability.addHoliday(
    calendarId: calendarId,
    date: date,
    name: name,
    halfDay: halfDay,
  );

  Future<Holiday?> updateHoliday(
    String id, {
    DateTime? date,
    String? name,
    bool? halfDay,
  }) =>
      _availability.updateHoliday(id, date: date, name: name, halfDay: halfDay);

  Future<void> deleteHoliday(String id) => _availability.deleteHoliday(id);
}
