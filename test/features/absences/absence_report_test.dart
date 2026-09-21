/// The absence report, the expiry card and the yearly run (HIN-119): what is
/// worth failing a build over.
///
/// The report says "nothing yet" when there is nothing, and lists the people
/// it was given when there is; the rate appears only where the server sent it;
/// the pills offer grouping, type and scope; the person's card names the day
/// the leave lapses; and the keeper's page lists who was not told and sends the
/// notice when asked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/absence_report_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/absences/absence_report_view.dart';
import 'package:hinata/features/absences/absence_year_run_screen.dart';
import 'package:hinata/features/absences/absence_year_views.dart';
import 'package:hinata/features/time/reports/absence_report_tab.dart';

void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  void wide(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(2400, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    WidgetTester tester,
    _FakeAbsences repository,
    Widget child,
  ) async {
    await tester.pumpWidget(
      RepositoryProvider<AbsenceRepository>.value(
        value: repository,
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget tab(ValueNotifier<AbsenceReportQuery> query) =>
      AbsenceReportTab(query: query, padding: const EdgeInsets.all(16));

  testWidgets('an empty year says so instead of drawing an empty ring', (
    tester,
  ) async {
    wide(tester);
    final query = ValueNotifier(const AbsenceReportQuery());
    addTearDown(query.dispose);
    await pump(tester, _FakeAbsences(), tab(query));

    expect(find.text('absence.report.empty'), findsOneWidget);
    expect(find.byType(AbsenceReportOverview), findsNothing);
  });

  testWidgets(
    'a filled report lists every person it was given, without a rate it was not sent',
    (tester) async {
      wide(tester);
      final query = ValueNotifier(const AbsenceReportQuery());
      addTearDown(query.dispose);
      final repository = _FakeAbsences(
        rows: const [
          AbsenceReportRow(
            userId: 'a',
            name: 'Amira',
            figures: AbsenceFigures(
              entitledMilliDays: 20000,
              remainingMilliDays: 12000,
            ),
          ),
          AbsenceReportRow(
            userId: 'b',
            name: 'Ben',
            figures: AbsenceFigures(
              entitledMilliDays: 20000,
              remainingMilliDays: 5000,
            ),
          ),
        ],
      );
      await pump(tester, repository, tab(query));

      expect(find.byType(AbsenceReportOverview), findsOneWidget);
      expect(find.text('Amira'), findsOneWidget);
      expect(find.text('Ben'), findsOneWidget);
      expect(find.text('absence.report.rateShort'), findsNothing);
      expect(repository.reports, 1);
    },
  );

  testWidgets(
    'the pills offer grouping and scope, and a new grouping asks again',
    (tester) async {
      wide(tester);
      final query = ValueNotifier(const AbsenceReportQuery());
      addTearDown(query.dispose);
      final repository = _FakeAbsences(
        keeper: true,
        rows: const [AbsenceReportRow(userId: 'a', name: 'Amira')],
      );
      await pump(tester, repository, tab(query));

      expect(find.text('absence.report.groupPerson'), findsOneWidget);
      expect(find.text('absence.report.everybody'), findsOneWidget);
      await tester.tap(find.text('absence.report.groupPerson'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('absence.report.groupType').last);
      await tester.pumpAndSettle();

      expect(query.value.groupBy, AbsenceReportGroupBy.type);
      expect(repository.reports, 2);
    },
  );

  testWidgets('the expiry card names the day and the days', (tester) async {
    await pump(
      tester,
      _FakeAbsences(),
      AbsenceExpiryCard(
        typeName: 'Urlaub',
        milliDays: 3000,
        on: DateTime(2027, 3, 31),
      ),
    );

    expect(find.text('absence.expiry.title'), findsOneWidget);
    expect(find.text('absence.expiry.body'), findsOneWidget);
  });

  testWidgets(
    'the yearly run lists who was not told and sends the notice when asked',
    (tester) async {
      wide(tester);
      final repository = _FakeAbsences(
        missing: [
          AbsenceMissingNotice(
            userId: 'd',
            name: 'Dana',
            typeId: 'v',
            year: 2025,
            milliDays: 4000,
            deadline: DateTime(2026, 3, 31),
            overdue: true,
          ),
        ],
      );
      await pump(tester, repository, const AbsenceYearRunScreen());

      expect(find.byType(AbsenceYearRunCard), findsOneWidget);
      expect(find.text('Dana'), findsOneWidget);
      expect(find.text('absence.yearRun.proposalsEmpty'), findsOneWidget);
      await tester.tap(find.text('absence.yearRun.sendNow'));
      await tester.pumpAndSettle();

      expect(repository.sent, ['d:v:2025']);
    },
  );
}

/// A fake that answers what the report, the notices and the yearly run ask.
class _FakeAbsences implements AbsenceRepository {
  _FakeAbsences({
    this.rows = const [],
    this.keeper = false,
    this.missing = const [],
  });

  final List<AbsenceReportRow> rows;
  final bool keeper;
  final List<AbsenceMissingNotice> missing;
  int reports = 0;
  final List<String> sent = [];

  @override
  Future<List<AbsenceType>> types({bool includeInactive = false}) async =>
      const [];

  @override
  Future<bool> isKeeper() async => keeper;

  @override
  Future<AbsenceReportPage> report(
    AbsenceReportQuery query, {
    int page = 0,
    int size = 50,
  }) async {
    reports++;
    return (
      head: AbsenceReportHead(
        year: 2026,
        groupBy: query.groupBy,
        people: rows.length,
      ),
      rows: rows,
      total: rows.length,
    );
  }

  @override
  Future<AbsenceYearRun> yearRun() async =>
      AbsenceYearRun(day: DateTime(2026, 1, 2), carried: 3);

  @override
  Future<PageResult<AbsenceMissingNotice>> missingNotices({
    int page = 0,
    int size = 50,
  }) async => (
    items: page == 0 ? missing : const <AbsenceMissingNotice>[],
    total: missing.length,
  );

  @override
  Future<PageResult<AbsenceProposal>> proposals({
    int page = 0,
    int size = 50,
  }) async => (items: const <AbsenceProposal>[], total: 0);

  @override
  Future<AbsenceNotice> sendNotice({
    required String userId,
    required String typeId,
    required int year,
  }) async {
    sent.add('$userId:$typeId:$year');
    return AbsenceNotice(
      id: 'n',
      typeId: typeId,
      year: year,
      kind: 'MANUAL',
      remainingMilliDays: 1000,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
