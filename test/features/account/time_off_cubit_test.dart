import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_models.dart' show AbsenceType;
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/features/account/time_off_cubit.dart';

import '../recording_fake.dart';

class _FakeAvailability with RecordingFake implements AvailabilityRepository {}

class _FakeAbsences with RecordingFake implements AbsenceRepository {}

/// The form for an absence entered directly reads the operator's types and
/// writes the absence through this cubit.
void main() {
  late _FakeAvailability availability;
  late _FakeAbsences absences;
  late TimeOffCubit cubit;
  final draft = TimeOffDraft(
    type: TimeOffType.vacation,
    from: DateTime(2026, 10, 5),
    to: DateTime(2026, 10, 9),
  );

  setUp(() {
    availability = _FakeAvailability();
    absences = _FakeAbsences();
    cubit = TimeOffCubit(availability, absences);
  });
  tearDown(() => cubit.close());

  test('the types come from the absence catalogue', () async {
    final types = <AbsenceType>[];
    absences.answers[#types] = () => Future<List<AbsenceType>>.value(types);

    expect(await cubit.types(), same(types));
    expect(availability.calls, isEmpty);
  });

  test('create, update and delete reach the availability endpoints', () async {
    availability.answers[#createTimeOff] = () => Future<TimeOff?>.value(null);
    availability.answers[#updateTimeOff] = () => Future<TimeOff?>.value(null);
    availability.answers[#deleteTimeOff] = () => Future<void>.value();

    await cubit.create(draft);
    await cubit.update('t1', draft);
    await cubit.delete('t1');

    expect(availability.calls.map((c) => c.memberName), [
      #createTimeOff,
      #updateTimeOff,
      #deleteTimeOff,
    ]);
    expect(availability.calls[0].positionalArguments, [same(draft)]);
    expect(availability.calls[1].positionalArguments, ['t1', same(draft)]);
    expect(availability.calls[2].positionalArguments, ['t1']);
  });

  test('a refused save comes back as the same failure', () async {
    availability.answers[#createTimeOff] = () =>
        Future<TimeOff?>.error(failure);

    await expectLater(cubit.create(draft), throwsA(same(failure)));
  });
}
