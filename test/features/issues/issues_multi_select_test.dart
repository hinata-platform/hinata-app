/// Selecting several issues on the Issues page, and what can be done with them.
///
/// Pinned here: one deadline reaches the server for exactly the ticked issues,
/// counted the way their project counts, and the answer replaces the rows in
/// place; every layout can switch into selection without a long press, which
/// neither a mouse nor a screen reader does; and a phone is told about the
/// long press once, not on every visit.
///
/// Nothing asserts on translated copy: widget tests render raw i18n keys.
/// Never `pumpAndSettle`: the glass surfaces keep scheduling frames.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/events/issue_events.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/widgets/glass_bulk_bar.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/features/issues/issues_screen.dart';
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = 'https://server.test';

List<Issue> get _issues => [
  for (var i = 1; i <= 5; i++)
    Issue(
      id: 'i$i',
      projectId: 'p1',
      readableId: 'MOB-$i',
      title: 'Issue number $i',
      state: 'OPEN',
    ),
];

/// The one project every issue sits in: it has an event date to count from and
/// counts in working days, overriding the organisation's calendar days.
final _project = Project(
  id: 'p1',
  key: 'MOB',
  name: 'Mobile App',
  eventDate: DateTime(2026, 12, 1),
  deadlineBasis: RelativeDateBasis.working,
);

