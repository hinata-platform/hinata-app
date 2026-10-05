import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_request_models.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/features/time/time_absences_cubit.dart';

import '../../support/recording_fake.dart';

/// The absences view reads its lists and decides requests through this cubit:
/// each call reaches the repository as asked and comes back as it answered.
void main() {
  final absence = TimeOff(
    userId: 'u1',
    type: TimeOffType.vacation,
    from: DateTime(2026, 8, 3),
    to: DateTime(2026, 8, 7),
  );
  final request = AbsenceRequest(
    id: 'q1',
    userId: 'u1',
    typeId: 't1',
    from: DateTime(2026, 8, 3),
    to: DateTime(2026, 8, 7),
    status: AbsenceRequestStatus.submitted,
  );

  late FakeAvailabilityRepository availability;
  late FakeAbsenceRepository absences;
  late TimeAbsencesCubit cubit;

  setUp(() {
    availability = FakeAvailabilityRepository();
    absences = FakeAbsenceRepository();
    cubit = TimeAbsencesCubit(availability, absences);
    addTearDown(cubit.close);
  });

  test('reads the absences with every filter', () async {
    availability.answer(#timeOff, (items: [absence], total: 1));

    final page = await cubit.timeOff(
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 31),
      query: 'sea',
      typeId: 't1',
      type: TimeOffType.vacation,
      oldestFirst: true,
      page: 1,
      size: 30,
    );

    expect(page.items, [absence]);
    expect(
      availability.calls.single,
      invoked(
        #timeOff,
        named: {
          #from: DateTime(2026, 8, 1),
          #to: DateTime(2026, 8, 31),
          #query: 'sea',
          #typeId: 't1',
          #type: TimeOffType.vacation,
          #oldestFirst: true,
          #page: 1,
          #size: 30,
        },
      ),
    );
  });

  test('reads either side of the requests', () async {
    absences.answer(#myRequests, (items: [request], total: 1));
    absences.answer(#inbox, (items: [request], total: 1));

    expect((await cubit.myRequests(page: 0, size: 25)).items, [request]);
    expect((await cubit.inbox(page: 2, size: 25)).items, [request]);
    expect(absences.calls, [
      invoked(#myRequests, named: {#page: 0, #size: 25}),
      invoked(#inbox, named: {#page: 2, #size: 25}),
    ]);
  });

  test('decides the request named, with the reason given', () async {
    for (final member in [#approve, #reject, #withdraw, #cancel]) {
      absences.answer(member, request);
    }

    expect(await cubit.approve('q1'), request);
    expect(await cubit.reject('q1', note: 'team is away'), request);
    expect(await cubit.withdraw('q1'), request);
    expect(await cubit.cancel('q1', note: null), request);

    expect(absences.calls, [
      invoked(#approve, positional: ['q1'], named: {#note: null}),
      invoked(#reject, positional: ['q1'], named: {#note: 'team is away'}),
      invoked(#withdraw, positional: ['q1']),
      invoked(#cancel, positional: ['q1'], named: {#note: null}),
    ]);
  });

  test('passes a failure through', () async {
    availability.fail(#timeOff, failure);
    for (final member in [
      #myRequests,
      #inbox,
      #approve,
      #reject,
      #withdraw,
      #cancel,
    ]) {
      absences.fail(member, failure);
    }

    await expectLater(() => cubit.timeOff(page: 0, size: 30), throwsFailure);
    await expectLater(() => cubit.myRequests(page: 0, size: 25), throwsFailure);
    await expectLater(() => cubit.inbox(page: 0, size: 25), throwsFailure);
    await expectLater(() => cubit.approve('q1'), throwsFailure);
    await expectLater(() => cubit.reject('q1', note: 'no'), throwsFailure);
    await expectLater(() => cubit.withdraw('q1'), throwsFailure);
    await expectLater(() => cubit.cancel('q1'), throwsFailure);
  });
}
