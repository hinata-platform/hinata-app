import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/time/time_calendar_cubit.dart';

import '../../support/recording_fake.dart';

/// The calendar reads its windows and moves an entry through this cubit: each
/// call reaches the repository as asked and comes back as it answered.
void main() {
  final window = CalendarWindow(
    from: DateTime(2026, 9, 1),
    to: DateTime(2026, 9, 30),
  );
  const saved = SavedTimeEntry(
    entry: WorkItem(id: 'e1', durationMinutes: 60, activityType: 'WORK'),
  );

  late FakeTimeRepository time;
  late TimeCalendarCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    cubit = TimeCalendarCubit(time);
    addTearDown(cubit.close);
  });

  test('reads the window asked for and moves the entry named', () async {
    time.answer(#calendar, window);
    time.answer(#update, saved);
    final draft = TimeEntryDraft(
      startedAt: DateTime(2026, 9, 2, 9),
      endedAt: DateTime(2026, 9, 2, 10),
      date: DateTime(2026, 9, 2),
    );

    expect(
      await cubit.calendar(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      window,
    );
    expect(await cubit.update('e1', draft), saved);
    expect(time.calls, [
      invoked(
        #calendar,
        positional: [DateTime(2026, 9, 1), DateTime(2026, 9, 30)],
      ),
      invoked(#update, positional: ['e1', draft]),
    ]);
  });

  test('passes a failure through', () async {
    time.fail(#calendar, failure);
    time.fail(#update, failure);

    await expectLater(
      () => cubit.calendar(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      throwsFailure,
    );
    await expectLater(
      () => cubit.update('e1', const TimeEntryDraft()),
      throwsFailure,
    );
  });
}
