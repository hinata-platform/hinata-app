import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/features/absences/absence_entitlements_cubit.dart';

import 'recording_repositories.dart';

void main() {
  late RecordingAbsences absences;
  late RecordingUsers users;
  late AbsenceEntitlementsCubit cubit;

  setUp(() {
    absences = RecordingAbsences();
    users = RecordingUsers();
    cubit = AbsenceEntitlementsCubit(absences, users);
  });

  tearDown(() => cubit.close());

  test('types asks for the inactive ones too', () async {
    const types = <AbsenceType>[];
    absences.answer<List<AbsenceType>>(#types, types);

    expect(await cubit.types(), same(types));
    expectCall(absences.only, #types, named: {#includeInactive: true});
  });

  test(
    'overview reads the page with the search and hands failures back',
    () async {
      const page = (items: <AbsenceStanding>[], total: 0);
      absences.answer<PageResult<AbsenceStanding>>(#overview, page);

      final result = await cubit.overview(
        typeId: 't1',
        year: 2026,
        query: 'ann',
        page: 1,
        size: 25,
      );

      expect(result, page);
      expectCall(
        absences.only,
        #overview,
        named: {#typeId: 't1', #year: 2026, #query: 'ann', #page: 1, #size: 25},
      );

      absences.fail<PageResult<AbsenceStanding>>(#overview, failure);
      await expectLater(
        cubit.overview(typeId: 't1', year: 2026, query: '', page: 0, size: 25),
        throwsA(same(failure)),
      );
    },
  );

  test('people reads the names behind the ids', () async {
    const found = [DirectoryUser(id: 'a', username: 'ann', displayName: 'Ann')];
    users.answer<List<DirectoryUser>>(#usersByIds, found);

    expect(await cubit.people(['a']), same(found));
    expectCall(
      users.only,
      #usersByIds,
      positional: [
        ['a'],
      ],
    );
    expect(absences.calls, isEmpty);
  });
}
