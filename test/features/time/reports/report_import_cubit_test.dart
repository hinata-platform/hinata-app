import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_report_models.dart';
import 'package:hinata/features/time/reports/report_import_cubit.dart';

import '../../../support/recording_fake.dart';

/// The import wizard checks, pages, writes and discards through this cubit:
/// each call reaches the repository as asked and comes back as it answered.
void main() {
  const preview = ImportPreview(importId: 'i1');
  const error = ImportRowError(line: 3, message: 'time.import.badDate');

  late FakeTimeReportRepository reports;
  late ReportImportCubit cubit;

  setUp(() {
    reports = FakeTimeReportRepository();
    cubit = ReportImportCubit(reports);
    addTearDown(cubit.close);
  });

  test('checks a file with its mapping and target', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    reports.answer(#previewImport, preview);

    expect(
      await cubit.previewImport(
        fileName: 'hours.csv',
        bytes: bytes,
        mapping: {ImportColumn.date: 0},
        userId: 'u1',
      ),
      preview,
    );
    expect(
      reports.calls.single,
      invoked(
        #previewImport,
        named: {
          #fileName: 'hours.csv',
          #bytes: bytes,
          #path: null,
          #mapping: {ImportColumn.date: 0},
          #userId: 'u1',
        },
      ),
    );
  });

  test('pages the failed rows, writes, and throws a check away', () async {
    reports.answer(#importErrors, (items: [error], total: 1));
    reports.answer(#commitImport, 12);
    reports.answer<void>(#discardImport, null);

    expect((await cubit.importErrors('i1', page: 2)).items, [error]);
    expect(await cubit.commitImport('i1'), 12);
    await cubit.discardImport('i1');

    expect(reports.calls, [
      invoked(#importErrors, positional: ['i1'], named: {#page: 2}),
      invoked(#commitImport, positional: ['i1']),
      invoked(#discardImport, positional: ['i1']),
    ]);
  });

  test('passes a failure through', () async {
    reports.fail(#previewImport, failure);
    reports.fail(#importErrors, failure);
    reports.fail(#commitImport, failure);
    reports.fail(#discardImport, failure);

    await expectLater(
      () => cubit.previewImport(fileName: 'hours.csv'),
      throwsFailure,
    );
    await expectLater(() => cubit.importErrors('i1', page: 0), throwsFailure);
    await expectLater(() => cubit.commitImport('i1'), throwsFailure);
    await expectLater(() => cubit.discardImport('i1'), throwsFailure);
  });
}
