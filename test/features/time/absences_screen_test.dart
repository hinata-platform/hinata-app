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
import 'package:hinata/core/blocs/my_absences_cubit.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/absences/absence_request_sheet.dart';
import 'package:hinata/features/time/absences_screen.dart';

import '../absences/absence_test_support.dart';
import 'fake_time_policy_cubit.dart';

/// Days away in the time module: one's own absences, the requests and what
/// became of them, the inbox, and the forms behind them (HIN-117).
///
/// What is worth failing a build over: an inbox that says the honest thing when
/// it is empty; a rejection that cannot be sent without a reason (§ 7 (1)
/// BUrlG); a cancel button that is not offered for leave already under way,
/// because the server refuses that and a button that is going to be refused is
/// worse than no button; a request form that will not send a span worth nothing;
/// and a sick report that says what § 9 BUrlG handed back.
/// The catalogue most cases get: leave, and the sickness a filter can pick
/// beside it.
const _vacationType = AbsenceType(
  id: 't-vacation',
  key: 'vacation',
  kind: AbsenceKind.vacation,
  systemKey: 'vacation',
  countsAgainstBalance: true,
  icon: 'palmtree',
);

const _sickType = AbsenceType(
  id: 't-sick',
  key: 'sick',
  kind: AbsenceKind.sick,
  systemKey: 'sick',
  icon: 'thermometer',
);

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
    _FakeAbsences? absences,
    List<AbsenceRequest> pending = const [],
    List<AbsenceType> types = const [_vacationType],
  }) => MediaQuery(
    // The test surface's own size: a wider claim lays the page out for room
    // it does not get, and its head runs over the edge.
    data: const MediaQueryData(size: Size(800, 600)),
    child: MaterialApp(
      home: Scaffold(
        body: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AbsenceRepository>.value(value: repository),
            RepositoryProvider<UserRepository>.value(value: _FakeUsers()),
            RepositoryProvider<AvailabilityRepository>.value(
              value: absences ?? _FakeAbsences(),
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AppConfigBloc>(
                create: (_) => FakeAppConfig(absenceManagement: moduleOn),
              ),
              BlocProvider<AuthBloc>.value(value: _FakeAuth(meId)),
              BlocProvider<MyAbsencesCubit>(
                create: (_) => FakeMyAbsencesCubit(
                  managed: moduleOn,
                  pending: pending,
                  // What the module holds for every screen: the form a sheet
                  // reopens takes its types from here.
                  types: types,
                ),
              ),
              BlocProvider<TimePolicyCubit>(
                create: (_) =>
                    FakeTimePolicyCubit(TimePolicySnapshot.none, _UnusedTime()),
              ),
            ],
            child: child ?? const TimeAbsencesScreen(scope: 'requests'),
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
      host(_FakeRequests(), child: const TimeAbsencesScreen(scope: 'inbox')),
    );
    await tester.pumpAndSettle();

    expect(find.text('absence.view.empty.inbox'), findsOneWidget);
    expect(find.text('absence.view.emptyMessage.inbox'), findsOneWidget);
  });

  testWidgets(
    'a request in the inbox names who asked, and what it would cost',
    (tester) async {
      await tester.pumpWidget(
        host(
          _FakeRequests(inbox: [request(balanceShort: true, clashes: 2)]),
          child: const TimeAbsencesScreen(scope: 'inbox'),
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
    },
  );

  testWidgets('nobody is offered a decision on their own request', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        // A lead's own request lands in their own inbox — the server does not
        // filter it out — and it is the one they may not decide.
        _FakeRequests(
          inbox: [request(userId: 'me', personName: 'Me')],
        ),
        child: const TimeAbsencesScreen(scope: 'inbox'),
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
      host(repository, child: const TimeAbsencesScreen(scope: 'inbox')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('absence.request.approve'));
    await tester.pumpAndSettle();

    expect(repository.approved, ['r1']);
  });

  testWidgets('a rejection cannot be sent without a reason', (tester) async {
    final repository = _FakeRequests(inbox: [request()]);
    await tester.pumpWidget(
      host(repository, child: const TimeAbsencesScreen(scope: 'inbox')),
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
    expect(find.textContaining('absence.request.holidaysIn'), findsOneWidget);
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
    await tester.pumpWidget(
      host(repository, child: const _Opener(onTap: _openSick)),
    );
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
    await tester.pumpWidget(
      host(repository, child: const _Opener(onTap: _openSick)),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('absence.sick.report'));
    await tester.pumpAndSettle();

    // Leave comes back by itself, and saying so is the only way anybody learns
    // their balance moved.
    expect(find.text('absence.sick.reportedAndReturned'), findsOneWidget);
  });

  // --- the module switch ---------------------------------------------------------

  testWidgets('with the module off there are absences, and no requests', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(_FakeRequests(), moduleOn: false, child: const TimeAbsencesScreen()),
    );
    await tester.pumpAndSettle();

    // Entered directly, as they always were: no inbox and no request history
    // on an instance that has no approvals.
    expect(find.text('absence.view.scope.inbox'), findsNothing);
    expect(find.text('absence.view.empty.mine'), findsOneWidget);
    expect(find.text('availability.timeOff.add'), findsWidgets);
  });

  // --- one's own absences --------------------------------------------------------

  testWidgets(
    'one\'s own absences are listed, with what is still waiting above',
    (tester) async {
      final absences = _FakeAbsences(
        items: [
          TimeOff(
            id: 'a1',
            userId: 'me',
            type: TimeOffType.vacation,
            from: monday,
            to: monday.add(const Duration(days: 2)),
            note: 'Baltic Sea',
          ),
        ],
      );
      await tester.pumpWidget(
        host(
          _FakeRequests(),
          absences: absences,
          pending: [request(userId: 'me', personName: 'Me')],
          child: const TimeAbsencesScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('absence.view.pending'), findsOneWidget);
      expect(find.text('absence.request.status.submitted'), findsOneWidget);
      // Under the balances and what is waiting, below the fold of the surface.
      await tester.scrollUntilVisible(
        find.text('Baltic Sea'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .first,
      );
      expect(find.text('Baltic Sea'), findsOneWidget);
      expect(find.text('absence.sheet.entered'), findsOneWidget);
    },
  );

  testWidgets('the balances are a list of their own, not a block over the '
      'absences', (tester) async {
    await tester.pumpWidget(
      host(_FakeRequests(), child: const TimeAbsencesScreen()),
    );
    await tester.pumpAndSettle();

    // What is under the scopes on "mine": the search of the list, and no
    // block of balances above it.
    expect(find.text('absence.view.search'), findsOneWidget);
    expect(find.text('absence.balances.title'), findsNothing);

    // The scope of their own — where a notification or a link lands too.
    await tester.pumpWidget(
      host(
        _FakeRequests(),
        child: const TimeAbsencesScreen(scope: kAbsenceScopeBalances),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('absence.balances.title'), findsOneWidget);
    expect(find.text('absence.view.search'), findsNothing);
  });

  testWidgets('the search and the order reach the server', (tester) async {
    final absences = _FakeAbsences();
    await tester.pumpWidget(
      host(
        _FakeRequests(),
        absences: absences,
        child: const TimeAbsencesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'sea');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(absences.lastQuery, 'sea');

    await tester.tap(find.text('absence.view.newestFirst'));
    await tester.pumpAndSettle();
    expect(absences.lastOldestFirst, isTrue);
  });

  testWidgets('a type filter takes the waiting requests with it', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        _FakeRequests(),
        pending: [request(userId: 'me', personName: 'Me')],
        types: const [_vacationType, _sickType],
        child: const TimeAbsencesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('absence.view.pending'), findsOneWidget);

    await tester.tap(find.text('absence.view.allTypes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('absence.type.sick').last);
    await tester.pumpAndSettle();

    // The leave that waits is not sickness, so the block above the list goes
    // with the rest of it — a filter that only reaches half a page reads as a
    // broken filter.
    expect(find.text('absence.view.pending'), findsNothing);
    expect(find.text('absence.request.status.submitted'), findsNothing);
  });

  testWidgets('an absence entered directly opens with edit and delete', (
    tester,
  ) async {
    final absences = _FakeAbsences(
      items: [
        TimeOff(
          id: 'a1',
          userId: 'me',
          type: TimeOffType.other,
          from: monday,
          to: monday,
        ),
      ],
    );
    await tester.pumpWidget(
      host(
        _FakeRequests(),
        absences: absences,
        child: const TimeAbsencesScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('absence.sheet.entered'));
    await tester.pumpAndSettle();

    expect(find.text('common.edit'), findsOneWidget);
    expect(find.text('common.delete'), findsOneWidget);
  });

  testWidgets('an absence from a request opens the request, not an editor', (
    tester,
  ) async {
    final ahead = DateTime.now().add(const Duration(days: 20));
    final repository = _FakeRequests(
      mine: [
        request(
          userId: 'me',
          status: AbsenceRequestStatus.approved,
          from: ahead,
          to: ahead,
        ),
      ],
    );
    final absences = _FakeAbsences(
      items: [
        TimeOff(
          id: 'a1',
          userId: 'me',
          type: TimeOffType.vacation,
          from: ahead,
          to: ahead,
          requestId: 'r1',
        ),
      ],
    );
    await tester.pumpWidget(
      host(repository, absences: absences, child: const TimeAbsencesScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('absence.request.status.approved'));
    await tester.pumpAndSettle();

    // Changed only through the request: its days are booked against a
    // balance, and a direct edit would leave the booking behind.
    expect(find.text('common.edit'), findsNothing);
    expect(find.text('common.delete'), findsNothing);
    expect(find.text('absence.request.cancel'), findsOneWidget);
  });

  testWidgets('a waiting request opens with edit and withdraw', (tester) async {
    final repository = _FakeRequests(
      mine: [request(userId: 'me', personName: 'Me')],
    );
    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('absence.request.status.submitted'));
    await tester.pumpAndSettle();

    expect(find.text('common.edit'), findsOneWidget);
    expect(find.text('absence.request.withdraw'), findsWidgets);

    // And the button does what it says.
    await tester.tap(find.text('absence.request.withdraw').last);
    await tester.pumpAndSettle();
    expect(repository.withdrawn, ['r1']);
  });

  testWidgets('editing a waiting request sends the new span to the server', (
    tester,
  ) async {
    final repository = _FakeRequests(
      mine: [request(userId: 'me', personName: 'Me')],
    );
    await tester.pumpWidget(host(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('absence.request.status.submitted'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('common.edit'));
    await tester.pumpAndSettle();

    // The form says it is editing rather than filing, and saves through the
    // edit route with the request's own days.
    expect(find.text('absence.request.editTitle'), findsOneWidget);
    await tester.tap(find.text('absence.request.saveEdit'));
    await tester.pumpAndSettle();

    expect(repository.edited.keys, ['r1']);
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
  final Map<String, AbsenceRequestDraft> edited = {};
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
  Future<AbsenceRequest> edit(String id, AbsenceRequestDraft draft) async {
    edited[id] = draft;
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
  Future<AbsenceRequest> request(String id) async =>
      (_inbox + mine).firstWhere((request) => request.id == id);

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
  Future<bool> isKeeper() async => false;

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

/// The reader's own absences, and what the list asked for last.
class _FakeAbsences implements AvailabilityRepository {
  _FakeAbsences({this.items = const []});

  final List<TimeOff> items;
  String? lastQuery;
  bool? lastOldestFirst;

  @override
  Future<PageResult<TimeOff>> timeOff({
    DateTime? from,
    DateTime? to,
    String? query,
    String? typeId,
    TimeOffType? type,
    bool oldestFirst = false,
    int page = 0,
    int size = 50,
  }) async {
    lastQuery = query;
    lastOldestFirst = oldestFirst;
    return (items: items, total: items.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _UnusedTime implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
