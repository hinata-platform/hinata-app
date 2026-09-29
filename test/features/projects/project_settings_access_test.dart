import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/features/projects/settings/project_settings_screen.dart';
import 'package:hinata/features/shell/page_chrome.dart';

/// Project settings (HIN-129): who gets the page, and the deadline basis on it.
///
/// The page is for the project's leads and for the Team-Admins of a team owning
/// it. A platform admin who is neither is bounced like any member. A Team-Admin
/// who does not lead sees no git and no deletion: those stay with the leads.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  const project = Project(
    id: 'p1',
    key: 'FEST',
    name: 'Sommerfest',
    leadIds: ['lead'],
    memberIds: ['lead'],
    workflowStates: [
      WorkflowState(id: 's1', name: 'Open', hue: 210),
      WorkflowState(id: 's2', name: 'Done', hue: 140),
    ],
    resolvedStates: ['Done'],
  );

  AuthUser user(String id, {Set<String> roles = const {'USER'}}) => AuthUser(
    id: id,
    email: '$id@example.org',
    username: id,
    displayName: id,
    roles: roles,
  );

  Team owningTeam(String adminId) => Team(
    id: 't1',
    key: 'KULT',
    name: 'Kultur',
    projectIds: const ['p1'],
    members: [TeamMembership(userId: adminId, role: TeamRole.admin)],
  );

  Future<_FakeProjects> pump(
    WidgetTester tester, {
    required AuthUser me,
    List<Team> teams = const [],
    bool templates = true,
    String orgBasis = 'WORKING',
    Project source = project,
  }) async {
    tester.view.physicalSize = const Size(1400, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final projects = _FakeProjects(source);
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => Scaffold(
            body: PageChromeScope(
              controller: PageChromeController(),
              child: const ProjectSettingsScreen(projectId: 'p1'),
            ),
          ),
        ),
        GoRoute(
          path: '/issues',
          builder: (_, _) => const Scaffold(body: Text('issues')),
        ),
      ],
    );
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ProjectRepository>.value(value: projects),
          RepositoryProvider<UserRepository>.value(value: _FakeUsers()),
          RepositoryProvider<TeamRepository>.value(value: _FakeTeams(teams)),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: _FakeAuthBloc(me)),
            BlocProvider<AppConfigBloc>.value(
              value: _FakeAppConfig(templates: templates, basis: orgBasis),
            ),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    return projects;
  }

  testWidgets('a Team-Admin of an owning team gets the settings', (
    tester,
  ) async {
    await pump(tester, me: user('ta'), teams: [owningTeam('ta')]);

    expect(find.text('issues'), findsNothing);
    expect(find.byType(ProjectSettingsScreen), findsOneWidget);
    // The event date is theirs to move.
    expect(find.text('projectSettings.templates.eventDate'), findsOneWidget);
    // Deletion stays with the leads.
    expect(find.text('projectSettings.dangerZone'), findsNothing);
  });

  testWidgets('a lead gets the settings with the danger zone', (tester) async {
    await pump(tester, me: user('lead'));

    expect(find.text('issues'), findsNothing);
    expect(find.text('projectSettings.dangerZone'), findsOneWidget);
  });

  testWidgets('a platform admin without membership is bounced', (tester) async {
    await pump(tester, me: user('boss', roles: const {'USER', 'ADMIN'}));

    expect(find.text('issues'), findsOneWidget);
  });

  testWidgets('a plain member of the owning team is bounced', (tester) async {
    await pump(
      tester,
      me: user('member'),
      teams: const [
        Team(
          id: 't1',
          key: 'KULT',
          name: 'Kultur',
          projectIds: ['p1'],
          members: [TeamMembership(userId: 'member')],
        ),
      ],
    );

    expect(find.text('issues'), findsOneWidget);
  });

  group('deadline basis', () {
    testWidgets('shows the organisation default the project follows', (
      tester,
    ) async {
      await pump(tester, me: user('lead'), orgBasis: 'WORKING');

      expect(find.text('projects.deadlineBasis.label'), findsOneWidget);
      expect(find.text('projects.deadlineBasis.followsOrg'), findsOneWidget);
      // Following the organisation, nothing to go back to.
      expect(find.text('projects.deadlineBasis.useOrgDefault'), findsNothing);
      final working = tester.widget<GlassSwitchChip>(
        find.widgetWithText(GlassSwitchChip, 'projects.deadlineBasis.working'),
      );
      expect(working.active, isTrue);
    });

    testWidgets('a basis of its own offers the way back', (tester) async {
      await pump(
        tester,
        me: user('lead'),
        orgBasis: 'WORKING',
        source: project.copyWith(deadlineBasis: RelativeDateBasis.calendar),
      );

      final calendar = tester.widget<GlassSwitchChip>(
        find.widgetWithText(GlassSwitchChip, 'projects.deadlineBasis.calendar'),
      );
      expect(calendar.active, isTrue);
      expect(find.text('projects.deadlineBasis.useOrgDefault'), findsOneWidget);
    });

    testWidgets('is not on the page while templates are off', (tester) async {
      await pump(tester, me: user('lead'), templates: false);

      expect(find.text('projects.deadlineBasis.label'), findsNothing);
    });
  });

  group('deadlineBasisPatch', () {
    test('nothing when unchanged', () {
      expect(deadlineBasisPatch(null, null), isEmpty);
      expect(
        deadlineBasisPatch(
          RelativeDateBasis.working,
          RelativeDateBasis.working,
        ),
        isEmpty,
      );
    });

    test('the wire name when a basis is picked', () {
      expect(deadlineBasisPatch(null, RelativeDateBasis.working), {
        'deadlineBasis': 'WORKING',
      });
    });

    test('clearDeadlineBasis when the project follows the org again', () {
      expect(deadlineBasisPatch(RelativeDateBasis.calendar, null), {
        'clearDeadlineBasis': true,
      });
    });
  });
}

class _FakeProjects implements ProjectRepository {
  _FakeProjects(this.source);

  final Project source;

  @override
  Future<Project> project(String id) async => source;

  @override
  Future<Map<String, int>> projectStateUsage(String id) async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUsers implements UserRepository {
  @override
  Future<List<DirectoryUser>> users() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeTeams implements TeamRepository {
  _FakeTeams(this.mine);

  final List<Team> mine;

  @override
  Future<List<Team>> teams() async => mine;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc(AuthUser me)
    : super(AuthState(status: AuthStatus.authenticated, user: me));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAppConfig extends AppConfigBloc {
  _FakeAppConfig({required bool templates, required String basis})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          featureFlags: {PlatformFlags.projectTemplates: templates},
          defaultDeadlineBasis: RelativeDateBasis.fromWire(basis),
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
