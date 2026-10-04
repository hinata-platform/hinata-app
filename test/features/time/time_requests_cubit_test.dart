import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/time_requests_cubit.dart';

import 'recording_repository.dart';

/// What a person asks about their own frozen time reaches the repository as
/// asked, and a refusal comes back for the dialog to say.
void main() {
  late _FakeTime time;
  late TimeRequestsCubit cubit;

  setUp(() {
    time = _FakeTime();
    cubit = TimeRequestsCubit(time);
    addTearDown(cubit.close);
  });

  test('asks for a correction and for days, with the reason', () async {
    time.answers[#requestCorrection] = Future<void>.value();
    time.answers[#requestBackfill] = Future<void>.value();

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
    time.answers[#entryCorrectionRequests] = Future.value([request]);

    expect(await cubit.entryCorrectionRequests('e1'), [request]);
    expect(
      time.calls.single,
      invoked(#entryCorrectionRequests, positional: ['e1']),
    );
  });

  test('passes a refusal through', () async {
    time.failure = refusal;

    await expectLater(
      () => cubit.requestCorrection('e1', 'wrong day'),
      throwsRefusal,
    );
    await expectLater(
      () => cubit.requestBackfill(
        from: DateTime(2026, 1, 5),
        to: DateTime(2026, 1, 5),
        note: 'was ill',
      ),
      throwsRefusal,
    );
    await expectLater(() => cubit.entryCorrectionRequests('e1'), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
