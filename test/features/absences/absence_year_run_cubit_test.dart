import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/absence_report_models.dart';
import 'package:hinata/features/absences/absence_year_run_cubit.dart';

import 'recording_repositories.dart';

void main() {
  late RecordingAbsences absences;
  late AbsenceYearRunCubit cubit;

  setUp(() {
    absences = RecordingAbsences();
    cubit = AbsenceYearRunCubit(absences);
  });

  tearDown(() => cubit.close());

  test('overview reads the run and every type at once', () async {
    const run = AbsenceYearRun(openProposals: 2);
    const types = <AbsenceType>[];
    absences
      ..answer<AbsenceYearRun>(#yearRun, run)
      ..answer<List<AbsenceType>>(#types, types);

    final result = await cubit.overview();

    expect(result.run, same(run));
    expect(result.types, same(types));
    expectCall(absences.calls.first, #yearRun);
    expectCall(absences.calls.last, #types, named: {#includeInactive: true});
  });

  test('overview hands a refusal back unchanged', () async {
    absences
      ..fail<AbsenceYearRun>(#yearRun, failure)
      ..answer<List<AbsenceType>>(#types, const <AbsenceType>[]);

    await expectLater(cubit.overview(), throwsA(same(failure)));
  });

  test('the two lists read the page they were asked for', () async {
    const missing = (items: <AbsenceMissingNotice>[], total: 0);
    const proposals = (items: <AbsenceProposal>[], total: 0);
    absences
      ..answer<PageResult<AbsenceMissingNotice>>(#missingNotices, missing)
      ..answer<PageResult<AbsenceProposal>>(#proposals, proposals);

    expect(await cubit.missingNotices(page: 1, size: 50), missing);
    expect(await cubit.proposals(page: 2, size: 50), proposals);

    expectCall(
      absences.calls.first,
      #missingNotices,
      named: {#page: 1, #size: 50},
    );
    expectCall(absences.calls.last, #proposals, named: {#page: 2, #size: 50});
  });

  test('sendNotice sends it about the row given', () async {
    const notice = AbsenceNotice(
      id: 'n1',
      typeId: 't1',
      year: 2025,
      kind: 'MANUAL',
      remainingMilliDays: 3000,
    );
    absences.answer<AbsenceNotice>(#sendNotice, notice);

    final result = await cubit.sendNotice(
      userId: 'u1',
      typeId: 't1',
      year: 2025,
    );

    expect(result, same(notice));
    expectCall(
      absences.only,
      #sendNotice,
      named: {#userId: 'u1', #typeId: 't1', #year: 2025},
    );
  });

  test('decide confirms a lapse and dismisses otherwise', () async {
    absences
      ..answer<void>(#confirmProposal, null)
      ..answer<void>(#dismissProposal, null);

    await cubit.decide('p1', lapse: true, reason: 'long illness');
    await cubit.decide('p2', lapse: false, reason: 'not yet');

    expectCall(
      absences.calls.first,
      #confirmProposal,
      positional: ['p1', 'long illness'],
    );
    expectCall(
      absences.calls.last,
      #dismissProposal,
      positional: ['p2', 'not yet'],
    );
  });
}
