import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/time/time_entry_sheet_cubit.dart';

import '../../support/recording_fake.dart';

/// The entry sheet writes through this cubit: each write reaches the
/// repository as asked and comes back as it answered.
void main() {
  const saved = SavedTimeEntry(
    entry: WorkItem(id: 'e1', durationMinutes: 90, activityType: 'WORK'),
  );
  const draft = TimeEntryDraft(durationMinutes: 90, description: 'review');

  late FakeTimeRepository time;
  late TimeEntrySheetCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    cubit = TimeEntrySheetCubit(time);
    addTearDown(cubit.close);
  });

  test('creates, edits and removes the entry named', () async {
    time.answer(#create, saved);
    time.answer(#update, saved);
    time.answer<void>(#delete, null);

    expect(await cubit.create(draft), saved);
    expect(await cubit.update('e1', draft), saved);
    await cubit.delete('e1');

    expect(time.calls, [
      invoked(#create, positional: [draft]),
      invoked(#update, positional: ['e1', draft]),
      invoked(#delete, positional: ['e1']),
    ]);
  });

  test('passes a failure through', () async {
    time.fail(#create, failure);
    time.fail(#update, failure);
    time.fail(#delete, failure);

    await expectLater(() => cubit.create(draft), throwsFailure);
    await expectLater(() => cubit.update('e1', draft), throwsFailure);
    await expectLater(() => cubit.delete('e1'), throwsFailure);
  });
}
