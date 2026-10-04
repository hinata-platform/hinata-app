import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/features/account/working_hours_cubit.dart';

import '../recording_fake.dart';

class _FakeAvailability with RecordingFake implements AvailabilityRepository {}

/// Settings → Working hours reads and saves the pattern through this cubit.
void main() {
  late _FakeAvailability availability;
  late WorkingHoursCubit cubit;

  setUp(() {
    availability = _FakeAvailability();
    cubit = WorkingHoursCubit(availability);
  });
  tearDown(() => cubit.close());

  test('the calendars are read a page of the asked size', () async {
    final page = (items: <HolidayCalendar>[], total: 0);
    availability.answers[#calendars] = () =>
        Future<({List<HolidayCalendar> items, int total})>.value(page);

    expect(await cubit.calendars(size: 100), page);
    expect(availability.only.namedArguments, {#page: 0, #size: 100});
  });

  test('a save sends the pattern, its start and its calendar', () async {
    availability.answers[#saveSchedule] = () =>
        Future<WorkingPattern?>.value(null);
    final from = DateTime(2026, 10, 5);

    await cubit.saveSchedule(
      validFrom: from,
      minutesPerWeekday: const [480, 480, 480, 480, 480, 0, 0],
      holidayCalendarId: 'c1',
    );

    expect(availability.only.namedArguments, {
      #validFrom: from,
      #minutesPerWeekday: [480, 480, 480, 480, 480, 0, 0],
      #holidayCalendarId: 'c1',
    });
  });

  test('a failed read comes back as the same failure', () async {
    availability.answers[#schedule] = () =>
        Future<WorkingSchedule>.error(failure);

    await expectLater(cubit.schedule(), throwsA(same(failure)));
  });
}
