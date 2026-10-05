import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/features/time/tag_picker_cubit.dart';

import '../../support/recording_fake.dart';

/// The tag picker searches and grows the catalogue through this cubit: each
/// call reaches the repository as asked and comes back as it answered.
void main() {
  const tag = TimeTag(id: 't1', name: 'travel');

  late FakeTimeRepository time;
  late TagPickerCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    cubit = TagPickerCubit(time);
    addTearDown(cubit.close);
  });

  test('searches the catalogue and coins a word', () async {
    time.answer(#tags, (items: [tag], total: 1));
    time.answer(#createTag, tag);

    expect((await cubit.tags(query: 'tra', size: 30)).items, [tag]);
    expect(await cubit.createTag('travel'), tag);
    expect(time.calls, [
      invoked(#tags, named: {#query: 'tra', #size: 30}),
      invoked(#createTag, positional: ['travel'], named: {#hue: null}),
    ]);
  });

  test('passes a failure through', () async {
    time.fail(#tags, failure);
    time.fail(#createTag, failure);

    await expectLater(() => cubit.tags(size: 30), throwsFailure);
    await expectLater(() => cubit.createTag('travel'), throwsFailure);
  });
}
