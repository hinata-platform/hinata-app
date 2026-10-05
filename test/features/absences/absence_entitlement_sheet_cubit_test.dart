import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/absence_report_models.dart';
import 'package:hinata/features/absences/absence_entitlement_sheet_cubit.dart';

import '../../support/recording_fake.dart';

void main() {
  late FakeAbsenceRepository absences;
  late AbsenceEntitlementSheetCubit cubit;

  const entry = AbsenceLedgerEntry(
    id: 'l1',
    typeId: 't1',
    year: 2026,
    kind: AbsenceLedgerKind.accrual,
    milliDays: 1000,
  );

  setUp(() {
    absences = FakeAbsenceRepository();
    cubit = AbsenceEntitlementSheetCubit(absences);
  });

  tearDown(() => cubit.close());

  test(
    'previewGrant asks with the override and passes the rows back',
    () async {
      const rows = <AbsenceGrantPreview>[];
      absences.answer<List<AbsenceGrantPreview>>(#previewGrant, rows);

      final result = await cubit.previewGrant(
        typeId: 't1',
        year: 2026,
        userIds: ['a', 'b'],
        allowanceMilliDays: 25000,
      );

      expect(result, same(rows));
      expect(
        absences.only,
        invoked(
          #previewGrant,
          named: {
            #typeId: 't1',
            #year: 2026,
            #userIds: ['a', 'b'],
            #allowanceMilliDays: 25000,
          },
        ),
      );
    },
  );

  test('grantMany writes and hands a failure back unchanged', () async {
    absences.fail(#grantMany, failure);

    await expectLater(
      cubit.grantMany(typeId: 't1', year: 2026, userIds: ['a']),
      throwsA(same(failure)),
    );
    expect(
      absences.only,
      invoked(
        #grantMany,
        named: {
          #typeId: 't1',
          #year: 2026,
          #userIds: ['a'],
          #allowanceMilliDays: null,
        },
      ),
    );
  });

  test('adjust books the correction as given', () async {
    absences.answer<AbsenceLedgerEntry>(#adjust, entry);
    final on = DateTime(2026, 3, 1);

    final result = await cubit.adjust(
      userId: 'u1',
      typeId: 't1',
      year: 2026,
      milliDays: -500,
      reason: 'why',
      effectiveOn: on,
    );

    expect(result, same(entry));
    expect(
      absences.only,
      invoked(
        #adjust,
        named: {
          #userId: 'u1',
          #typeId: 't1',
          #year: 2026,
          #milliDays: -500,
          #reason: 'why',
          #effectiveOn: on,
        },
      ),
    );
  });

  test('employment reads and saves the two dates', () async {
    const dates = EmploymentDates(userId: 'u1');
    absences
      ..answer<EmploymentDates>(#employment, dates)
      ..answer<EmploymentDates>(#saveEmployment, dates);
    final hired = DateTime(2020, 1, 1);

    expect(await cubit.employment('u1'), same(dates));
    expect(
      await cubit.saveEmployment(userId: 'u1', hiredOn: hired, note: 'n'),
      same(dates),
    );

    expect(absences.calls.first, invoked(#employment, positional: ['u1']));
    expect(
      absences.calls.last,
      invoked(
        #saveEmployment,
        named: {#userId: 'u1', #hiredOn: hired, #leftOn: null, #note: 'n'},
      ),
    );
  });

  test('settlement asks for the rows and every type at once', () async {
    const rows = <AbsenceSettlement>[];
    const types = <AbsenceType>[];
    absences
      ..answer<List<AbsenceSettlement>>(#settlement, rows)
      ..answer<List<AbsenceType>>(#types, types);

    final result = await cubit.settlement('u1');

    expect(result.settlement, same(rows));
    expect(result.types, same(types));
    expect(absences.calls.first, invoked(#settlement, positional: ['u1']));
    expect(
      absences.calls.last,
      invoked(#types, named: {#includeInactive: true}),
    );
  });

  test('payout books the days as given', () async {
    absences.answer<AbsenceLedgerEntry>(#payout, entry);

    final result = await cubit.payout(
      userId: 'u1',
      typeId: 't1',
      year: 2025,
      milliDays: 2000,
      reason: 'paid',
    );

    expect(result, same(entry));
    expect(
      absences.only,
      invoked(
        #payout,
        named: {
          #userId: 'u1',
          #typeId: 't1',
          #year: 2025,
          #milliDays: 2000,
          #reason: 'paid',
        },
      ),
    );
  });

  test('ledger reads the page it was asked for', () async {
    const page = (items: <AbsenceLedgerEntry>[entry], total: 1);
    absences.answer<PageResult<AbsenceLedgerEntry>>(#ledger, page);

    final result = await cubit.ledger(
      userId: 'u1',
      typeId: 't1',
      year: 2026,
      page: 0,
      size: 50,
    );

    expect(result, page);
    expect(
      absences.only,
      invoked(
        #ledger,
        named: {#userId: 'u1', #typeId: 't1', #year: 2026, #page: 0, #size: 50},
      ),
    );
  });
}
