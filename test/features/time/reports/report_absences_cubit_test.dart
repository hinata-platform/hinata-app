import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/absence_report_models.dart';
import 'package:hinata/features/time/reports/report_absences_cubit.dart';

import '../../../support/recording_fake.dart';

/// The absence report reads its pages, its catalogue and the reader's role,
/// and comes out as a file, through this cubit: each call reaches the
/// repository as asked and comes back as it answered.
void main() {
  const query = AbsenceReportQuery(year: 2026);
  const vacation = AbsenceType(
    id: 't1',
    key: 'VAC',
    kind: AbsenceKind.vacation,
  );

  late FakeAbsenceRepository absences;
  late ReportAbsencesCubit cubit;

  setUp(() {
    absences = FakeAbsenceRepository();
    cubit = ReportAbsencesCubit(absences);
    addTearDown(cubit.close);
  });

  test('reads a page, the catalogue and the role', () async {
    const head = AbsenceReportHead(year: 2026);
    absences.answer(#report, (
      head: head,
      rows: <AbsenceReportRow>[],
      total: 0,
    ));
    absences.answer(#types, [vacation]);
    absences.answer(#isKeeper, true);

    expect((await cubit.report(query, page: 1, size: 50)).head, head);
    expect(await cubit.types(), [vacation]);
    expect(await cubit.isKeeper(), isTrue);

    expect(absences.calls, [
      invoked(#report, positional: [query], named: {#page: 1, #size: 50}),
      invoked(#types, named: {#includeInactive: false}),
      invoked(#isKeeper),
    ]);
  });

  test('takes the report out as a file, in memory or to disk', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    absences.answer(#exportReport, (bytes: bytes, truncated: true));
    absences.answer(#exportReportTo, false);

    expect((await cubit.exportReport(query, 'pdf')).truncated, isTrue);
    expect(await cubit.exportReportTo(query, 'xlsx', '/tmp/a.xlsx'), isFalse);

    expect(absences.calls, [
      invoked(#exportReport, positional: [query, 'pdf']),
      invoked(#exportReportTo, positional: [query, 'xlsx', '/tmp/a.xlsx']),
    ]);
  });

  test('passes a failure through', () async {
    absences.fail(#report, failure);
    absences.fail(#types, failure);
    absences.fail(#isKeeper, failure);
    absences.fail(#exportReport, failure);
    absences.fail(#exportReportTo, failure);

    await expectLater(
      () => cubit.report(query, page: 0, size: 50),
      throwsFailure,
    );
    await expectLater(cubit.types, throwsFailure);
    await expectLater(cubit.isKeeper, throwsFailure);
    await expectLater(() => cubit.exportReport(query, 'pdf'), throwsFailure);
    await expectLater(
      () => cubit.exportReportTo(query, 'csv', '/tmp/a.csv'),
      throwsFailure,
    );
  });
}
