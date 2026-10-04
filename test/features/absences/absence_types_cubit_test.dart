import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/features/absences/absence_types_cubit.dart';

import 'recording_repositories.dart';

void main() {
  late RecordingAbsences absences;
  late AbsenceTypesCubit cubit;

  const type = AbsenceType(
    id: 't1',
    key: 'training',
    kind: AbsenceKind.special,
  );
  const draft = AbsenceTypeDraft(name: 'Training');

  setUp(() {
    absences = RecordingAbsences();
    cubit = AbsenceTypesCubit(absences);
  });

  tearDown(() => cubit.close());

  test('types asks for the inactive ones too', () async {
    const types = [type];
    absences.answer<List<AbsenceType>>(#types, types);

    expect(await cubit.types(), same(types));
    expectCall(absences.only, #types, named: {#includeInactive: true});
  });

  test('save creates a new type', () async {
    absences.answer<AbsenceType>(#createType, type);

    expect(await cubit.save(draft), same(type));
    expectCall(absences.only, #createType, positional: [draft]);
  });

  test('save updates the type it names', () async {
    absences.answer<AbsenceType>(#updateType, type);

    expect(await cubit.save(draft, existingId: 't1'), same(type));
    expectCall(absences.only, #updateType, positional: ['t1', draft]);
  });

  test('delete hands the server\'s refusal back unchanged', () async {
    absences.fail<void>(#deleteType, failure);

    await expectLater(cubit.delete('t1'), throwsA(same(failure)));
    expectCall(absences.only, #deleteType, positional: ['t1']);
  });
}
