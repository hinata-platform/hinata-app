import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/time_entry_sheet_cubit.dart';

import 'recording_repository.dart';

/// The entry sheet writes through this cubit: each write reaches the
/// repository as asked and comes back as it answered.
void main() {
  const saved = SavedTimeEntry(
    entry: WorkItem(id: 'e1', durationMinutes: 90, activityType: 'WORK'),
  );
  const draft = TimeEntryDraft(durationMinutes: 90, description: 'review');

  late _FakeTime time;
  late TimeEntrySheetCubit cubit;

  setUp(() {
    time = _FakeTime();
    cubit = TimeEntrySheetCubit(time);
    addTearDown(cubit.close);
  });

  test('creates, edits and removes the entry named', () async {
    time.answers[#create] = Future.value(saved);
    time.answers[#update] = Future.value(saved);
    time.answers[#delete] = Future<void>.value();

    expect(await cubit.create(draft), saved);
    expect(await cubit.update('e1', draft), saved);
    await cubit.delete('e1');

    expect(time.calls, [
      invoked(#create, positional: [draft]),
      invoked(#update, positional: ['e1', draft]),
      invoked(#delete, positional: ['e1']),
    ]);
  });

  test('passes a refusal through', () async {
    time.failure = refusal;

    await expectLater(() => cubit.create(draft), throwsRefusal);
    await expectLater(() => cubit.update('e1', draft), throwsRefusal);
    await expectLater(() => cubit.delete('e1'), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
