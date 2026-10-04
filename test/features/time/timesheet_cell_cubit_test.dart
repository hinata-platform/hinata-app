import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/timesheet_cell_cubit.dart';

import 'recording_repository.dart';

/// An opened timesheet cell reads and writes through this cubit: each call
/// reaches the repository as asked and comes back as it answered.
void main() {
  const entry = WorkItem(id: 'e1', durationMinutes: 45, activityType: 'WORK');
  const saved = SavedTimeEntry(entry: entry);

  late _FakeTime time;
  late TimesheetCellCubit cubit;

  setUp(() {
    time = _FakeTime();
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
    time.answers[#entries] = Future.value((items: [entry], total: 1));
    time.answers[#create] = Future.value(saved);
    time.answers[#delete] = Future<void>.value();

    expect((await cubit.entries(filter: filter, size: 50)).items, [entry]);
    expect(await cubit.create(draft), saved);
    await cubit.delete('e1');

    expect(time.calls, [
      invoked(#entries, named: {#filter: filter, #size: 50}),
      invoked(#create, positional: [draft]),
      invoked(#delete, positional: ['e1']),
    ]);
  });

  test('passes a refusal through', () async {
    time.failure = refusal;

    await expectLater(
      () => cubit.entries(filter: const TimeEntryFilter(), size: 50),
      throwsRefusal,
    );
    await expectLater(
      () => cubit.create(const TimeEntryDraft(durationMinutes: 45)),
      throwsRefusal,
    );
    await expectLater(() => cubit.delete('e1'), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