void main() {
  late _FakeIssueRepository issueRepo;

  setUp(() => issueRepo = _FakeIssueRepository(_issues));

  Future<void> settle(WidgetTester tester, [int frames = 4]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    required double width,
    bool templates = true,
    AppStorage? storage,
    List<Issue>? issues,
  }) async {
    if (issues != null) issueRepo = _FakeIssueRepository(issues);
    tester.view
      ..physicalSize = Size(width, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chrome = PageChromeController();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IssueRepository>.value(value: issueRepo),
          RepositoryProvider<ProjectRepository>.value(
            value: _FakeProjectRepository(),
          ),
          RepositoryProvider<UserRepository>.value(
            value: _FakeUserRepository(),
          ),
          if (storage != null)
            RepositoryProvider<AppStorage>.value(value: storage),
        ],
        child: BlocProvider<AppConfigBloc>.value(
          value: _FixedAppConfig(templates: templates),
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/issues',
              routes: [
                GoRoute(
                  path: '/issues',
                  builder: (_, _) => PageChromeScope(
                    controller: chrome,
                    child: const Scaffold(body: IssuesScreen()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await settle(tester, 3);
  }

  TextButton action(WidgetTester tester, String key) => tester.widget(
    find.ancestor(of: find.text(key), matching: find.byType(TextButton)),
  );

  group('bulk deadline', () {
    testWidgets('sends one rule for exactly the ticked issues', (tester) async {
      await open(tester, width: 1400);

      await tester.longPress(find.text('Issue number 1'));
      await settle(tester, 2);
      await tester.tap(find.text('Issue number 3'));
      await settle(tester, 2);

      await tester.tap(find.text('issues.bulkDeadline.action'));
      await settle(tester);
      // One project and the module on: rules are offered.
      // The raw key in the test font is wider than the 300 px switch bar, so
      // its centre lies outside the chip; call the chip instead of tapping.
      tester
          .widget<GlassSwitchChip>(
            find.ancestor(
              of: find.text('issues.deadline.modeOffset'),
              matching: find.byType(GlassSwitchChip),
            ),
          )
          .onTap!();
      await settle(tester, 6);
      await tester.tap(find.text('common.apply'));
      await settle(tester);

      expect(issueRepo.bulkCalls, hasLength(1));
      final call = issueRepo.bulkCalls.single;
      expect(call.ids.toSet(), {'i1', 'i3'});
      expect(call.dueDate, isNull);
      expect(call.clear, isFalse);
      // Four weeks before is the editor's starting rule; the basis is the
      // project's working days, not the organisation's calendar days.
      expect(call.dueOffset?.amount, -4);
      expect(call.dueOffset?.unit, RelativeDateUnit.weeks);
      expect(call.dueOffset?.basis, RelativeDateBasis.working);

      // Done: the selection is gone with its bar.
      expect(find.byType(GlassBulkBar), findsNothing);
      // Let the success toast run out.
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('swaps in the answered rows instead of reloading', (
      tester,
    ) async {
      final heard = <Object?>[];
      final sub = IssueEvents.instance.changes.listen(heard.add);
      addTearDown(sub.cancel);
      await open(tester, width: 1400);
      final loads = issueRepo.listCalls;

      await tester.longPress(find.text('Issue number 2'));
      await settle(tester, 2);
      await tester.tap(find.text('issues.bulkDeadline.action'));
      await settle(tester);
      await tester.tap(find.text('common.clear'));
      await settle(tester);

      // The server answers with the renamed row, and that is what shows.
      expect(find.text('Issue number 2 (updated)'), findsOneWidget);
      // No trip back to page 0 for it.
      expect(issueRepo.listCalls, loads);
      // The other screens still hear of it, marked as this screen's own.
      expect(heard, hasLength(1));
      expect(heard.single, isNotNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('knows the project of a ticked row that a reload took away', (
      tester,
    ) async {
      await open(tester, width: 1400);

      await tester.longPress(find.text('Issue number 1'));
      await settle(tester, 2);
      // Something elsewhere changed the list, and the ticked row is gone from
      // the rows now loaded.
      issueRepo.all.removeAt(0);
      IssueEvents.instance.notifyChanged();
      await settle(tester, 3);
      expect(find.text('Issue number 1'), findsNothing);

      await tester.tap(find.text('issues.bulkDeadline.action'));
      await settle(tester);
      // Still one project, so rules are still on offer.
      expect(find.text('issues.deadline.modeOffset'), findsOneWidget);
      await tester.tap(find.text('common.clear'));
      await settle(tester);
      expect(issueRepo.bulkCalls.single.ids, ['i1']);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a new sort starts over without the old selection', (
      tester,
    ) async {
      await open(tester, width: 1400);

      await tester.tap(find.byTooltip('issues.selection.enter'));
      await settle(tester, 2);
      await tester.tap(find.text('Issue number 2'));
      await settle(tester, 2);
      expect(action(tester, 'issues.bulkDeadline.action').onPressed, isNotNull);

      await tester.tap(find.text('issues.sort.label'));
      await settle(tester);
      await tester.tap(find.text('issues.sort.createdAsc').last);
      await settle(tester);

      // The mode asked for stays; what was ticked in the old order does not.
      expect(find.byType(GlassBulkBar), findsOneWidget);
      expect(action(tester, 'issues.bulkDeadline.action').onPressed, isNull);
    });

    testWidgets('clears the deadline of every ticked issue', (tester) async {
      await open(tester, width: 1400);

      await tester.longPress(find.text('Issue number 2'));
      await settle(tester, 2);
      await tester.tap(find.text('issues.bulkDeadline.action'));
      await settle(tester);
      await tester.tap(find.text('common.clear'));
      await settle(tester);

      expect(issueRepo.bulkCalls.single.ids, ['i2']);
      expect(issueRepo.bulkCalls.single.clear, isTrue);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('select all ticks every row on screen', (tester) async {
      await open(tester, width: 1400);

      await tester.longPress(find.text('Issue number 4'));
      await settle(tester, 2);
      await tester.tap(find.text('issues.selectAll'));
      await settle(tester, 2);
      await tester.tap(find.text('issues.bulkDeadline.action'));
      await settle(tester);
      await tester.tap(find.text('common.clear'));
      await settle(tester);

      expect(issueRepo.bulkCalls.single.ids.toSet(), {
        for (final issue in _issues) issue.id,
      });
      await tester.pump(const Duration(seconds: 10));
    });
  });

  group('selection toggle', () {
    testWidgets('enters selection with nothing selected and stays there', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await open(tester, width: 1400);

      expect(find.byType(GlassBulkBar), findsNothing);
      expect(
        tester.getSemantics(find.byTooltip('issues.selection.enter')),
        isSemantics(hasToggledState: true, isToggled: false),
      );

      await tester.tap(find.byTooltip('issues.selection.enter'));
      await settle(tester, 2);

      expect(find.byType(GlassBulkBar), findsOneWidget);
      expect(
        tester.getSemantics(find.byTooltip('issues.selection.exit').first),
        isSemantics(hasToggledState: true, isToggled: true),
      );
      // Nothing ticked yet: the actions are there, and inert.
      expect(action(tester, 'issues.bulkDeadline.action').onPressed, isNull);
      expect(action(tester, 'issues.move.action').onPressed, isNull);

      // Ticking and unticking a row does not end a mode somebody asked for.
      await tester.tap(find.text('Issue number 2'));
      await settle(tester, 2);
      expect(action(tester, 'issues.bulkDeadline.action').onPressed, isNotNull);
      await tester.tap(find.text('Issue number 2'));
      await settle(tester, 2);
      expect(find.byType(GlassBulkBar), findsOneWidget);

      // The same button leaves again. (The bar's ✕ shares its tooltip.)
      await tester.tap(find.byTooltip('issues.selection.exit').first);
      await settle(tester, 2);
      expect(find.byType(GlassBulkBar), findsNothing);
      semantics.dispose();
    });

    // 600: still the phone layout, and wide enough for the bar's raw i18n
    // keys, which run far longer than any real label.
    testWidgets('is offered on a phone too, for whoever cannot hold', (
      tester,
    ) async {
      await open(tester, width: 600);

      await tester.tap(find.byTooltip('issues.selection.enter'));
      await settle(tester, 2);
      expect(find.byType(GlassBulkBar), findsOneWidget);
    });

    testWidgets('a row offers "select" as a named action', (tester) async {
      await open(tester, width: 600);

      final rows = tester.widgetList<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.customSemanticsActions != null,
        ),
      );
      expect(rows, hasLength(_issues.length));
      final select = rows.first.properties.customSemanticsActions!;
      expect(select.keys.single.label, 'issues.selection.select');

      select.values.single();
      await settle(tester, 2);
      expect(find.byType(GlassBulkBar), findsOneWidget);
    });
  });

  group('phone tip', () {
    Future<AppStorage> storage([Map<String, Object> extra = const {}]) async {
      SharedPreferences.setMockInitialValues({
        'server_url': _server,
        'servers.v1': '[{"url":"$_server"}]',
        ...extra,
      });
      return AppStorage(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );
    }

    testWidgets('shows once and stays away after "got it"', (tester) async {
      final store = await storage();
      await open(tester, width: 390, storage: store);

      expect(find.text('issues.multiSelectHint.text'), findsOneWidget);

      await tester.tap(find.text('issues.multiSelectHint.gotIt'));
      await settle(tester, 2);

      expect(find.text('issues.multiSelectHint.text'), findsNothing);
      expect(store.multiSelectHintSeen, isTrue);

      // The next visit to the page.
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, width: 390, storage: store);
      expect(find.text('issues.multiSelectHint.text'), findsNothing);
    });

    testWidgets('can be activated from a screen reader', (tester) async {
      final semantics = tester.ensureSemantics();
      final store = await storage();
      await open(tester, width: 390, storage: store);

      expect(
        tester.getSemantics(find.text('issues.multiSelectHint.gotIt')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('is not shown where there is no row to press', (tester) async {
      await open(tester, width: 390, storage: await storage(), issues: []);

      expect(find.text('issues.multiSelectHint.text'), findsNothing);
    });

    testWidgets('is not shown on a wide window', (tester) async {
      await open(tester, width: 1400, storage: await storage());

      expect(find.text('issues.multiSelectHint.text'), findsNothing);
    });
  });
}

typedef _BulkCall = ({
  List<String> ids,
  DateTime? dueDate,
  RelativeDate? dueOffset,
  bool clear,
});

class _FakeIssueRepository implements IssueRepository {
  _FakeIssueRepository(this.all);

  final List<Issue> all;
  final List<_BulkCall> bulkCalls = [];

  /// How often the list was read, page 0 or later.
  int listCalls = 0;

  @override
  Future<List<Issue>> bulkSetDeadline(
    List<String> issueIds, {
    DateTime? dueDate,
    RelativeDate? dueOffset,
    bool clearDueDate = false,
  }) async {
    bulkCalls.add((
      ids: issueIds,
      dueDate: dueDate,
      dueOffset: dueOffset,
      clear: clearDueDate,
    ));
    return [
      for (final issue in all)
        if (issueIds.contains(issue.id))
          Issue(
            id: issue.id,
            projectId: issue.projectId,
            readableId: issue.readableId,
            title: '${issue.title} (updated)',
            state: issue.state,
          ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #issues => () {
          listCalls++;
          return Future<({List<Issue> issues, int total})>.value((
            issues: [...all],
            total: all.length,
          ));
        }(),
        _ => throw UnimplementedError('${invocation.memberName} is not faked'),
      };
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> projects({
    bool archived = false,
    bool? template,
  }) async => [_project];

  @override
  Future<DateTime?> resolveOffset(
    String id, {
    required RelativeDate offset,
    DateTime? eventDate,
  }) async => DateTime(2026, 11, 3);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUserRepository implements UserRepository {
  @override
  Future<List<DirectoryUser>> users() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// One fixed answer about the server: project templates on or off, calendar
/// days as the organisation's default.
class _FixedAppConfig extends AppConfigBloc {
  _FixedAppConfig({required bool templates})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          featureFlags: {PlatformFlags.projectTemplates: templates},
        ),
      ),
      super(repository: _UnusedMeta(), storage: _UnusedStorage());

  final AppConfigState _fixed;

  @override
  AppConfigState get state => _fixed;
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
