import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/absence_request_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/features/absences/absence_request_sheet_cubit.dart';

import '../../support/recording_fake.dart';

void main() {
  late FakeAbsenceRepository absences;
  late FakeUserRepository users;

  final draft = AbsenceRequestDraft(
    typeId: 't1',
    from: DateTime(2026, 7, 6),
    to: DateTime(2026, 7, 10),
  );
  final filed = AbsenceRequest(
    id: 'r1',
    userId: 'u1',
    typeId: 't1',
    from: DateTime(2026, 7, 6),
    to: DateTime(2026, 7, 10),
    status: AbsenceRequestStatus.submitted,
  );

  setUp(() {
    absences = FakeAbsenceRepository();
    users = FakeUserRepository();
  });

  group('the request form', () {
    late AbsenceRequestSheetCubit cubit;

    setUp(() => cubit = AbsenceRequestSheetCubit(absences, users));
    tearDown(() => cubit.close());

    test('people reads the stand-in by id', () async {
      const found = [
        DirectoryUser(id: 's1', username: 'sam', displayName: 'Sam'),
      ];
      users.answer<List<DirectoryUser>>(#usersByIds, found);

      expect(await cubit.usersByIds(['s1']), same(found));
      expect(
        users.only,
        invoked(
          #usersByIds,
          positional: [
            ['s1'],
          ],
        ),
      );
    });

    test('preview sends the draft and hands failures back', () async {
      const preview = AbsencePreview(milliDays: 5000);
      absences.answer<AbsencePreview>(#preview, preview);

      expect(await cubit.preview(draft), same(preview));
      expect(absences.only, invoked(#preview, positional: [draft]));

      absences.fail(#preview, failure);
      await expectLater(cubit.preview(draft), throwsA(same(failure)));
    });

    test('file submits a new request', () async {
      absences.answer<AbsenceRequest>(#submit, filed);

      expect(await cubit.file(draft), same(filed));
      expect(absences.only, invoked(#submit, positional: [draft]));
    });

    test('file edits the request it names', () async {
      absences.answer<AbsenceRequest>(#edit, filed);

      expect(await cubit.file(draft, existingId: 'r1'), same(filed));
      expect(absences.only, invoked(#edit, positional: ['r1', draft]));
    });
  });

  group('the sick report', () {
    late SickReportCubit cubit;

    setUp(() => cubit = SickReportCubit(absences));
    tearDown(() => cubit.close());

    test('reportSick sends the span as given', () async {
      const report = SickReport(milliDays: 1000);
      absences.answer<SickReport>(#reportSick, report);
      final day = DateTime(2026, 7, 6);

      final result = await cubit.reportSick(
        from: day,
        to: day,
        halfDay: true,
        typeId: 't-sick',
      );

      expect(result, same(report));
      expect(
        absences.only,
        invoked(
          #reportSick,
          named: {#from: day, #to: day, #halfDay: true, #typeId: 't-sick'},
        ),
      );
    });

    test('reportSick hands a failure back unchanged', () async {
      absences.fail(#reportSick, failure);

      await expectLater(
        cubit.reportSick(from: DateTime(2026, 7, 6)),
        throwsA(same(failure)),
      );
    });
  });
}
