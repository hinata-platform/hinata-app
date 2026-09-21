/// The time reports (HIN-93): what is worth failing a build over.
///
/// The workload tab exists only where the operator switched workload reports
/// on; an empty period says so rather than drawing an empty chart; the totals
/// and the groups come from the summary the server answered; the filter sheet
/// hands back the question the reader built; the export menu offers the three
/// files and the print dialog; and an import names every row that failed
/// before anything is written.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/time_report_models.dart';
import 'package:hinata/core/repositories/time_report_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/util/file_pick.dart';
import 'package:hinata/features/time/reports/report_actions.dart';
import 'package:hinata/features/time/reports/report_filter_sheet.dart';
import 'package:hinata/features/time/reports/report_import_wizard.dart';
import 'package:hinata/features/time/reports/time_reports_screen.dart';

import '../fake_time_policy_cubit.dart';

void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  // Keys render wider than words; a wide surface keeps every pill built.
  void wide(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(2400, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// The repositories and blocs above the app, as in the real one: a sheet
  /// on the root navigator inherits them only from there.
  Widget host(
    _FakeReports reports, {
    Widget child = const TimeReportsScreen(),
    TimePolicySnapshot policy = TimePolicySnapshot.none,
    bool admin = false,
  }) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<TimeReportRepository>.value(value: reports),
      RepositoryProvider<UserRepository>.value(value: _FakeUsers()),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: _FakeAuth(admin: admin)),
        BlocProvider<TimePolicyCubit>(
          create: (_) => FakeTimePolicyCubit(policy, _UnusedTime()),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );

  testWidgets('without its policy there is no workload tab', (tester) async {
    wide(tester);
    await tester.pumpWidget(host(_FakeReports()));
    await tester.pumpAndSettle();

    expect(find.text('time.reports.tab.summary'), findsOneWidget);
    expect(find.text('time.reports.tab.workload'), findsNothing);
  });

  testWidgets('with it, the workload tab joins the others', (tester) async {
    wide(tester);
    await tester.pumpWidget(
      host(
        _FakeReports(),
        policy: const TimePolicySnapshot(workloadReportsEnabled: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('time.reports.tab.workload'), findsOneWidget);
  });

  testWidgets('an empty period says so instead of drawing an empty chart', (
    tester,
  ) async {
    wide(tester);
    await tester.pumpWidget(host(_FakeReports()));
    await tester.pumpAndSettle();

    expect(find.text('time.reports.empty'), findsOneWidget);
    expect(find.text('time.reports.emptyHint'), findsOneWidget);
  });

  testWidgets('the summary shows the totals and every group it was given', (
    tester,
  ) async {
    wide(tester);
    final reports = _FakeReports(
      answer: const ReportSummary(
        totals: ReportTotals(minutes: 300, filedMinutes: 300, entries: 4),
        groups: [
          ReportGroup(key: 'p1', label: 'Apollo', detail: 'APO', minutes: 180),
          ReportGroup(key: 'p2', label: 'Zeus', detail: 'ZEU', minutes: 120),
        ],
        groupCount: 2,
      ),
    );
    await tester.pumpWidget(host(reports));
    await tester.pumpAndSettle();

    expect(find.text('time.reports.total'), findsWidgets);
    // Once in the chart's bars and once in the list under it.
    expect(find.text('Apollo'), findsNWidgets(2));
    expect(find.text('Zeus'), findsNWidgets(2));
    expect(reports.summaries, 1);
  });

  testWidgets('another chart of the same answer asks the server nothing', (
    tester,
  ) async {
    wide(tester);
    final reports = _FakeReports(
      answer: const ReportSummary(
        totals: ReportTotals(minutes: 60, filedMinutes: 60, entries: 1),
        groups: [ReportGroup(key: 'p1', label: 'Apollo', minutes: 60)],
        groupCount: 1,
      ),
    );
    await tester.pumpWidget(host(reports));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('time.reports.chart.pie'));
    await tester.pumpAndSettle();

    expect(reports.summaries, 1);
  });

  testWidgets('the filter sheet hands back the question the reader built', (
    tester,
  ) async {
    wide(tester);
    ReportQuery? result;
    await tester.pumpWidget(
      host(
        _FakeReports(),
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showReportFilterSheet(
              context,
              query: const ReportQuery(),
              labels: {},
              people: false,
              approvals: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('time.reports.sheet.people'), findsNothing);
    await tester.tap(find.text('time.reports.sheet.billableYes'));
    await tester.tap(find.text('time.reports.approval.approved'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.reports.sheet.done'));
    await tester.pumpAndSettle();

    expect(result?.billable, isTrue);
    expect(result?.approval, {ReportApproval.approved});
  });

  testWidgets('the export menu offers the three files and the printer', (
    tester,
  ) async {
    wide(tester);
    await tester.pumpWidget(
      host(
        _FakeReports(),
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReportFileMenu(context, null),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final file in ReportFile.values) {
      expect(find.text(file.labelKey), findsOneWidget);
    }
  });

  testWidgets('an import names every row that failed before writing', (
    tester,
  ) async {
    wide(tester);
    final reports = _FakeReports(
      preview: const ImportPreview(
        importId: 'i1',
        headers: ['date', 'minutes', 'project'],
        mapping: {ImportColumn.date: 0, ImportColumn.minutes: 1},
        totalRows: 3,
        validRows: 1,
        errorCount: 2,
        rows: [
          ImportPreviewRow(line: 2, minutes: 30, project: 'APO'),
          ImportPreviewRow(line: 3, error: 'The date cannot be read.'),
          ImportPreviewRow(line: 4, error: 'There is no project “NOPE”.'),
        ],
        errors: [
          ImportRowError(line: 3, message: 'The date cannot be read.'),
          ImportRowError(line: 4, message: 'There is no project “NOPE”.'),
        ],
      ),
    );
    await tester.pumpWidget(
      host(
        reports,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTimeImportWizard(context, admin: false),
            child: const Text('open'),
          ),
        ),
      ),
    );
    debugFilePickBackend = _OneFile();
    addTearDown(() => debugFilePickBackend = null);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.import.pick'));
    await tester.pumpAndSettle();

    expect(find.text('time.import.errorsTitle'), findsOneWidget);
    // In the preview beside its row, and again in the list of failures.
    expect(
      find.textContaining('The date cannot be read.', findRichText: true),
      findsNWidgets(2),
    );
    expect(reports.committed, isFalse);
  });
}

class _FakeReports implements TimeReportRepository {
  _FakeReports({this.answer = const ReportSummary(), this.preview});

  final ReportSummary answer;
  final ImportPreview? preview;
  int summaries = 0;
  bool committed = false;

  @override
  Future<ReportSummary> summary(
    ReportQuery query, {
    int page = 0,
    int size = 50,
    int weekStart = DateTime.monday,
  }) async {
    summaries++;
    return answer;
  }

  @override
  Future<ImportPreview> previewImport({
    required String fileName,
    Uint8List? bytes,
    String? path,
    Map<ImportColumn, int> mapping = const {},
    String? userId,
  }) async => preview!;

  @override
  Future<int> commitImport(String importId) async {
    committed = true;
    return 0;
  }

  @override
  Future<void> discardImport(String importId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUsers implements UserRepository {
  @override
  Future<List<DirectoryUser>> usersByIds(List<String> ids) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _UnusedTime implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAuth extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuth({required bool admin})
    : super(
        AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'me',
            email: 'me@example.org',
            username: 'me',
            displayName: 'Me',
            roles: {admin ? 'ADMIN' : 'USER'},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// A file dialog that hands over one small CSV at once.
class _OneFile implements FilePickBackend {
  @override
  Future<List<ChosenFile>> pick({
    required FilePickKind kind,
    required bool allowMultiple,
    required bool withData,
    required FilePickLabels labels,
  }) async => [
    ChosenFile(
      name: 'entries.csv',
      size: 3,
      bytes: Uint8List.fromList([1, 2, 3]),
    ),
  ];
}
