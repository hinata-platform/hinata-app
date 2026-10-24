import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/models/person_profile.dart';
import 'package:hinata/core/repositories/moderation_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/glass_scope_row.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/moderation/decision/decision_dialog.dart';
import 'package:hinata/features/moderation/queue/case_row.dart';
import 'package:hinata/features/moderation/queue/moderation_screen.dart';
import 'package:hinata/features/moderation/widgets/moderation_hex.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/moderation/widgets/statement_view.dart';
import 'package:hinata/features/sprint/modals/glass_modal.dart'
    show GlassField, GlassOptionRow;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/recording_fake.dart';
import 'case_fixtures.dart';

/// The moderation page (HIN-174): the lists, a case beside them or on its own
/// page, and the decision. Nothing here asserts on translated copy: widget
/// tests render raw i18n keys.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  late FakeModerationRepository moderation;
  late FakeUserRepository users;

  setUp(() {
    moderation = FakeModerationRepository()
      ..answer<ModerationSummary>(
        #summary,
        const ModerationSummary(open: 2, appeals: 1),
      )
      ..answer<({List<CaseSummary> items, int total})>(#cases, (
        items: [
          caseRow(id: 'k0', state: CaseState.urgent),
          caseRow(),
        ],
        total: 2,
      ))
      ..answer<CaseDetail>(#detail, caseDetail());
    users = FakeUserRepository()
      ..answer<List<DirectoryUser>>(#usersByIds, const [
        DirectoryUser(id: jonas, username: jonas, displayName: 'Jonas Becker'),
      ])
      ..answer<PersonProfile>(
        #profile,
        const PersonProfile(
          id: jonas,
          displayName: 'Jonas Becker',
          username: jonas,
        ),
      );
  });

  Widget app(Widget child, {double textScale = 1}) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<ModerationRepository>.value(value: moderation),
      RepositoryProvider<UserRepository>.value(value: users),
    ],
    child: BlocProvider<AuthBloc>(
      create: (_) => _FakeAuthBloc(),
      child: MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: app!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
    String? caseId,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(ModerationScreen(caseId: caseId), textScale: textScale),
    );
    await tester.pumpAndSettle();
  }

  group('a row', () {
    Future<void> pumpRow(WidgetTester tester, CaseSummary summary) async {
      await tester.pumpWidget(
        app(
          CaseRow(
            summary: summary,
            now: reportedAt.add(const Duration(hours: 26)),
            onTap: () {},
          ),
        ),
      );
    }

    testWidgets('every state has its word and its glyph', (tester) async {
      final semantics = tester.ensureSemantics();
      for (final (summary, word, glyph) in [
        (caseRow(), 'open', LucideIcons.flag),
        (caseRow(state: CaseState.urgent), 'urgent', LucideIcons.siren),
        (caseRow(state: CaseState.inReview), 'inReview', LucideIcons.eye),
        (
          caseRow(state: CaseState.pendingConfirmation),
          'pending',
          LucideIcons.usersRound,
        ),
        (caseRow(state: CaseState.appeal), 'appeal', LucideIcons.rotateCcw),
        (
          const CaseSummary(id: 'r', state: CaseState.acted, removed: true),
          'removed',
          LucideIcons.eyeOff,
        ),
        (
          const CaseSummary(id: 's', state: CaseState.acted, suspended: true),
          'suspended',
          LucideIcons.userX,
        ),
        (
          const CaseSummary(id: 'h', state: CaseState.acted),
          'handled',
          LucideIcons.clipboardCheck,
        ),
        (
          const CaseSummary(id: 'c', state: CaseState.noAction),
          'clear',
          LucideIcons.check,
        ),
      ]) {
        await pumpRow(tester, summary);
        // The row is one button to a screen reader, its state named first.
        expect(
          tester.getSemantics(find.byType(CaseRow)).label,
          startsWith('moderation.state.$word'),
          reason: word,
        );
        expect(find.byType(ModerationHex), findsOneWidget);
        expect(find.byIcon(glyph), findsOneWidget, reason: word);
      }
      semantics.dispose();
    });

    testWidgets('overdue says so in words and with its own glyph', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpRow(tester, caseRow(overdue: true));
      expect(find.byIcon(LucideIcons.alarmClock), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(CaseRow)).label,
        contains('moderation.case.waitedOverdue'),
      );
      semantics.dispose();
    });

    testWidgets('a case the reader holds says so instead of a name', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          CaseRow(
            summary: caseRow(
              state: CaseState.inReview,
              assignee: const PersonRef(id: 'sara', displayName: 'Sara Klein'),
            ),
            now: reportedAt,
            meId: 'sara',
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('moderation.queue.withYou'), findsOneWidget);
      expect(find.textContaining('Sara Klein'), findsNothing);
    });

    testWidgets('sexual content and the safety of children stay covered', (
      tester,
    ) async {
      await pumpRow(
        tester,
        caseRow(
          kind: ContentKind.attachment,
          categories: const [ReportCategory.sexual],
          listExcerpt: 'Etwas, das nicht in der Liste stehen soll',
        ),
      );
      expect(find.text('moderation.queue.imageCovered'), findsOneWidget);
      expect(
        find.text('Etwas, das nicht in der Liste stehen soll'),
        findsNothing,
      );
    });
  });

  group('the page', () {
    /// The shell draws a page's docked row in its own bar, above the page's
    /// navigator and outside everything the page provides.
    testWidgets('on a phone the pills render in the shell bar, with their '
        'numbers', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final chrome = PageChromeController();
      addTearDown(chrome.dispose);
      final router = GoRouter(
        initialLocation: '/moderation',
        routes: [
          GoRoute(
            path: '/moderation',
            builder: (_, _) => const Scaffold(body: ModerationScreen()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ModerationRepository>.value(value: moderation),
            RepositoryProvider<UserRepository>.value(value: users),
          ],
          child: BlocProvider<AuthBloc>(
            create: (_) => _FakeAuthBloc(),
            child: PageChromeScope(
              controller: chrome,
              child: MaterialApp.router(
                routerConfig: router,
                builder: (context, page) => Column(
                  children: [
                    SizedBox(
                      height: 64,
                      child: ListenableBuilder(
                        listenable: chrome,
                        builder: (_, _) =>
                            chrome.bottomFor('/moderation') ??
                            const SizedBox.shrink(),
                      ),
                    ),
                    Expanded(child: page!),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(GlassScopeRow), findsOneWidget);
      expect(find.text('moderation.queue.viewCount'), findsNWidgets(2));
    });

    testWidgets('a step changes the case\'s row in place, and a case decided '
        'meanwhile leaves the open list with its numbers read again', (
      tester,
    ) async {
      var reads = 0;
      CaseDetail read() {
        reads++;
        return switch (reads) {
          1 => caseDetail(),
          2 => caseDetail(
            summary: caseRow(
              state: CaseState.inReview,
              assignee: const PersonRef(id: 'sara', displayName: 'Sara Klein'),
              rev: 4,
            ),
          ),
          _ => caseDetail(
            summary: caseRow(
              state: CaseState.acted,
              outcome: CaseOutcome.action,
              rev: 5,
            ),
          ),
        };
      }

      moderation
        ..answerWith(#detail, (_) => Future.value(read()))
        ..answer<CaseSummary>(#claim, caseRow())
        ..answer<CaseSummary>(#release, caseRow());
      await pumpPage(tester, size: const Size(1400, 1400), caseId: 'k1');
      int calls(Symbol member) =>
          moderation.calls.where((call) => call.memberName == member).length;
      final summaries = calls(#summary);

      await tester.tap(find.text('moderation.case.claim'));
      await tester.pumpAndSettle();
      expect(calls(#cases), 1, reason: 'the row changes in place');
      expect(calls(#summary), summaries, reason: 'no number moved');
      expect(
        tester
            .widgetList<CaseRow>(find.byType(CaseRow))
            .map((row) => row.summary.state),
        contains(CaseState.inReview),
      );

      await tester.tap(find.text('moderation.case.release'));
      await tester.pumpAndSettle();
      expect(find.byType(CaseRow), findsOneWidget);
      expect(calls(#cases), 1);
      expect(calls(#summary), summaries + 1);
    });

    testWidgets('on a phone at twice the text size: the list, urgent first', (
      tester,
    ) async {
      await pumpPage(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      final rows = find.byType(CaseRow);
      expect(rows, findsNWidgets(2));
      expect(
        tester.widget<CaseRow>(rows.first).summary.state,
        CaseState.urgent,
      );
    });

    testWidgets('nothing to review says what comes next', (tester) async {
      moderation.answer<({List<CaseSummary> items, int total})>(#cases, (
        items: const [],
        total: 0,
      ));
      await pumpPage(tester);
      expect(find.text('moderation.queue.empty.open'), findsOneWidget);
    });

    testWidgets('a list that does not load offers to try again', (
      tester,
    ) async {
      moderation.fail(#cases, ApiFailure('Offline', statusCode: 0));
      await pumpPage(tester);
      expect(find.text('moderation.queue.failedTitle'), findsOneWidget);
      expect(find.text('common.retry'), findsOneWidget);
    });

    testWidgets('on a wide window the list and the case stand side by side', (
      tester,
    ) async {
      await pumpPage(tester, size: const Size(1400, 1000), caseId: 'k1');
      expect(tester.takeException(), isNull);
      expect(find.byType(CaseRow), findsNWidgets(2));
      // Section labels are set in capitals.
      expect(find.text('MODERATION.CASE.REPORTED'), findsOneWidget);
      expect(find.text('moderation.case.decide'), findsOneWidget);
    });
  });

  group('a case', () {
    Future<void> pumpCase(WidgetTester tester, CaseDetail detail) async {
      moderation.answer<CaseDetail>(#detail, detail);
      // A fresh page, so the case is read again rather than kept.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpPage(tester, size: const Size(1400, 1400), caseId: 'k1');
    }

    testWidgets('says whether its content changed since it was reported', (
      tester,
    ) async {
      await pumpCase(tester, caseDetail());
      expect(
        find.textContaining('moderation.case.since.unchanged'),
        findsOneWidget,
      );

      await pumpCase(tester, caseDetail(currentHash: 'b'));
      expect(
        find.textContaining('moderation.case.since.changed'),
        findsOneWidget,
      );

      await pumpCase(tester, caseDetail(noCurrent: true));
      expect(
        find.textContaining('moderation.case.since.deleted'),
        findsOneWidget,
      );
    });

    testWidgets('withheld content waits for a second person', (tester) async {
      await pumpCase(tester, caseDetail(withheld: true));
      expect(find.text('moderation.case.withheld'), findsOneWidget);
      expect(find.text('moderation.case.askToOpen'), findsOneWidget);
      expect(find.text('MODERATION.CASE.REPORTED'), findsNothing);
    });

    testWidgets('a removal still under way says so', (tester) async {
      await pumpCase(
        tester,
        caseDetail(
          summary: caseRow(state: CaseState.acted),
          removalIncomplete: true,
        ),
      );
      expect(find.text('moderation.case.removalIncomplete'), findsOneWidget);
    });

    testWidgets('files about the safety of children are never offered', (
      tester,
    ) async {
      const file = CaseMedia(
        fileName: 'bild.jpg',
        contentType: 'image/jpeg',
        size: 2048,
      );
      await pumpCase(
        tester,
        caseDetail(
          summary: caseRow(categories: const [ReportCategory.childSafety]),
          evidence: comment(media: const [file]),
        ),
      );
      expect(find.text('bild.jpg'), findsOneWidget);
      expect(find.text('moderation.case.viewFile'), findsNothing);
      expect(find.text('moderation.case.filesNeverShown'), findsOneWidget);

      await pumpCase(
        tester,
        caseDetail(evidence: comment(media: const [file])),
      );
      expect(find.text('moderation.case.viewFile'), findsOneWidget);
    });

    testWidgets('the one main step is a button that works', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCase(tester, caseDetail());
      expect(
        tester.getSemantics(find.text('moderation.case.decide')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });
  });

  testWidgets('the statement preview is not read out again on every change', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    moderation.answer<ModerationRules>(
      #rules,
      const ModerationRules(
        rules: [HouseRule(2, 'Niemanden herabsetzen')],
        categoryRules: {ReportCategory.harassment: 2},
      ),
    );
    moderation.answer<Statement>(
      #statementPreview,
      const Statement(caseId: 'k1', measure: 'Dein Kommentar wurde entfernt.'),
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDecisionDialog(context, caseDetail()),
            child: const Text('decide'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('decide'));
    await tester.pumpAndSettle();
    final action = find.text('moderation.decision.outcome.action');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();

    // It follows the fields keystroke by keystroke.
    expect(
      tester.getSemantics(find.text('Dein Kommentar wurde entfernt.')),
      isSemantics(isLiveRegion: false),
    );
    semantics.dispose();
  });

  testWidgets('what is typed reaches the preview and settles its problem', (
    tester,
  ) async {
    // The form leaves pure typing to the fields; the preview and the problems
    // still follow it.
    moderation.answer<ModerationRules>(
      #rules,
      const ModerationRules(
        rules: [HouseRule(2, 'Niemanden herabsetzen')],
        categoryRules: {ReportCategory.harassment: 2},
      ),
    );
    moderation.answer<Statement>(
      #statementPreview,
      const Statement(caseId: 'k1', measure: 'Dein Kommentar wurde entfernt.'),
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDecisionDialog(context, caseDetail()),
            child: const Text('decide'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('decide'));
    await tester.pumpAndSettle();
    final action = find.text('moderation.decision.outcome.action');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    final facts = find.descendant(
      of: find.ancestor(
        of: find.text('moderation.decision.factsRequired'),
        matching: find.byType(GlassField),
      ),
      matching: find.byType(TextField),
    );
    await tester.enterText(facts, 'Beleidigt eine andere Person mit Namen.');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(StatementView),
        matching: find.textContaining('Beleidigt eine andere Person'),
      ),
      findsOneWidget,
    );

    await tester.enterText(facts, 'Zu kurz.');
    final send = find.text('moderation.decision.send');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(find.text('moderation.decision.problem.facts'), findsOneWidget);
    await tester.enterText(facts, 'Beleidigt eine andere Person mit Namen.');
    await tester.pump();
    expect(find.text('moderation.decision.problem.facts'), findsNothing);
  });

  testWidgets('the decision fits a phone at twice the text size, and the '
      'length of a suspension hugs its choices', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    moderation.answer<ModerationRules>(
      #rules,
      const ModerationRules(
        rules: [HouseRule(2, 'Kein Herabsetzen anderer')],
        categoryRules: {ReportCategory.harassment: 2},
      ),
    );
    moderation.answer<Statement>(
      #statementPreview,
      const Statement(caseId: 'k1', measure: 'Dein Kommentar wurde entfernt.'),
    );
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDecisionDialog(context, caseDetail()),
            child: const Text('decide'),
          ),
        ),
        textScale: 2,
      ),
    );
    await tester.tap(find.text('decide'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final action = find.text('moderation.decision.outcome.action');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    final suspend = find.descendant(
      of: find.ancestor(
        of: find.text('moderation.decision.suspend'),
        matching: find.byType(GlassOptionRow),
      ),
      matching: find.byType(HiveSwitch),
    );
    await tester.ensureVisible(suspend);
    await tester.pumpAndSettle();
    await tester.tap(suspend);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final length = find.text('moderation.suspension.length.days7');
    expect(length, findsOneWidget);
    expect(find.text('moderation.decision.suspendSignOut'), findsOneWidget);
    // As wide as its three choices, never a track across the sheet.
    final bar = find.ancestor(
      of: length,
      matching: find.byType(GlassSwitchBar),
    );
    final chips = tester
        .widgetList<GlassSwitchChip>(
          find.descendant(of: bar, matching: find.byType(GlassSwitchChip)),
        )
        .map((chip) => tester.getSize(find.byWidget(chip)).width)
        .fold<double>(0, (sum, width) => sum + width);
    expect(
      tester.getSize(bar).width,
      lessThanOrEqualTo(chips + GlassSwitchBar.inset + 0.5),
    );
  });
}

class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc()
    : super(
        const AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'sara',
            email: 'sara@example.org',
            username: 'sara',
            displayName: 'Sara Klein',
            roles: {'USER', 'MODERATOR'},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
