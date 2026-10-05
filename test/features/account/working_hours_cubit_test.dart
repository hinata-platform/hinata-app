import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/features/account/working_hours_cubit.dart';

import '../../support/recording_fake.dart';

/// Settings → Working hours reads and saves the pattern through this cubit.
void main() {
  late FakeAvailabilityRepository availability;
  late WorkingHoursCubit cubit;

  setUp(() {
    availability = FakeAvailabilityRepository();
    cubit = WorkingHoursCubit(availability);
  });
  tearDown(() => cubit.close());

  test('the calendars are read a page of the asked size', () async {
    final page = (items: <HolidayCalendar>[], total: 0);
    availability.answer<({List<HolidayCalendar> items, int total})>(
      #calendars,
      page,
    );

    expect(await cubit.calendars(size: 100), page);
    expect(availability.only.namedArguments, {#page: 0, #size: 100});
  });

  test('a save sends the pattern, its start and its calendar', () async {
    availability.answer<WorkingPattern?>(#saveSchedule, null);
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
    availability.fail(#schedule, failure);

    await expectLater(cubit.schedule(), throwsA(same(failure)));
  });
}
