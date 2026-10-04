import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/tag_picker_cubit.dart';

import 'recording_repository.dart';

/// The tag picker searches and grows the catalogue through this cubit: each
/// call reaches the repository as asked and comes back as it answered.
void main() {
  const tag = TimeTag(id: 't1', name: 'travel');

  late _FakeTime time;
  late TagPickerCubit cubit;

  setUp(() {
    time = _FakeTime();
    cubit = TagPickerCubit(time);
    addTearDown(cubit.close);
  });

  test('searches the catalogue and coins a word', () async {
    time.answers[#tags] = Future.value((items: [tag], total: 1));
    time.answers[#createTag] = Future.value(tag);

    expect((await cubit.tags(query: 'tra', size: 30)).items, [tag]);
    expect(await cubit.createTag('travel'), tag);
    expect(time.calls, [
      invoked(#tags, named: {#query: 'tra', #size: 30}),
      invoked(#createTag, positional: ['travel'], named: {#hue: null}),
    ]);
  });

  test('passes a refusal through', () async {
    time.failure = refusal;

    await expectLater(() => cubit.tags(size: 30), throwsRefusal);
    await expectLater(() => cubit.createTag('travel'), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
