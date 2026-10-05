import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/features/time/time_requests_cubit.dart';

import '../../support/recording_fake.dart';

/// What a person asks about their own frozen time reaches the repository as
/// asked, and a failure comes back for the dialog to say.
void main() {
  late FakeTimeRepository time;
  late TimeRequestsCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    cubit = TimeRequestsCubit(time);
    addTearDown(cubit.close);
  });

  test('asks for a correction and for days, with the reason', () async {
    time.answer<void>(#requestCorrection, null);
    time.answer<void>(#requestBackfill, null);

    await cubit.requestCorrection('e1', 'wrong day');
    await cubit.requestBackfill(
      from: DateTime(2026, 1, 5),
      to: DateTime(2026, 1, 6),
      note: 'was ill',
    );

    expect(time.calls, [
      invoked(#requestCorrection, positional: ['e1', 'wrong day']),
      invoked(
        #requestBackfill,
        named: {
          #from: DateTime(2026, 1, 5),
          #to: DateTime(2026, 1, 6),
          #note: 'was ill',
        },
      ),
    ]);
  });

  test('reads the requests about one entry', () async {
    const request = TimeCorrectionRequest(id: 'r1');
    time.answer(#entryCorrectionRequests, [request]);

    expect(await cubit.entryCorrectionRequests('e1'), [request]);
    expect(
      time.calls.single,
      invoked(#entryCorrectionRequests, positional: ['e1']),
    );
  });

  test('passes a failure through', () async {
    time.fail(#requestCorrection, failure);
    time.fail(#requestBackfill, failure);
    time.fail(#entryCorrectionRequests, failure);

    await expectLater(
      () => cubit.requestCorrection('e1', 'wrong day'),
      throwsFailure,
    );
    await expectLater(
      () => cubit.requestBackfill(
        from: DateTime(2026, 1, 5),
        to: DateTime(2026, 1, 5),
        note: 'was ill',
      ),
      throwsFailure,
    );
    await expectLater(() => cubit.entryCorrectionRequests('e1'), throwsFailure);
  });
}
