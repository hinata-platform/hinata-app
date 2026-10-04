import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/time_calendar_cubit.dart';

import 'recording_repository.dart';

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

  late _FakeTime time;
  late TimeCalendarCubit cubit;

  setUp(() {
    time = _FakeTime();
    cubit = TimeCalendarCubit(time);
    addTearDown(cubit.close);
  });

  test('reads the window asked for and moves the entry named', () async {
    time.answers[#calendar] = Future.value(window);
    time.answers[#update] = Future.value(saved);
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

  test('passes a refusal through', () async {
    time.failure = refusal;

    await expectLater(
      () => cubit.calendar(DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
      throwsRefusal,
    );
    await expectLater(
      () => cubit.update('e1', const TimeEntryDraft()),
      throwsRefusal,
    );
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
