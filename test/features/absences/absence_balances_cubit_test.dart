import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/absence_report_models.dart';
import 'package:hinata/features/absences/absence_balances_cubit.dart';

import '../../support/recording_fake.dart';

void main() {
  late FakeAbsenceRepository absences;
  late AbsenceBalancesCubit cubit;

  setUp(() {
    absences = FakeAbsenceRepository();
    cubit = AbsenceBalancesCubit(absences);
  });

  tearDown(() => cubit.close());

  test('balances asks for the reader\'s own year and passes it back', () async {
    const standing = AbsenceBalances(
      userId: 'u1',
      year: 2026,
      workingDaysPerWeek: 5,
      balances: [],
    );
    absences.answer<AbsenceBalances>(#balances, standing);

    expect(await cubit.balances(year: 2026), same(standing));
    // The reader's own balances: no user named, so userId goes as null.
    expect(
      absences.only,
      invoked(#balances, named: {#userId: null, #year: 2026}),
    );
  });

  test('balances hands the failure back unchanged', () async {
    absences.fail(#balances, failure);

    await expectLater(cubit.balances(year: 2025), throwsA(same(failure)));
  });

  test('ledger reads the page it was asked for', () async {
    const page = (items: <AbsenceLedgerEntry>[], total: 0);
    absences.answer<PageResult<AbsenceLedgerEntry>>(#ledger, page);

    final result = await cubit.ledger(
      userId: 'u1',
      typeId: 't1',
      year: 2026,
      page: 2,
      size: 50,
    );

    expect(result, page);
    expect(
      absences.only,
      invoked(
        #ledger,
        named: {#userId: 'u1', #typeId: 't1', #year: 2026, #page: 2, #size: 50},
      ),
    );
  });

  test('notices reads the page it was asked for', () async {
    const page = (items: <AbsenceNotice>[], total: 0);
    absences.answer<PageResult<AbsenceNotice>>(#notices, page);

    expect(await cubit.notices(page: 1, size: 10), page);
    expect(
      absences.only,
      invoked(#notices, named: {#userId: null, #page: 1, #size: 10}),
    );
  });
}
