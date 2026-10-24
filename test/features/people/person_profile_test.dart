import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/person_profile.dart';
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/widgets/glass_panel.dart';
import 'package:hinata/features/admin/users/user_management_cubit.dart';
import 'package:hinata/features/admin/users/user_management_widgets.dart'
    show UserAdminSections;
import 'package:hinata/features/blocks/hidden_content_cubit.dart';
import 'package:hinata/features/people/person_admin_cubit.dart';
import 'package:hinata/features/people/person_profile_cubit.dart';
import 'package:hinata/features/people/person_profile_screen.dart';

import '../../support/recording_fake.dart';
import '../blocks/block_fakes.dart';

/// A person's profile (HIN-165): what every member sees, what an admin sees on
/// top, and how it opens at every width.
///
/// Widget tests render raw i18n keys, so the assertions look for keys.
void main() {
  const mia = PersonProfile(
    id: 'u1',
    displayName: 'Mia Berger',
    username: 'mia',
    title: 'Projektleitung',
    pronouns: 'sie/ihr',
    roles: ['MEMBER'],
    timezone: 'Europe/Berlin',
    sharedTeams: [SharedTeam(id: 't1', name: 'Veranstaltungen', key: 'VER')],
    sharedProjects: [
      SharedProject(id: 'p1', name: 'Sommerfest', key: 'SOF', color: '#AEC6F4'),
    ],
  );

  final asAdmin = PersonProfile.fromJson(const {
    'id': 'u1',
    'displayName': 'Mia Berger',
    'username': 'mia',
    'roles': ['ORG_ADMIN', 'MEMBER'],
    'timezone': 'Europe/Berlin',
    'sharedTeams': <dynamic>[],
    'sharedProjects': <dynamic>[],
    'absenceToday': {
      'type': 'VACATION',
      'from': '2026-10-19',
      'to': '2026-10-23',
    },
    'email': 'mia@example.org',
    'active': true,
    'self': false,
    'canAdmin': true,
  });

  group('the cubit', () {
    test('loads the profile', () async {
      final cubit = PersonProfileCubit(
        _FakeUsers(mia),
        'u1',
        loadClock: () async {},
      );
      await cubit.load();
      expect(cubit.state.status, PersonProfileStatus.ready);
      expect(cubit.state.profile, mia);
      expect(cubit.state.clockReady, isTrue);
    });

    test('an unknown or deactivated account is not found', () async {
      final cubit = PersonProfileCubit(
        _FakeUsers(null),
        'gone',
        loadClock: () async {},
      );
      await cubit.load();
      expect(cubit.state.status, PersonProfileStatus.notFound);
      expect(cubit.state.profile, isNull);
    });

    test('reads the wire, absence and address included', () {
      expect(asAdmin.isOrgAdmin, isTrue);
      expect(asAdmin.absenceToday!.to, DateTime(2026, 10, 23));
      expect(asAdmin.email, 'mia@example.org');
      // A member's profile carries no address at all.
      expect(mia.email, isNull);
    });
  });

  group('a member', () {
    testWidgets('sees the shared profile and no administration', (
      tester,
    ) async {
      await _pumpPage(tester, mia, width: 390);
      expect(find.text('Mia Berger'), findsWidgets);
      expect(find.text('@mia'), findsOneWidget);
      expect(find.text('Veranstaltungen'), findsOneWidget);
      expect(find.text('Sommerfest'), findsOneWidget);
      expect(find.text('people.issues'), findsOneWidget);
      // No address, so no e-mail; no administration either.
      expect(find.text('people.email'), findsNothing);
      expect(find.text('people.admin'), findsNothing);
      expect(find.byType(UserAdminSections), findsNothing);
    });

    testWidgets('"issues of this person" opens the filtered list', (
      tester,
    ) async {
      final router = await _pumpPage(tester, mia, width: 390);
      await tester.tap(find.text('people.issues'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/issues?assignee=u1');
    });

    testWidgets('a shared team opens the team', (tester) async {
      final router = await _pumpPage(tester, mia, width: 390);
      await tester.tap(find.text('Veranstaltungen'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), '/teams/t1');
    });
  });

  group('an admin', () {
    testWidgets('sees the administration of the admin area', (tester) async {
      await _pumpPage(tester, asAdmin, width: 390, admin: true);
      expect(find.text('people.email'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('people.admin'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('people.admin'), findsOneWidget);
      expect(find.byType(UserAdminSections), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('admin.um.deleteThisUser'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('admin.um.deleteThisUser'), findsOneWidget);
    });
  });

  group('an admin, leaving', () {
    testWidgets('closes both cubits of the administration', (tester) async {
      final router = await _pumpPage(tester, asAdmin, width: 390, admin: true);
      await tester.scrollUntilVisible(
        find.byType(UserAdminSections),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      final sections = tester.element(find.byType(UserAdminSections));
      final account = sections.read<PersonAdminCubit>();
      final actions = sections.read<UserManagementCubit>();
      expect(account.isClosed, isFalse);

      router.go('/issues');
      await tester.pumpAndSettle();
      expect(account.isClosed, isTrue);
      expect(actions.isClosed, isTrue);
    });
  });

  group('blocking (HIN-168)', () {
    testWidgets('a member can block somebody else, after a question', (
      tester,
    ) async {
      final account = FakeAccountRepository()..answer<void>(#block, null);
      final hidden = await hiddenContent(account);
      addTearDown(hidden.close);
      await _pumpPage(tester, mia, width: 390, hidden: hidden);
      await tester.scrollUntilVisible(
        find.text('blocks.profile.block'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('blocks.profile.section'), findsOneWidget);

      await tester.tap(find.text('blocks.profile.block'));
      await tester.pumpAndSettle();
      expect(find.text('blocks.confirm.title'), findsOneWidget);
      await tester.tap(find.text('blocks.confirm.button'));
      await tester.pumpAndSettle();

      expect(account.only, invoked(#block, positional: ['u1']));
      expect(hidden.state.blocks('u1'), isTrue);
      expect(find.text('blocks.profile.unblock'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('a blocked person offers lifting it, without a question', (
      tester,
    ) async {
      final account = FakeAccountRepository()..answer<void>(#unblock, null);
      final hidden = await hiddenContent(account, blocked: {'u1'});
      addTearDown(hidden.close);
      await _pumpPage(tester, mia, width: 390, hidden: hidden);
      await tester.scrollUntilVisible(
        find.text('blocks.profile.unblock'),
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(find.text('blocks.profile.unblock'));
      await tester.pumpAndSettle();

      expect(account.only, invoked(#unblock, positional: ['u1']));
      expect(find.text('blocks.profile.block'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets("one's own profile has nothing to block", (tester) async {
      final hidden = await hiddenContent(FakeAccountRepository());
      addTearDown(hidden.close);
      const me = PersonProfile(
        id: 'u1',
        displayName: 'Mia Berger',
        username: 'mia',
        roles: ['MEMBER'],
        self: true,
      );
      await _pumpPage(tester, me, width: 390, hidden: hidden);
      expect(find.text('blocks.profile.section'), findsNothing);
      expect(find.text('blocks.profile.block'), findsNothing);
    });

    testWidgets('a server without blocking offers none', (tester) async {
      final hidden = await hiddenContent(FakeAccountRepository());
      addTearDown(hidden.close);
      await _pumpPage(
        tester,
        mia,
        width: 390,
        hidden: hidden,
        moderation: false,
      );
      expect(find.text('blocks.profile.section'), findsNothing);
    });
  });

  group('how it opens', () {
    testWidgets('wide: a panel from the right over the page', (tester) async {
      final router = await _pumpPage(
        tester,
        mia,
        width: 1280,
        openFromPage: true,
      );
      expect(find.byType(GlassFloatingSurface), findsOneWidget);
      // The panel sits against the right edge.
      final panel = tester.getRect(find.byType(GlassFloatingSurface));
      expect(panel.right, greaterThan(1280 - 40));
      expect(panel.width, lessThan(500));
      // The page it was opened from is still there beneath it.
      expect(find.text('home', skipOffstage: false), findsOneWidget);
      expect(router.state.uri.toString(), '/people/u1');

      await tester.tap(find.byTooltip('common.close'));
      await tester.pumpAndSettle();
      expect(find.byType(GlassFloatingSurface), findsNothing);
      expect(router.state.uri.toString(), '/');
    });

    testWidgets('compact: a page of its own', (tester) async {
      await _pumpPage(tester, mia, width: 390, openFromPage: true);
      expect(find.byType(GlassFloatingSurface), findsNothing);
      expect(find.text('people.issues'), findsOneWidget);
      expect(find.byTooltip('common.close'), findsNothing);
    });

    testWidgets('a link opened cold is a page even on a wide window', (
      tester,
    ) async {
      await _pumpPage(tester, mia, width: 1280);
      expect(find.byType(GlassFloatingSurface), findsNothing);
      expect(find.text('people.issues'), findsOneWidget);
    });

    testWidgets('a person who is not there says so', (tester) async {
      await _pumpPage(tester, null, width: 390);
      expect(find.text('people.notFound.title'), findsOneWidget);
    });
  });

  group('every width and text size', () {
    for (final width in const [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets('${width.toInt()} px at ${(scale * 100).toInt()} %', (
          tester,
        ) async {
          await _pumpPage(
            tester,
            asAdmin,
            width: width,
            textScale: scale,
            admin: true,
            openFromPage: true,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Mia Berger'), findsWidgets);
          await tester.scrollUntilVisible(
            find.text('admin.um.deleteThisUser'),
            300,
            scrollable: find.byType(Scrollable).last,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}

Future<GoRouter> _pumpPage(
  WidgetTester tester,
  PersonProfile? profile, {
  required double width,
  double textScale = 1,
  bool admin = false,
  bool openFromPage = false,
  HiddenContentCubit? hidden,
  bool moderation = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: openFromPage ? '/' : '/people/u1',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
      ),
      GoRoute(
        path: '/people/:id',
        pageBuilder: (context, state) => personProfilePage(
          context,
          state,
          fullPage: (state, child) => MaterialPage(
            key: state.pageKey,
            child: Scaffold(body: child),
          ),
        ),
      ),
      GoRoute(
        path: '/issues',
        builder: (_, state) => Scaffold(body: Text('at ${state.uri}')),
      ),
      GoRoute(
        path: '/teams/:id',
        builder: (_, state) => Scaffold(body: Text('at ${state.uri}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<UserRepository>.value(value: _FakeUsers(profile)),
        RepositoryProvider<AdminRepository>.value(value: _FakeAdmin()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>.value(value: _FakeAuthBloc(admin: admin)),
          if (hidden != null) ...[
            BlocProvider<AppConfigBloc>.value(
              value: ModerationAppConfig(supported: moderation),
            ),
            BlocProvider<HiddenContentCubit>.value(value: hidden),
          ],
        ],
        child: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (openFromPage) {
    openPersonProfile(tester.element(find.text('home')), 'u1');
    await tester.pumpAndSettle();
  }
  return router;
}

class _FakeUsers implements UserRepository {
  _FakeUsers(this.person);
  final PersonProfile? person;

  @override
  Future<PersonProfile> profile(String id) async {
    final found = person;
    if (found == null) {
      throw ApiFailure('error.notFound', statusCode: 404);
    }
    return found;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

const _miaAccount = AdminUser(
  id: 'u1',
  name: 'Mia Berger',
  username: 'mia',
  email: 'mia@example.org',
  title: 'Projektleitung',
  role: AdminRole.user,
  orgAdmin: true,
  origin: UserOrigin.local,
  status: UserStatus.active,
  twoFA: false,
  sso: false,
  sessions: 2,
);

class _FakeAdmin implements AdminRepository {
  @override
  Future<AdminUser> adminUser(String id) async => _miaAccount;

  @override
  Future<AdminUserPage> adminUsersPage({
    String query = '',
    UserRoleFilter? role,
    UserStatus? status,
    UserOrigin? origin,
    UserSortKey sort = UserSortKey.lastActive,
    bool desc = true,
    int page = 1,
    int perPage = 25,
  }) async => AdminUserPage(
    items: const [_miaAccount],
    total: 1,
    page: 1,
    perPage: perPage,
    counts: AdminUserCounts.empty,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc({required bool admin})
    : super(
        AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'me',
            email: 'me@example.org',
            username: 'me',
            displayName: 'Me',
            roles: admin ? const {'ADMIN'} : const {'MEMBER'},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
