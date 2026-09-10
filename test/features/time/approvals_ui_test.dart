import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/time/approval_actions.dart';
import 'package:hinata/features/time/approvals_screen.dart';
import 'package:hinata/features/time/lock_notice.dart';
import 'package:hinata/features/shell/page_chrome.dart';

import 'fake_time_policy_cubit.dart';

/// The surfaces stage 7 adds: the lock notice every freeze shares, the status
/// chips, and the inbox.
///
/// The rows render as i18n *keys* here, which is what makes them worth asserting:
/// a key is the contract between the component and the bundle, and the one
/// failure this file exists to catch is a component that renders the wrong one —
/// a freeze explained with the lock date's sentence when an approval is what
/// froze it, say. What the words *say* is the bundle's business and is checked by
/// the parity test.
void main() {
  // --- one vocabulary for every freeze -------------------------------------

  group('the lock notice', () {
    Future<void> show(
      WidgetTester tester,
      TimeLockInfo lock, {
      bool compact = false,
    }) async {
      await tester.pumpWidget(
        RepositoryProvider<TimeRepository>.value(
          value: _FakeTimeRepository(),
          child: MaterialApp(
            home: Scaffold(
              body: LockNotice(lock: lock, compact: compact),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders the lock date with its own three sentences', (
      tester,
    ) async {
      await show(
        tester,
        TimeLockInfo(reason: 'lockDate', lockDate: DateTime(2026, 9, 1)),
      );

      expect(find.text('time.lock.reason.lockDate'), findsOneWidget);
      expect(find.text('time.lock.holder.lockDate'), findsOneWidget);
      expect(find.text('time.lock.remedy.lockDate'), findsOneWidget);
    });

    testWidgets('renders an approval with the same component and other words', (
      tester,
    ) async {
      // The whole point of the stage: one component, three sentences, and the
      // reason only picks which. HIN-96's invoice will be the third variant and
      // will need no new widget.
      await show(
        tester,
        TimeLockInfo(
          reason: 'approval',
          approvalId: 'a1',
          periodStart: DateTime(2026, 8, 1),
          periodEnd: DateTime(2026, 8, 31),
        ),
      );

      expect(find.text('time.lock.reason.approval'), findsOneWidget);
      expect(find.text('time.lock.holder.approval'), findsOneWidget);
      expect(find.text('time.lock.remedy.approval'), findsOneWidget);
      expect(find.text('time.lock.reason.lockDate'), findsNothing);
    });

    testWidgets('renders the invoice variant HIN-96 will use', (tester) async {
      // The keys exist before the mechanism does, so the day the third freeze
      // lands there is nothing to translate and nothing to wire.
      await show(tester, const TimeLockInfo(reason: 'invoice'));

      expect(find.text('time.lock.holder.invoice'), findsOneWidget);
      expect(find.text('time.lock.remedy.invoice'), findsOneWidget);
    });

    testWidgets('a reason this build has never heard of still says frozen', (
      tester,
    ) async {
      // A server newer than the app. "Closed, for a reason this app cannot name"
      // is the honest answer; rendering a raw key at somebody is not, and
      // silently reading as "fine" would be worse than either.
      await show(tester, const TimeLockInfo(reason: 'somethingNewer'));

      expect(find.text('time.lock.reason.unknown'), findsOneWidget);
    });

    testWidgets(
      'offers the way back only where there is an entry to ask about',
      (tester) async {
        await show(tester, const TimeLockInfo(reason: 'lockDate'));
        expect(find.text('time.lock.request'), findsNothing);

        await show(
          tester,
          const TimeLockInfo(reason: 'lockDate', entryId: 'w1'),
        );
        expect(find.text('time.lock.request'), findsOneWidget);
      },
    );

    testWidgets('the compact form drops the holder and keeps the remedy', (
      tester,
    ) async {
      // A bottom sheet's scarcest resource is height, and the remedy already
      // names who to ask.
      await show(tester, const TimeLockInfo(reason: 'approval'), compact: true);

      expect(find.text('time.lock.holder.approval'), findsNothing);
      expect(find.text('time.lock.remedy.approval'), findsOneWidget);
    });

    testWidgets('a correction request sends the typed reason and nothing else', (
      tester,
    ) async {
      final repository = _FakeTimeRepository();
      await tester.pumpWidget(
        RepositoryProvider<TimeRepository>.value(
          value: repository,
          child: const MaterialApp(
            home: Scaffold(
              body: LockNotice(
                lock: TimeLockInfo(reason: 'approval', entryId: 'w1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('time.lock.request'));
      await tester.pumpAndSettle();
      // Empty is refused by the server, so the dialog refuses it first: a button
      // that answers 400 teaches people to distrust the button.
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: find.text('time.lock.requestSend'),
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      // The dialog is wide enough for its own buttons in any language: a row of
      // two that overflowed would replace the confirm with a striped band.
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), '  Tuesday is doubled  ');
      await tester.pumpAndSettle();
      await tester.tap(find.text('time.lock.requestSend'));
      await tester.pumpAndSettle();

      expect(repository.corrections, [('w1', 'Tuesday is doubled')]);
      // The success toast dismisses itself on a timer; letting it finish here
      // keeps that timer out of whichever test runs next.
      await tester.pumpAndSettle(const Duration(seconds: 6));
    });
  });

  // --- the chips ------------------------------------------------------------

  group('the status chip', () {
    Future<void> show(
      WidgetTester tester,
      ApprovalStatus? status, {
      String? note,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ApprovalStatusChip(status: status, note: note),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('names every state a period can be in', (tester) async {
      await show(tester, null);
      expect(find.text('time.approval.status.open'), findsOneWidget);

      for (final status in ApprovalStatus.values) {
        await show(tester, status);
        expect(find.text(status.labelKey), findsOneWidget);
      }
    });

    testWidgets('a rejection carries its reason on the chip', (tester) async {
      // The reason is the whole point of sending a period back, so it must not
      // be a tap away from the state that says it happened.
      await show(tester, ApprovalStatus.rejected, note: 'Friday is missing');

      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Friday is missing',
      );
    });

    testWidgets('and a state with no reason carries no empty tooltip', (
      tester,
    ) async {
      await show(tester, ApprovalStatus.approved, note: '   ');

      expect(find.byType(Tooltip), findsNothing);
    });
  });

  // --- freezing, as the models see it ---------------------------------------

  group('the policy', () {
    TimesheetApproval approved({
      ApprovalStatus status = ApprovalStatus.approved,
    }) => TimesheetApproval(
      id: 'a1',
      userId: 'u1',
      projectId: 'p1',
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 31),
      status: status,
    );

    test('answers the lock date first, because it is the more absolute', () {
      // A day an administrator has archived stays archived whatever a submission
      // says about it — which is also the order the server resolves them in.
      final policy = TimePolicySnapshot(
        lockBefore: DateTime(2026, 9, 1),
        approvalsEnabled: true,
      );
      expect(
        policy.lockFor(DateTime(2026, 8, 10), projectId: 'p1')!.reason,
        'lockDate',
      );
    });

    test('an exception inside the freeze reopens exactly its own days', () {
      final policy = TimePolicySnapshot(
        lockBefore: DateTime(2026, 9, 1),
        lockExceptions: [
          TimeLockException(
            id: 'e1',
            from: DateTime(2026, 8, 10),
            to: DateTime(2026, 8, 12),
            note: 'payroll correction',
          ),
        ],
      );

      expect(policy.isLocked(DateTime(2026, 8, 9)), isTrue);
      for (final open in [10, 11, 12]) {
        expect(
          policy.isLocked(DateTime(2026, 8, open)),
          isFalse,
          reason: 'August $open is inside the exception',
        );
      }
      expect(policy.isLocked(DateTime(2026, 8, 13)), isTrue);
    });

    test('a submitted period freezes its days once the lock date is clear', () {
      final policy = TimePolicySnapshot(
        approvalsEnabled: true,
        myFrozenPeriods: [approved(status: ApprovalStatus.submitted)],
      );

      final lock = policy.lockFor(
        DateTime(2026, 8, 31),
        projectId: 'p1',
        entryId: 'w1',
      );
      expect(lock?.reason, 'approval');
      expect(lock?.approvalId, 'a1');
      expect(lock?.entryId, 'w1');
      // And the day after it is not.
      expect(policy.lockFor(DateTime(2026, 9, 1), projectId: 'p1'), isNull);
    });

    test('and freezes only its own project', () {
      // Both halves of the tuple have to match: a period is somebody's hours for
      // *one* project, so a submission of one freezes nothing in another — and an
      // entry with no project is never handed in at all.
      final policy = TimePolicySnapshot(
        approvalsEnabled: true,
        myFrozenPeriods: [approved()],
      );

      expect(policy.lockFor(DateTime(2026, 8, 10), projectId: 'p1'), isNotNull);
      expect(policy.lockFor(DateTime(2026, 8, 10), projectId: 'p2'), isNull);
      expect(policy.lockFor(DateTime(2026, 8, 10)), isNull);
    });

    test(
      'a rejected or withdrawn period freezes nothing — that is the point',
      () {
        const policy = TimePolicySnapshot(approvalsEnabled: true);
        for (final status in [
          ApprovalStatus.rejected,
          ApprovalStatus.withdrawn,
        ]) {
          expect(
            policy
                .withFrozenPeriods([approved(status: status)])
                .lockFor(DateTime(2026, 8, 10), projectId: 'p1'),
            isNull,
            reason: '$status must leave the period editable',
          );
        }
      },
    );

    test('with approvals off a stale submission freezes nothing either', () {
      // Switching the policy off has to give people their records back.
      final policy = TimePolicySnapshot(myFrozenPeriods: [approved()]);

      expect(policy.lockFor(DateTime(2026, 8, 10), projectId: 'p1'), isNull);
    });
  });

  // --- the freeze is visible before it refuses ---------------------------------

  group('the entry form', () {
    testWidgets('shows the notice for a period the reader has handed in', (
      tester,
    ) async {
      // The whole point of loading the freezing periods with the rules: before
      // this, a person whose period was submitted opened the form, saw nothing,
      // typed, and was refused on save. The lock has to be drawn, not discovered.
      final policy = TimePolicySnapshot(
        approvalsEnabled: true,
        myFrozenPeriods: [
          TimesheetApproval(
            id: 'a1',
            userId: 'u1',
            projectId: 'p1',
            periodStart: DateTime(2026, 8, 1),
            periodEnd: DateTime(2026, 8, 31),
            status: ApprovalStatus.submitted,
          ),
        ],
      );

      final lock = policy.lockFor(
        DateTime(2026, 8, 14),
        projectId: 'p1',
        entryId: 'w1',
      );

      expect(lock?.reason, 'approval');
      await tester.pumpWidget(
        RepositoryProvider<TimeRepository>.value(
          value: _FakeTimeRepository(),
          child: MaterialApp(
            home: Scaffold(body: LockNotice(lock: lock!)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('time.lock.reason.approval'), findsOneWidget);
      expect(find.text('time.lock.request'), findsOneWidget);
    });

    test('a refusal the app did not see coming becomes the notice', () {
      // The rules the app holds can be a moment out of date — somebody else's
      // approval landing between the last read and this save. Then the server's
      // answer is the authority, and it carries everything the notice needs.
      final failure = ApiFailure(
        'error.time.approvalLocked',
        statusCode: 403,
        details: const {
          'reason': 'approval',
          'holder': 'approver',
          'remedy': 'reopen',
          'approvalId': 'a9',
          'periodStart': '2026-08-01',
          'periodEnd': '2026-08-31',
        },
      );

      final lock = lockFromFailure(failure, entryId: 'w1');

      expect(lock?.reason, 'approval');
      expect(lock?.approvalId, 'a9');
      expect(lock?.periodEnd, DateTime(2026, 8, 31));
      expect(lock?.entryId, 'w1');
      // And an ordinary failure names no freeze at all.
      expect(lockFromFailure(ApiFailure('errors.unexpected')), isNull);
    });
  });

  // --- what a period offers -------------------------------------------------

  group('a period', () {
    ApprovalProjectStatus project(
      String id, {
      ApprovalStatus? status,
      int minutes = 60,
      bool required = true,
    }) => ApprovalProjectStatus(
      projectId: id,
      projectKey: id.toUpperCase(),
      status: status,
      minutes: minutes,
      required: required,
    );

    test('offers only what can still be handed in', () {
      final period = ApprovalPeriod(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 31),
        type: 'MONTHLY',
        projects: [
          project('hin'),
          // Already in: nothing to do.
          project('mob', status: ApprovalStatus.submitted),
          // Sent back: that is exactly what can be handed in again.
          project('inf', status: ApprovalStatus.rejected),
          // No hours: there is nothing to submit.
          project('ops', minutes: 0),
          // The project says its periods are not handed in at all.
          project('kb', required: false),
        ],
      );

      expect(period.submittable.map((p) => p.projectId), ['hin', 'inf']);
      expect(period.withdrawable.map((p) => p.projectId), ['mob']);
      expect(period.minutes, 240);
    });
  });

  // --- the inbox ------------------------------------------------------------

  group('the approvals page', () {
    Future<_FakeTimeRepository> open(
      WidgetTester tester, {
      List<TimesheetApproval> mine = const [],
      List<TimesheetApproval> inbox = const [],
    }) async {
      final repository = _FakeTimeRepository(mine: mine, inbox: inbox);
      // Wide, and that is the point: on a phone the page docks its scope switch
      // into the shell's glass app bar, and this host draws no shell band — so a
      // compact viewport would be asserting about a control nothing rendered.
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<TimeRepository>.value(value: repository),
            RepositoryProvider<UserRepository>.value(
              value: const _FakeUserRepository(),
            ),
            RepositoryProvider<ProjectRepository>.value(
              value: const _FakeProjectRepository(),
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: _FakeAuthBloc()),
              BlocProvider<TimePolicyCubit>.value(
                value: FakeTimePolicyCubit(
                  const TimePolicySnapshot(approvalsEnabled: true),
                  repository,
                ),
              ),
            ],
            // A router above it, because PageChrome publishes into the shell by
            // asking GoRouterState where it is — the page is a destination, not a
            // widget that can be rendered on its own.
            child: MaterialApp.router(
              routerConfig: GoRouter(
                routes: [
                  GoRoute(
                    path: '/time/approvals',
                    builder: (_, _) => PageChromeScope(
                      controller: PageChromeController(),
                      child: const Scaffold(body: ApprovalsScreen()),
                    ),
                  ),
                ],
                initialLocation: '/time/approvals',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repository;
    }

    /// Taps the inbox segment.
    ///
    /// Scrolled into view first, and that is a test artifact worth naming: the
    /// labels render as i18n *keys* here, which are far longer than the words
    /// they stand for, so the second chip of a 280-point pill is scrolled out of
    /// it — and a clipped widget does not hit-test. Nothing is wrong with the
    /// control; asserting its pixels would be.
    Future<void> switchToInbox(WidgetTester tester) async {
      await tester.ensureVisible(find.text('time.approval.scope.inbox'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('time.approval.scope.inbox'));
      await tester.pumpAndSettle();
    }

    /// A submission. [mine] decides whose — and that is the point of the flag: a
    /// lead's own rows appear in their own inbox (the server does not filter them
    /// out, deliberately), and those are exactly the ones they may not decide.
    TimesheetApproval approval({
      String id = 'a1',
      ApprovalStatus status = ApprovalStatus.submitted,
      String? note,
      bool mine = false,
    }) => TimesheetApproval(
      id: id,
      userId: mine ? 'u1' : 'u2',
      projectId: 'p1',
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 8, 31),
      status: status,
      totalMinutes: 420,
      note: note,
    );

    testWidgets('opens on one\'s own submissions, never on the inbox', (
      tester,
    ) async {
      // "Mine" is what every member has; the inbox is for whoever can decide
      // something, and opening on it would show most people an empty page.
      final repository = await open(tester, mine: [approval(mine: true)]);

      expect(repository.scopes, ['mine']);
      expect(find.text('time.approval.status.submitted'), findsOneWidget);
    });

    testWidgets('an empty list says which list is empty', (tester) async {
      await open(tester);

      expect(find.text('time.approval.empty.mine.title'), findsOneWidget);

      await switchToInbox(tester);

      expect(find.text('time.approval.empty.inbox.title'), findsOneWidget);
    });

    testWidgets('switching to the inbox asks the server for the inbox', (
      tester,
    ) async {
      final repository = await open(tester, inbox: [approval()]);

      await switchToInbox(tester);

      expect(repository.scopes, ['mine', 'inbox']);
    });

    testWidgets(
      'decisions are offered in the inbox and not on one\'s own list',
      (tester) async {
        // Nobody signs off their own period. A button that always answered 403
        // would be a worse way to say so.
        await open(tester, mine: [approval()], inbox: [approval()]);
        expect(find.text('time.approval.approveAction'), findsNothing);

        await switchToInbox(tester);

        expect(find.text('time.approval.approveAction'), findsOneWidget);
        expect(find.text('time.approval.rejectAction'), findsOneWidget);
        // Reopen belongs to an approved period, not a pending one.
        expect(find.text('time.approval.reopenAction'), findsNothing);
      },
    );

    testWidgets('and never on one\'s own row, even inside the inbox', (
      tester,
    ) async {
      // A lead who leads the project they submitted to sees their own row there.
      // Nobody signs off their own period, so the buttons are not offered — a
      // button that always answered 403 would be a worse way to say so.
      await open(tester, inbox: [approval(mine: true)]);
      await switchToInbox(tester);

      expect(find.text('time.approval.approveAction'), findsNothing);
      expect(find.text('time.approval.rejectAction'), findsNothing);
    });

    testWidgets('an approved period offers the reopen instead', (tester) async {
      await open(tester, inbox: [approval(status: ApprovalStatus.approved)]);
      await switchToInbox(tester);

      expect(find.text('time.approval.reopenAction'), findsOneWidget);
      expect(find.text('time.approval.approveAction'), findsNothing);
    });

    testWidgets('a rejection\'s reason is on the card, not a tap away', (
      tester,
    ) async {
      await open(
        tester,
        mine: [
          approval(
            mine: true,
            status: ApprovalStatus.rejected,
            note: 'Friday is missing',
          ),
        ],
      );

      expect(find.text('Friday is missing'), findsOneWidget);
    });

    testWidgets('sending a period back asks for a reason and refuses none', (
      tester,
    ) async {
      final repository = await open(tester, inbox: [approval()]);
      await switchToInbox(tester);

      await tester.tap(find.text('time.approval.rejectAction'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Thursday is doubled');
      await tester.pumpAndSettle();
      // The dialog's own confirm, not the card's button that opened it: both
      // carry the same label, and tapping the card again would reopen the dialog.
      await tester.tap(
        find.widgetWithText(FilledButton, 'time.approval.rejectAction'),
      );
      await tester.pumpAndSettle();

      expect(repository.rejected, [('a1', 'Thursday is doubled')]);
      await tester.pumpAndSettle(const Duration(seconds: 6));
    });
  });
}

// --- fakes -----------------------------------------------------------------

class _FakeTimeRepository implements TimeRepository {
  _FakeTimeRepository({this.mine = const [], this.inbox = const []});

  final List<TimesheetApproval> mine;
  final List<TimesheetApproval> inbox;

  final List<String> scopes = [];
  final List<(String, String)> corrections = [];
  final List<(String, String)> rejected = [];

  @override
  Future<PageResult<TimesheetApproval>> approvals({
    String scope = 'mine',
    ApprovalStatus? status,
    int page = 0,
    int size = 25,
  }) async {
    scopes.add(scope);
    final items = scope == 'inbox' ? inbox : mine;
    return (items: items, total: items.length);
  }

  @override
  Future<void> requestCorrection(String entryId, String note) async =>
      corrections.add((entryId, note));

  @override
  Future<TimesheetApproval> reject(String id, {required String note}) async {
    rejected.add((id, note));
    return mine.isNotEmpty ? mine.first : inbox.first;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUserRepository implements UserRepository {
  const _FakeUserRepository();

  @override
  Future<List<DirectoryUser>> usersByIds(List<String> ids) async => [
    for (final id in ids)
      DirectoryUser(id: id, displayName: 'Ada', username: 'ada'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  const _FakeProjectRepository();

  @override
  Future<List<Project>> resolveProjects(List<String> ids) async => [
    for (final id in ids) Project(id: id, key: 'HIN', name: 'Hinata'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc()
    : super(
        const AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'u1',
            email: 'u1@example.test',
            username: 'u1',
            displayName: 'Ada',
            roles: {'USER'},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
