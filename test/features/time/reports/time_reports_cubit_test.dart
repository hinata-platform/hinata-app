import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_report_models.dart';
import 'package:hinata/core/repositories/time_report_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/time/reports/time_reports_cubit.dart';

import '../recording_repository.dart';

/// The report page's calls reach the repository as asked — the question, the
/// page and the first day of the week included — and come back as it answered.
void main() {
  const query = ReportQuery();
  const kept = SavedReport(id: 's1', name: 'September', query: query);
  const ada = DirectoryUser(id: 'u1', username: 'ada', displayName: 'Ada');

  late _FakeReports reports;
  late _FakeUsers users;
  late TimeReportsCubit cubit;

  setUp(() {
    reports = _FakeReports();
    users = _FakeUsers();
    cubit = TimeReportsCubit(reports, users);
    addTearDown(cubit.close);
  });

  test('reads the three reports with the week start', () async {
    const summary = ReportSummary();
    const workload = WorkloadPage();
    reports.answers[#summary] = Future.value(summary);
    reports.answers[#detailed] = Future.value((
      items: <ReportEntry>[],
      total: 0,
    ));
    reports.answers[#workload] = Future.value(workload);

    expect(
      await cubit.summary(query, page: 1, size: 50, weekStart: 7),
      summary,
    );
    expect(
      (await cubit.detailed(query, page: 2, size: 50, weekStart: 7)).total,
      0,
    );
    expect(
      await cubit.workload(
        query,
        projectId: 'p1',
        page: 0,
        size: 50,
        weekStart: 7,
      ),
      workload,
    );

    expect(reports.calls, [
      invoked(
        #summary,
        positional: [query],
        named: {#page: 1, #size: 50, #weekStart: 7},
      ),
      invoked(
        #detailed,
        positional: [query],
        named: {#page: 2, #size: 50, #weekStart: 7},
      ),
      invoked(
        #workload,
        positional: [query],
        named: {#projectId: 'p1', #page: 0, #size: 50, #weekStart: 7},
      ),
    ]);
  });

  test('keeps, opens, shares, schedules and drops a report', () async {
    const schedule = ReportSchedule(cadence: ReportCadence.weekly);
    reports.answers[#savedReports] = Future.value((items: [kept], total: 1));
    for (final member in [
      #openShared,
      #openSaved,
      #saveReport,
      #updateReport,
      #scheduleReport,
      #unscheduleReport,
    ]) {
      reports.answers[member] = Future.value(kept);
    }
    reports.answers[#shareReport] = Future.value('token');
    reports.answers[#unshareReport] = Future<void>.value();
    reports.answers[#deleteReport] = Future<void>.value();

    expect((await cubit.savedReports(page: 0, size: 50)).items, [kept]);
    expect(await cubit.openShared('token'), kept);
    expect(await cubit.openSaved('s1'), kept);
    expect(await cubit.saveReport('September', query), kept);
    expect(await cubit.updateReport('s1', name: 'October'), kept);
    expect(await cubit.shareReport('s1'), 'token');
    await cubit.unshareReport('s1');
    expect(await cubit.scheduleReport('s1', schedule), kept);
    expect(await cubit.unscheduleReport('s1'), kept);
    await cubit.deleteReport('s1');

    expect(reports.calls, [
      invoked(#savedReports, named: {#page: 0, #size: 50}),
      invoked(#openShared, positional: ['token']),
      invoked(#openSaved, positional: ['s1']),
      invoked(#saveReport, positional: ['September', query]),
      invoked(
        #updateReport,
        positional: ['s1'],
        named: {#name: 'October', #query: null},
      ),
      invoked(#shareReport, positional: ['s1']),
      invoked(#unshareReport, positional: ['s1']),
      invoked(#scheduleReport, positional: ['s1', schedule]),
      invoked(#unscheduleReport, positional: ['s1']),
      invoked(#deleteReport, positional: ['s1']),
    ]);
  });

  test('takes the report out as a file, in memory or to disk', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    reports.answers[#export] = Future.value((bytes: bytes, truncated: false));
    reports.answers[#exportTo] = Future.value(true);

    expect((await cubit.export(query, 'pdf', weekStart: 1)).bytes, bytes);
    expect(
      await cubit.exportTo(query, 'csv', '/tmp/r.csv', weekStart: 1),
      true,
    );

    expect(reports.calls, [
      invoked(#export, positional: [query, 'pdf'], named: {#weekStart: 1}),
      invoked(
        #exportTo,
        positional: [query, 'csv', '/tmp/r.csv'],
        named: {#weekStart: 1},
      ),
    ]);
  });

  test('names the people a kept report mentions', () async {
    users.answers[#usersByIds] = Future.value([ada]);

    expect(await cubit.usersByIds(['u1']), [ada]);
    expect(
      users.calls.single,
      invoked(
        #usersByIds,
        positional: [
          ['u1'],
        ],
      ),
    );
  });

  test('passes a refusal through', () async {
    reports.failure = refusal;
    users.failure = refusal;

    await expectLater(
      () => cubit.summary(query, page: 0, size: 50, weekStart: 1),
      throwsRefusal,
    );
    await expectLater(() => cubit.openSaved('s1'), throwsRefusal);
    await expectLater(() => cubit.shareReport('s1'), throwsRefusal);
    await expectLater(() => cubit.deleteReport('s1'), throwsRefusal);
    await expectLater(
      () => cubit.export(query, 'pdf', weekStart: 1),
      throwsRefusal,
    );
    await expectLater(() => cubit.usersByIds(['u1']), throwsRefusal);
  });
}

class _FakeReports with RecordingRepository implements TimeReportRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeUsers with RecordingRepository implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
