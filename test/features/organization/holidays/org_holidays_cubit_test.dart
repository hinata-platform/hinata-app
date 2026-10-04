import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/features/organization/holidays/org_holidays_cubit.dart';

/// Organisation → Holidays: the calendars, their days and every change to
/// either, sent on as the page and its forms asked.
void main() {
  late _FakeAvailability availability;
  late OrgHolidaysCubit cubit;

  setUp(() {
    availability = _FakeAvailability();
    cubit = OrgHolidaysCubit(availability);
  });

  tearDown(() => cubit.close());

  final day = DateTime(2026, 10, 3);

  test('the calendars and one calendar\'s days', () async {
    final page = await cubit.calendars(size: 100);
    final days = await cubit.holidays('cal1', year: 2026);

    expect(page.items.single.id, 'cal1');
    expect(days.single.name, 'Tag der Deutschen Einheit');
    expect(availability.calls, ['calendars 0 100', 'holidays cal1 2026']);
  });

  test('calendar changes carry their fields', () async {
    await cubit.createCalendar(
      name: 'Hessen',
      region: 'HE',
      icsUrl: 'https://example.org/he.ics',
      defaultCalendar: true,
    );
    await cubit.updateCalendar('cal1', name: 'Hessen', icsUrl: '');
    await cubit.importHolidays('cal1', year: 2027);
    await cubit.deleteCalendar('cal1');

    expect(availability.calls, [
      'createCalendar Hessen HE https://example.org/he.ics true',
      'updateCalendar cal1 Hessen null  null',
      'import cal1 2027',
      'deleteCalendar cal1',
    ]);
  });

  test('holiday changes carry their fields', () async {
    await cubit.addHoliday(
      calendarId: 'cal1',
      date: day,
      name: 'Einheit',
      halfDay: true,
    );
    await cubit.updateHoliday('h1', date: day, name: 'Einheit');
    await cubit.deleteHoliday('h1');

    expect(availability.calls, [
      'addHoliday cal1 $day Einheit true',
      'updateHoliday h1 $day Einheit null',
      'deleteHoliday h1',
    ]);
  });

  test('a refusal passes through', () async {
    availability.fail = true;

    await expectLater(cubit.deleteCalendar('cal1'), throwsA(isA<ApiFailure>()));
  });
}

class _FakeAvailability implements AvailabilityRepository {
  bool fail = false;
  final List<String> calls = [];

  static const _calendar = HolidayCalendar(id: 'cal1', name: 'Hessen');

  @override
  Future<PageResult<HolidayCalendar>> calendars({
    int page = 0,
    int size = 50,
  }) async {
    calls.add('calendars $page $size');
    return (items: const [_calendar], total: 1);
  }

  @override
  Future<List<Holiday>> holidays(String calendarId, {int? year}) async {
    calls.add('holidays $calendarId $year');
    return [
      Holiday(
        id: 'h1',
        calendarId: calendarId,
        date: DateTime(2026, 10, 3),
        name: 'Tag der Deutschen Einheit',
      ),
    ];
  }

  @override
  Future<HolidayCalendar> createCalendar({
    required String name,
    String? region,
    String? icsUrl,
    bool defaultCalendar = false,
  }) async {
    calls.add('createCalendar $name $region $icsUrl $defaultCalendar');
    return _calendar;
  }

  @override
  Future<HolidayCalendar> updateCalendar(
    String id, {
    String? name,
    String? region,
    String? icsUrl,
    bool? defaultCalendar,
  }) async {
    calls.add('updateCalendar $id $name $region $icsUrl $defaultCalendar');
    return _calendar;
  }

  @override
  Future<HolidayCalendar> importHolidays(String id, {int? year}) async {
    calls.add('import $id $year');
    return _calendar;
  }

  @override
  Future<void> deleteCalendar(String id) async {
    if (fail) throw ApiFailure('error.forbidden', statusCode: 403);
    calls.add('deleteCalendar $id');
  }

  @override
  Future<Holiday?> addHoliday({
    required String calendarId,
    required DateTime date,
    required String name,
    bool halfDay = false,
  }) async {
    calls.add('addHoliday $calendarId $date $name $halfDay');
    return null;
  }

  @override
  Future<Holiday?> updateHoliday(
    String id, {
    DateTime? date,
    String? name,
    bool? halfDay,
  }) async {
    calls.add('updateHoliday $id $date $name $halfDay');
    return null;
  }

  @override
  Future<void> deleteHoliday(String id) async {
    calls.add('deleteHoliday $id');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
