import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/absence_models.dart';
import 'package:hinata/core/models/absence_request_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/absence_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/absences/absence_request_sheet.dart';
import 'package:hinata/features/absences/absence_requests_screen.dart';

import 'absence_test_support.dart';

/// Asking for time off, deciding it, and reporting sickness (HIN-117).
///
/// What is worth failing a build over: an inbox that says the honest thing when
/// it is empty; a rejection that cannot be sent without a reason (§ 7 (1)
/// BUrlG); a cancel button that is not offered for leave already under way,
/// because the server refuses that and a button that is going to be refused is
/// worse than no button; a request form that will not send a span worth nothing;
/// and a sick report that says what § 9 BUrlG handed back.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  final monday = DateTime(2026, 6, 15);

  AbsenceRequest request({
    String id = 'r1',
    String userId = 'them',
    AbsenceRequestStatus status = AbsenceRequestStatus.submitted,
    DateTime? from,
    DateTime? to,
    int milliDays = 5 * kMilliDay,
    String? personName = 'Lena',
    bool balanceShort = false,
    bool shortNotice = false,
    int clashes = 0,
    String? decisionNote,
    List<AbsenceRequestEvent> history = const [],
  }) => AbsenceRequest(
    id: id,
    userId: userId,
    typeId: 't-vacation',
    typeKey: 'vacation',
    typeSystemKey: 'vacation',
    from: from ?? monday,
    to: to ?? monday.add(const Duration(days: 4)),
    status: status,
    personName: personName,
    milliDays: milliDays,
    balanceShort: balanceShort,
    shortNotice: shortNotice,
    clashes: clashes,
    decisionNote: decisionNote,
    history: history,
  );

  /// No [PageChromeScope]: the page publishes its chrome into one when the
  /// shell provides it, and the shell is not what these tests are about.
  Widget host(
    _FakeRequests repository, {
    Widget? child,
    bool moduleOn = true,
    String meId = 'me',
  }) => MediaQuery(
    data: const MediaQueryData(size: Size(1100, 1400)),
    child: MaterialApp(
      home: Scaffold(
        body: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AbsenceRepository>.value(value: repository),
            RepositoryProvider<UserRepository>.value(value: _FakeUsers()),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AppConfigBloc>(
                create: (_) => FakeAppConfig(absenceManagement: moduleOn),
              ),
              BlocProvider<AuthBloc>.value(value: _FakeAuth(meId)),
            ],
            child: child ?? const AbsenceRequestsScreen(),
          ),
        ),
      ),
    ),
  );

  // --- the two lists -------------------------------------------------------

  testWidgets('an empty inbox says so rather than looking broken', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(_FakeRequests(), child: const AbsenceRequestsScreen(inbox: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('absence.request.empty.inbox'), findsOneWidget);
    expect(find.text('absence.request.emptyMessage.inbox'), findsOneWidget);
  });

  testWidgets('a request in the inbox names who asked, and what it would cost', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        _FakeRequests(inbox: [request(balanceShort: true, clashes: 2)]),
        child: const AbsenceRequestsScreen(inbox: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lena'), findsOneWidget);
    expect(find.text('absence.request.status.submitted'), findsOneWidget);
    // The warnings a decider weighs, and never a figure: whether the days are
    // there, not how many are left (R2, R10).
    expect(find.text('absence.request.balanceShortRow'), findsOneWidget);
    expect(find.text('absence.request.clashes'), findsOneWidget);
    expect(find.text('absence.request.approve'), findsOneWidget);
  });

  testWidgets('nobody is offered a decision on their own request', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        // A lead's own request lands in their own inbox — the server does not
        // filter it out — and it is the one they may not decide.
        _FakeRequests(inbox: [request(userId: 'me', personName: 'Me')]),
        child: const AbsenceRequestsScreen(inbox: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Me'), findsOneWidget);
    expect(find.text('absence.request.approve'), findsNothing);
    expect(find.text('absence.request.reject'), findsNothing);
  });

  testWidgets('approving sends it and says so', (tester) async {
    final repository = _FakeRequests(inbox: [request()]);
    await tester.pumpWidget(
      host(repository, child: const AbsenceRequestsScreen(inbox: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('absence.request.approve'));
    await tester.pumpAndSettle();

    expect(repository.approved, ['r1']);
  });

  testWidgets('a rejection cannot be sent without a reason', (tester) async {
    final repository = _FakeRequests(inbox: [request()]);
    await tester.pumpWidget(
      host(repository, child: const AbsenceRequestsScreen(inbox: true)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('absence.request.reject'));
    await tester.pumpAndSettle();
    expect(find.text('absence.request.rejectTitle'), findsOneWidget);

    // The confirm is dead until something is written: § 7 (1) BUrlG allows a
    // refusal only for a reason, so there is no way to send one without.
    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'common.ok'),
    );
    expect(confirm.onPressed, isNull);
    expect(repository.rejected, isEmpty);

    await tester.enterText(find.byType(TextField), 'Half the team is away');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'common.ok'));
    await tester.pumpAndSettle();

    expect(repository.rejected, {'r1': 'Half the team is away'});
  });

  testWidgets('leave already under way is not offered a cancel button', (
    tester,
  ) async {
    final started = DateTime.now().subtract(const Duration(days: 1));
    await tester.pumpWidget(
      host(
        _FakeRequests(
          mine: [
            request(
              userId: 'me',
              status: AbsenceRequestStatus.approved,
              from: started,
              to: started.add(const Duration(days: 3)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The server takes a keeper for this one, and a button that is going to be
    // refused is worse than no button.
    expect(find.text('absence.request.cancel'), findsNothing);
  });

  testWidgets('leave still ahead can be taken back by the person', (
    tester,
  ) async {
    final ahead = DateTime.now().add(const Duration(days: 20));
    final repository = _FakeRequests(
      mine: [
        request(
          userId: 'me',
          status: AbsenceRequestStatus.approved,
          from: ahead,
          to: ahead.add(const Duration(days: 2)),
        ),
      ],
    );
    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('absence.request.cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'common.ok'));
    await tester.pumpAndSettle();

    expect(repository.cancelled, ['r1']);
  });

  testWidgets('a rejected request carries the reason it was given', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        _FakeRequests(
          mine: [
            request(
              userId: 'me',
              status: AbsenceRequestStatus.rejected,
              decisionNote: 'Two others are already away',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // R4 and Art. 15: the person reads what was decided about them, and why.
    expect(find.text('Two others are already away'), findsOneWidget);
    expect(find.text('absence.request.withdraw'), findsNothing);
  });

  // --- the form ---------------------------------------------------------------

  testWidgets('the form previews what a span costs before anybody commits', (
    tester,
  ) async {
    final repository = _FakeRequests(
      preview: const AbsencePreview(
        milliDays: 4 * kMilliDay,
        workingDays: 4,
        holidays: 1,
        daysOff: 2,
      ),
    );
    await tester.pumpWidget(
      host(repository, child: const _Opener(onTap: _openRequest)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The figure with its reason beside it — one line, so that the total and
    // the holiday it fell on are read together — and nothing written yet.
    expect(
      find.textContaining('absence.request.holidaysIn'),
      findsOneWidget,
    );
    expect(find.textContaining('absence.request.daysOffIn'), findsOneWidget);
    expect(repository.submitted, isEmpty);
  });

  testWidgets('a span worth nothing cannot be sent', (tester) async {
    final repository = _FakeRequests(preview: const AbsencePreview());
    await tester.pumpWidget(
      host(repository, child: const _Opener(onTap: _openRequest)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Every day of it is a weekend, a holiday or a day this person does not
    // work: there is no leave to grant, so there is nothing to decide.
    final send = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'absence.request.submit'),
    );
    expect(send.onPressed, isNull);
  });

  // --- the sick report ---------------------------------------------------------

  testWidgets('a sick report is two fields and a sentence about proof', (
    tester,
  ) async {
    final repository = _FakeRequests();
    await tester.pumpWidget(host(repository, child: const _Opener(onTap: _openSick)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('absence.sick.title'), findsOneWidget);
    // No approver, no reason field, and the sentence that says no certificate
    // belongs in the product (§ 5 EFZG, Art. 9 DSGVO).
    expect(find.text('absence.sick.explainer'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('absence.sick.report'));
    await tester.pumpAndSettle();

    expect(repository.sickReports, 1);
  });

  testWidgets('§ 9 BUrlG: the days handed back are said out loud', (
    tester,
  ) async {
    final repository = _FakeRequests(
      sick: const SickReport(
        absenceId: 'a1',
        milliDays: 3 * kMilliDay,
        returnedMilliDays: 2 * kMilliDay,
      ),
    );
    await tester.pumpWidget(host(repository, child: const _Opener(onTap: _openSick)));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('absence.sick.report'));
    await tester.pumpAndSettle();

    // Leave comes back by itself, and saying so is the only way anybody learns
    // their balance moved.
    expect(find.text('absence.sick.reportedAndReturned'), findsOneWidget);
  });

  // --- the module switch ---------------------------------------------------------

  testWidgets('with the module off the page says so rather than spinning', (
    tester,
  ) async {
    final repository = _FakeRequests();
    await tester.pumpWidget(host(repository, moduleOn: false));
    await tester.pumpAndSettle();

    expect(find.text('absence.request.moduleOff'), findsOneWidget);
  });
}

Future<void> _openRequest(BuildContext context) => showAbsenceRequestSheet(
  context,
  types: const [
    AbsenceType(
      id: 't-vacation',
      key: 'vacation',
      kind: AbsenceKind.vacation,
      systemKey: 'vacation',
      countsAgainstBalance: true,
      icon: 'palmtree',
    ),
  ],
);

Future<void> _openSick(BuildContext context) => showSickReportSheet(
  context,
  types: const [
    AbsenceType(
      id: 't-sick',
      key: 'sick',
      kind: AbsenceKind.sick,
      systemKey: 'sick',
      unlimited: true,
      icon: 'thermometer',
    ),
  ],
);

/// A button that opens one of the sheets, so a sheet can be tested without the
/// page that usually offers it.
class _Opener extends StatelessWidget {
  const _Opener({required this.onTap});

  final Future<void> Function(BuildContext context) onTap;

  @override
  Widget build(BuildContext context) => Center(
    child: Builder(
      builder: (inner) =>
          TextButton(onPressed: () => onTap(inner), child: const Text('open')),
    ),
  );
}

class _FakeRequests implements AbsenceRepository {
  _FakeRequests({
    this.mine = const [],
    List<AbsenceRequest> inbox = const [],
    AbsencePreview preview = const AbsencePreview(
      milliDays: 5 * kMilliDay,
      workingDays: 5,
    ),
    this.sick = const SickReport(absenceId: 'a1', milliDays: kMilliDay),
  }) : _inbox = inbox,
       _preview = preview;

  final List<AbsenceRequest> mine;
  final List<AbsenceRequest> _inbox;
  final AbsencePreview _preview;
  final SickReport sick;

  final List<String> approved = [];
  final Map<String, String> rejected = {};
  final List<String> withdrawn = [];
  final List<String> cancelled = [];
  final List<AbsenceRequestDraft> submitted = [];
  int sickReports = 0;

  @override
  Future<PageResult<AbsenceRequest>> myRequests({
    AbsenceRequestStatus? status,
    int? year,
    int page = 0,
    int size = 25,
  }) async => (items: mine, total: mine.length);

  @override
  Future<PageResult<AbsenceRequest>> inbox({
    AbsenceRequestStatus? status,
    int page = 0,
    int size = 25,
  }) async => (items: _inbox, total: _inbox.length);

  @override
  Future<AbsenceRequest> approve(String id, {String? note}) async {
    approved.add(id);
    return (_inbox + mine).firstWhere((request) => request.id == id);
  }

  @override
  Future<AbsenceRequest> reject(String id, {required String note}) async {
    rejected[id] = note;
    return (_inbox + mine).firstWhere((request) => request.id == id);
  }

  @override
  Future<AbsenceRequest> withdraw(String id) async {
    withdrawn.add(id);
    return (_inbox + mine).firstWhere((request) => request.id == id);
  }

  @override
  Future<AbsenceRequest> cancel(String id, {String? note}) async {
    cancelled.add(id);
    return (_inbox + mine).firstWhere((request) => request.id == id);
  }

  @override
  Future<AbsencePreview> preview(AbsenceRequestDraft draft) async => _preview;

  @override
  Future<AbsenceRequest> submit(AbsenceRequestDraft draft) async {
    submitted.add(draft);
    return (mine + _inbox).first;
  }

  @override
  Future<SickReport> reportSick({
    required DateTime from,
    DateTime? to,
    bool halfDay = false,
    String? typeId,
  }) async {
    sickReports++;
    return sick;
  }

  @override
  Future<List<AbsenceType>> types({bool includeInactive = false}) async =>
      const [];

  @override
  Future<AbsenceBalances> balances({String? userId, int? year}) async =>
      const AbsenceBalances(
        userId: 'me',
        year: 2026,
        workingDaysPerWeek: 5,
        balances: [],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUsers implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAuth extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuth(String id)
    : super(
        AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: id,
            email: 'me@example.org',
            username: 'me',
            displayName: 'Me',
            roles: const {'USER'},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
