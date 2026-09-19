import '../api/api_client.dart';
import '../blocs/paged_cubit.dart';
import '../models/availability_models.dart';
import '../util/dates.dart';

/// Capacity planning (HIN-91): the reader's working-time pattern and absences,
/// their capacity, and the holiday calendars administrators keep.
///
/// Behind the server's `advanced_time_tracking` flag like the rest of the
/// module, so with it off every route answers 404 `error.feature.disabled`.
/// Ids go into paths encoded.
class AvailabilityRepository {
  AvailabilityRepository(this._api);

  final ApiClient _api;

  static String _id(String id) => Uri.encodeComponent(id);

  // --- the pattern -------------------------------------------------------------

  Future<WorkingSchedule> schedule() async => WorkingSchedule.fromJson(
    await _api.get('/api/v1/availability/schedule') as Map<String, dynamic>,
  );

  /// Saves the pattern that applies from [validFrom], today when null. A
  /// pattern starting the same day is replaced.
  Future<WorkingPattern?> saveSchedule({
    DateTime? validFrom,
    required List<int> minutesPerWeekday,
    String? holidayCalendarId,
  }) async => WorkingPattern.fromJson(
    await _api.put(
          '/api/v1/availability/schedule',
          body: {
            if (validFrom != null) 'validFrom': formatDateOnly(validFrom),
            'minutesPerWeekday': minutesPerWeekday,
            'holidayCalendarId': ?holidayCalendarId,
          },
        )
        as Map<String, dynamic>,
  );

  // --- absences ----------------------------------------------------------------

  /// One page of the reader's absences touching [from]–[to], newest first —
  /// or oldest first with [oldestFirst]. [query] finds words in the note;
  /// [typeId] keeps one operator type, [type] one plain type.
  Future<PageResult<TimeOff>> timeOff({
    DateTime? from,
    DateTime? to,
    String? query,
    String? typeId,
    TimeOffType? type,
    bool oldestFirst = false,
    int page = 0,
    int size = 50,
  }) async {
    final words = query?.trim() ?? '';
    final data =
        await _api.get(
              '/api/v1/availability/time-off',
              query: {
                if (from != null) 'from': formatDateOnly(from),
                if (to != null) 'to': formatDateOnly(to),
                if (words.isNotEmpty) 'q': words,
                'typeId': ?typeId,
                if (type != null) 'type': type.wire,
                if (oldestFirst) 'sort': 'oldest',
                'page': page,
                'size': size,
              },
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final item in (data['content'] as List<dynamic>?) ?? const [])
          ?TimeOff.fromJson(item as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  Future<TimeOff?> createTimeOff(TimeOffDraft draft) async => TimeOff.fromJson(
    await _api.post('/api/v1/availability/time-off', body: draft.toJson())
        as Map<String, dynamic>,
  );

  Future<TimeOff?> updateTimeOff(String id, TimeOffDraft draft) async =>
      TimeOff.fromJson(
        await _api.patch(
              '/api/v1/availability/time-off/${_id(id)}',
              body: draft.toJson(),
            )
            as Map<String, dynamic>,
      );

  Future<void> deleteTimeOff(String id) =>
      _api.delete('/api/v1/availability/time-off/${_id(id)}');

  // --- capacity ----------------------------------------------------------------

  /// The reader's capacity from [from] to [to], at most a year.
  Future<Capacity> capacity(DateTime from, DateTime to) async =>
      Capacity.fromJson(
        await _api.get(
              '/api/v1/availability/capacity',
              query: {'from': formatDateOnly(from), 'to': formatDateOnly(to)},
            )
            as Map<String, dynamic>,
      );

  // --- holiday calendars -------------------------------------------------------

  Future<PageResult<HolidayCalendar>> calendars({
    int page = 0,
    int size = 50,
  }) async {
    final data =
        await _api.get(
              '/api/v1/availability/holidays/calendars',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: [
        for (final item in (data['content'] as List<dynamic>?) ?? const [])
          HolidayCalendar.fromJson(item as Map<String, dynamic>),
      ],
      total: (data['totalElements'] as num?)?.toInt() ?? 0,
    );
  }

  Future<HolidayCalendar> createCalendar({
    required String name,
    String? region,
    String? icsUrl,
    bool defaultCalendar = false,
  }) async => HolidayCalendar.fromJson(
    await _api.post(
          '/api/v1/availability/holidays/calendars',
          body: {
            'name': name,
            'region': ?region,
            'icsUrl': ?icsUrl,
            'defaultCalendar': defaultCalendar,
          },
        )
        as Map<String, dynamic>,
  );

  /// An edit; a null field is left alone, an empty [icsUrl] removes the feed.
  Future<HolidayCalendar> updateCalendar(
    String id, {
    String? name,
    String? region,
    String? icsUrl,
    bool? defaultCalendar,
  }) async => HolidayCalendar.fromJson(
    await _api.patch(
          '/api/v1/availability/holidays/calendars/${_id(id)}',
          body: {
            'name': ?name,
            'region': ?region,
            'icsUrl': ?icsUrl,
            'defaultCalendar': ?defaultCalendar,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> deleteCalendar(String id) =>
      _api.delete('/api/v1/availability/holidays/calendars/${_id(id)}');

  /// Starts importing a year of the calendar's feed. The answer comes at once
  /// with the calendar importing; reading the calendars again shows the result.
  Future<HolidayCalendar> importHolidays(String id, {int? year}) async =>
      HolidayCalendar.fromJson(
        await _api.post(
              '/api/v1/availability/holidays/calendars/${_id(id)}/import'
              '${year == null ? '' : '?year=$year'}',
            )
            as Map<String, dynamic>,
      );

  Future<List<Holiday>> holidays(String calendarId, {int? year}) async {
    final data =
        await _api.get(
              '/api/v1/availability/holidays',
              query: {'calendarId': calendarId, 'year': ?year},
            )
            as List<dynamic>;
    return [
      for (final item in data) ?Holiday.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Holiday?> addHoliday({
    required String calendarId,
    required DateTime date,
    required String name,
    bool halfDay = false,
  }) async => Holiday.fromJson(
    await _api.post(
          '/api/v1/availability/holidays',
          body: {
            'calendarId': calendarId,
            'date': formatDateOnly(date),
            'name': name,
            'halfDay': halfDay,
          },
        )
        as Map<String, dynamic>,
  );

  Future<Holiday?> updateHoliday(
    String id, {
    DateTime? date,
    String? name,
    bool? halfDay,
  }) async => Holiday.fromJson(
    await _api.patch(
          '/api/v1/availability/holidays/${_id(id)}',
          body: {
            if (date != null) 'date': formatDateOnly(date),
            'name': ?name,
            'halfDay': ?halfDay,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> deleteHoliday(String id) =>
      _api.delete('/api/v1/availability/holidays/${_id(id)}');
}
