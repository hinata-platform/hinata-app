import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/features/absences/absence_types_cubit.dart';

import '../../support/recording_fake.dart';

void main() {
  late FakeAbsenceRepository absences;
  late AbsenceTypesCubit cubit;

  const type = AbsenceType(
    id: 't1',
    key: 'training',
    kind: AbsenceKind.special,
  );
  const draft = AbsenceTypeDraft(name: 'Training');

  setUp(() {
    absences = FakeAbsenceRepository();
    cubit = AbsenceTypesCubit(absences);
  });

  tearDown(() => cubit.close());

  test('types asks for the inactive ones too', () async {
    const types = [type];
    absences.answer<List<AbsenceType>>(#types, types);

    expect(await cubit.types(), same(types));
    expect(absences.only, invoked(#types, named: {#includeInactive: true}));
  });

  test('save creates a new type', () async {
    absences.answer<AbsenceType>(#createType, type);

    expect(await cubit.save(draft), same(type));
    expect(absences.only, invoked(#createType, positional: [draft]));
  });

  test('save updates the type it names', () async {
    absences.answer<AbsenceType>(#updateType, type);

    expect(await cubit.save(draft, existingId: 't1'), same(type));
    expect(absences.only, invoked(#updateType, positional: ['t1', draft]));
  });

  test('delete hands the server\'s failure back unchanged', () async {
    absences.fail(#deleteType, failure);

    await expectLater(cubit.delete('t1'), throwsA(same(failure)));
    expect(absences.only, invoked(#deleteType, positional: ['t1']));
  });
}
