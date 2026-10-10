import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/billing_models.dart';
import 'package:hinata/core/repositories/billing_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/billing/billing_format.dart';
import 'package:hinata/features/billing/invoice_draft_sheet.dart';
import 'package:hinata/features/billing/invoices_screen.dart';
import 'package:hinata/features/billing/rate_timeline_sheet.dart';
import 'package:hinata/features/time/reports/billing_report_tab.dart';

/// Billing (HIN-96): amounts typed and shown, the rate timeline with "change
/// from a date", the invoice draft, the report tab's kinds by role, and the
/// invoices page for somebody without billing.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  group('amounts', () {
    test('typed amounts become cents, whatever the separator', () {
      expect(parseCents('95'), 9500);
      expect(parseCents('95,5'), 9550);
      expect(parseCents('95.50'), 9550);
      expect(parseCents('1.234,56'), 123456);
      expect(parseCents('1,234.56'), 123456);
      expect(parseCents('1.234'), 123400);
      expect(parseCents(' 12 '), 1200);
      expect(parseCents(''), isNull);
      expect(parseCents('abc'), isNull);
      expect(parseCents('-5'), isNull);
    });

    test('a tax rate is a percentage up to 100', () {
      expect(parseBasisPoints('19'), 1900);
      expect(parseBasisPoints('7,5'), 750);
      expect(parseBasisPoints('101'), isNull);
    });

    test('people are a grouping of the billing report only', () {
      expect(
        BillingGroupBy.forKind(BillingReportKind.billing, people: true),
        contains(BillingGroupBy.user),
      );
      expect(
        BillingGroupBy.forKind(BillingReportKind.billing, people: false),
        isNot(contains(BillingGroupBy.user)),
      );
      expect(
        BillingGroupBy.forKind(BillingReportKind.profitability, people: true),
        isNot(contains(BillingGroupBy.user)),
      );
      expect(
        BillingGroupBy.forKind(BillingReportKind.utilization, people: true),
        isNot(contains(BillingGroupBy.user)),
      );
    });

    test('an invoice reads its totals and lines from the wire', () {
      final detail = InvoiceDetail.fromJson(const {
        'summary': {
          'id': 'i1',
          'kind': 'CREDIT_NOTE',
          'number': 'INV-2026-00002',
          'status': 'ISSUED',
          'currency': 'EUR',
          'totals': {
            'minutes': -90,
            'netCents': -13500,
            'taxCents': -2565,
            'grossCents': -16065,
          },
          'creditedInvoiceId': 'i0',
        },
        'grouping': 'DAY',
        'recipient': {'name': 'ACME GmbH'},
        'taxBasisPoints': 1900,
        'lineCount': 1,
        'unratedLines': 0,
        'editable': false,
        'creditedInvoiceNumber': 'INV-2026-00001',
      });
      expect(detail.summary.kind, InvoiceKind.creditNote);
      expect(detail.summary.totals.grossCents, -16065);
      expect(detail.grouping, InvoiceGrouping.day);
      expect(detail.recipient.name, 'ACME GmbH');
      expect(detail.summary.isDraft, isFalse);
    });
  });

  group('rate timeline', () {
    const target = RateTarget(
      kind: RateKind.billable,
      scope: RateScope.project,
      scopeId: 'p1',
      label: 'Hinata',
    );

    Future<_FakeBilling> open(
      WidgetTester tester, {
      bool canEdit = true,
    }) async {
      final billing = _FakeBilling(
        spans: [
          BillingRate(
            id: 'r2',
            kind: RateKind.billable,
            scope: RateScope.project,
            scopeId: 'p1',
            amountCents: 9500,
            currency: 'EUR',
            validFrom: DateTime(2026, 9, 15),
            status: RateStatus.active,
          ),
          BillingRate(
            id: 'r1',
            kind: RateKind.billable,
            scope: RateScope.project,
            scopeId: 'p1',
            amountCents: 8000,
            currency: 'EUR',
            validFrom: DateTime(2026, 1, 1),
            validTo: DateTime(2026, 9, 14),
            status: RateStatus.ended,
          ),
        ],
      );
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRateTimelineSheet(
                  context,
                  billing: billing,
                  target: target,
                  currency: 'EUR',
                  canEdit: canEdit,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return billing;
    }

    testWidgets('shows every span of the target, newest first', (tester) async {
      await open(tester);

      expect(find.text('Hinata'), findsOneWidget);
      expect(find.byType(RateSpanRow), findsNWidgets(2));
      expect(find.textContaining('billing.rateStatus.active'), findsOneWidget);
      expect(find.textContaining('billing.rateStatus.ended'), findsOneWidget);
    });

    testWidgets('a new rate from a date is sent as cents and read back', (
      tester,
    ) async {
      final billing = await open(tester);

      await tester.enterText(find.byType(TextField), '120,50');
      await tester.tap(find.text('billing.rate.set'));
      await tester.pumpAndSettle();

      expect(billing.created, hasLength(1));
      expect(billing.created.single.$1, target);
      expect(billing.created.single.$2, 12050);
      expect(billing.timelineReads, 2);
    });

    testWidgets('an amount that is none is refused before anything is sent', (
      tester,
    ) async {
      final billing = await open(tester);

      await tester.enterText(find.byType(TextField), 'viel');
      await tester.tap(find.text('billing.rate.set'));
      await tester.pumpAndSettle();

      expect(billing.created, isEmpty);
      expect(find.text('billing.rate.amountInvalid'), findsOneWidget);
    });

    testWidgets('read-only, the form and the removal are not offered', (
      tester,
    ) async {
      await open(tester, canEdit: false);

      expect(find.byType(TextField), findsNothing);
      expect(find.text('billing.rate.set'), findsNothing);
      expect(find.byTooltip('billing.rate.remove'), findsNothing);
    });
  });

  group('invoice draft', () {
    Future<_FakeBilling> open(WidgetTester tester, {String? projectId}) async {
      final billing = _FakeBilling();
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepositoryProvider<ProjectRepository>.value(
          value: _NoProjects(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showInvoiceDraftSheet(
                    context,
                    billing: billing,
                    projectId: projectId,
                    projectName: projectId == null ? null : 'Hinata',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return billing;
    }

    testWidgets('asks for the project before drafting', (tester) async {
      final billing = await open(tester);

      await tester.tap(find.text('billing.invoice.createDraft'));
      await tester.pumpAndSettle();

      expect(billing.drafted, isEmpty);
      expect(find.text('error.billing.invoice.project'), findsOneWidget);
    });

    testWidgets('drafts last month of the project with the tax typed', (
      tester,
    ) async {
      final billing = await open(tester, projectId: 'p1');

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'ACME GmbH');
      await tester.enterText(fields.last, '19');
      await tester.tap(find.text('billing.invoice.createDraft'));
      await tester.pumpAndSettle();

      final request = billing.drafted.single;
      final now = DateTime.now();
      expect(request.projectId, 'p1');
      expect(request.from, DateTime(now.year, now.month - 1));
      expect(request.to, DateTime(now.year, now.month, 0));
      expect(request.grouping, InvoiceGrouping.issue);
      expect(request.taxBasisPoints, 1900);
      expect(request.recipient.name, 'ACME GmbH');
      expect(find.text('billing.invoice.createDraft'), findsNothing);
    });
  });

  group('report tab by role', () {
    Future<void> pump(WidgetTester tester, BillingAccess access) async {
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepositoryProvider<BillingRepository>.value(
          value: _FakeBilling(),
          child: MaterialApp(
            home: Scaffold(
              body: BillingReportTab(access: access, padding: EdgeInsets.zero),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('billing.report.kind.billing'));
      await tester.pumpAndSettle();
    }

    testWidgets('an administrator may ask for profitability', (tester) async {
      await pump(
        tester,
        const BillingAccess(
          currency: 'EUR',
          admin: true,
          costs: true,
          invoices: true,
          reports: true,
        ),
      );

      expect(find.text('billing.report.kind.profitability'), findsOneWidget);
    });

    testWidgets('a lead is not offered profitability', (tester) async {
      await pump(
        tester,
        const BillingAccess(
          currency: 'EUR',
          invoices: true,
          reports: true,
          ledProjects: ['p1'],
        ),
      );

      expect(find.text('billing.report.kind.profitability'), findsNothing);
      expect(find.text('billing.report.kind.utilization'), findsOneWidget);
    });
  });

  testWidgets('the invoices page tells a member it is not theirs', (
    tester,
  ) async {
    await tester.pumpWidget(
      RepositoryProvider<BillingRepository>.value(
        value: _FakeBilling(granted: BillingAccess.none),
        child: const MaterialApp(home: Scaffold(body: InvoicesScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('error.billing.forbidden'), findsOneWidget);
    expect(find.text('billing.invoice.new'), findsNothing);
  });

  testWidgets('an empty invoices page offers the first draft', (tester) async {
    await tester.pumpWidget(
      RepositoryProvider<BillingRepository>.value(
        value: _FakeBilling(
          granted: const BillingAccess(
            currency: 'EUR',
            admin: true,
            costs: true,
            invoices: true,
            reports: true,
          ),
        ),
        child: const MaterialApp(home: Scaffold(body: InvoicesScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('billing.invoices.emptyTitle'), findsOneWidget);
    expect(find.text('billing.invoice.new'), findsWidgets);
  });
}

class _NoProjects extends Fake implements ProjectRepository {}

class _FakeBilling extends Fake implements BillingRepository {
  _FakeBilling({
    this.spans = const [],
    this.granted = const BillingAccess(currency: 'EUR', reports: true),
  });

  final List<BillingRate> spans;
  final BillingAccess granted;
  final List<(RateTarget, int, DateTime)> created = [];
  final List<InvoiceDraftRequest> drafted = [];
  int timelineReads = 0;

  @override
  Future<BillingAccess> access() async => granted;

  @override
  Future<List<BillingRate>> timeline(RateTarget target) async {
    timelineReads++;
    return spans;
  }

  @override
  Future<BillingRate> createRate(
    RateTarget target, {
    required int amountCents,
    required DateTime from,
    DateTime? to,
  }) async {
    created.add((target, amountCents, from));
    return spans.first;
  }

  @override
  Future<InvoiceDetail> createDraft(InvoiceDraftRequest request) async {
    drafted.add(request);
    return InvoiceDetail(
      summary: const InvoiceSummary(
        id: 'd1',
        kind: InvoiceKind.invoice,
        status: InvoiceStatus.draft,
        totals: InvoiceTotals(),
        currency: 'EUR',
      ),
      grouping: request.grouping,
      recipient: request.recipient,
      taxBasisPoints: request.taxBasisPoints,
      lineCount: 0,
      unratedLines: 0,
      editable: true,
    );
  }

  @override
  Future<PageResult<InvoiceSummary>> invoices({
    InvoiceStatus? status,
    String? projectId,
    int page = 0,
    int size = 20,
  }) async => (items: const <InvoiceSummary>[], total: 0);

  @override
  Future<({BillingReportHead head, PageResult<BillingRow> rows})> report(
    BillingReportKind kind, {
    required DateTime from,
    required DateTime to,
    required BillingGroupBy groupBy,
    List<String> projectIds = const [],
    int page = 0,
    int size = 25,
  }) async => (
    head: BillingReportHead(
      kind: kind,
      groupBy: groupBy,
      currency: 'EUR',
      totals: const BillingRow(),
      costs: kind == BillingReportKind.profitability,
    ),
    rows: (items: const <BillingRow>[], total: 0),
  );
}
