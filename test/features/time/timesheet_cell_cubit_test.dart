import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/time/timesheet_cell_cubit.dart';

import '../../support/recording_fake.dart';

/// An opened timesheet cell reads and writes through this cubit: each call
/// reaches the repository as asked and comes back as it answered.
void main() {
  const entry = WorkItem(id: 'e1', durationMinutes: 45, activityType: 'WORK');
  const saved = SavedTimeEntry(entry: entry);

  late FakeTimeRepository time;
  late TimesheetCellCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    cubit = TimesheetCellCubit(time);
    addTearDown(cubit.close);
  });

  test('reads the day, adds an entry and removes one', () async {
    final day = DateTime(2026, 9, 3);
    final filter = TimeEntryFilter(from: day, to: day, projectId: 'p1');
    final draft = TimeEntryDraft(
      projectId: 'p1',
      durationMinutes: 45,
      date: day,
    );
    time.answer(#entries, (items: [entry], total: 1));
    time.answer(#create, saved);
    time.answer<void>(#delete, null);

    expect((await cubit.entries(filter: filter, size: 50)).items, [entry]);
    expect(await cubit.create(draft), saved);
    await cubit.delete('e1');

    expect(time.calls, [
      invoked(#entries, named: {#filter: filter, #size: 50}),
      invoked(#create, positional: [draft]),
      invoked(#delete, positional: ['e1']),
    ]);
  });

  test('passes a failure through', () async {
    time.fail(#entries, failure);
    time.fail(#create, failure);
    time.fail(#delete, failure);

    await expectLater(
      () => cubit.entries(filter: const TimeEntryFilter(), size: 50),
      throwsFailure,
    );
    await expectLater(
      () => cubit.create(const TimeEntryDraft(durationMinutes: 45)),
      throwsFailure,
    );
    await expectLater(() => cubit.delete('e1'), throwsFailure);
  });
}
