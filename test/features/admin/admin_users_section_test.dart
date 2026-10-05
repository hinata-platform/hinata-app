import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/admin_user_models.dart';
import 'package:hinata/core/models/audit_models.dart';
import 'package:hinata/core/models/core_models.dart' show AuthUser;
import 'package:hinata/core/repositories/admin_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/router/app_router.dart' show adminUsersRedirect;
import 'package:hinata/core/widgets/settings_split.dart';
import 'package:hinata/features/admin/admin_screen.dart';
import 'package:hinata/features/admin/users/user_management_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../organization/organization_test_support.dart' show FakeOrgAppConfig;

/// User management is a section of the admin area, the way the audit log is
/// one: it opens in the rail layout's pane instead of on a route of its own,
/// and the old `/admin/users` address lands on it.
///
/// Widget tests render raw i18n keys, so the rail entry reads `admin.users`.
void main() {
  // Wide enough that the table's badges hold their raw i18n keys, which the
  // test font sets far wider than the real labels.
  const desktop = Size(2560, 1200);

  void window(WidgetTester tester, Size size) {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget providers(Widget child) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<AdminRepository>.value(value: _FakeAdmin()),
      RepositoryProvider<MetaRepository>.value(value: _UnusedMeta()),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<AppConfigBloc>.value(value: FakeOrgAppConfig()),
        BlocProvider<AuthBloc>.value(value: _FakeAuthBloc()),
      ],
      child: child,
    ),
  );

  /// The user directory, inside the admin area's rail layout.
  Finder usersInPane() => find.descendant(
    of: find.byWidgetPredicate((w) => w is SettingsSplitLayout),
    matching: find.byType(UserManagementScreen),
  );

  testWidgets(
    'the Benutzer entry shows the directory inside the admin layout',
    (tester) async {
      window(tester, desktop);
      await tester.pumpWidget(
        providers(const MaterialApp(home: Scaffold(body: AdminScreen()))),
      );
      await tester.pumpAndSettle();

      // A plain section entry: no glyph that promises a jump elsewhere.
      expect(find.byIcon(LucideIcons.externalLink), findsNothing);
      expect(find.byType(UserManagementScreen), findsNothing);

      await tester.tap(find.text('admin.users'));
      await tester.pumpAndSettle();

      expect(usersInPane(), findsOneWidget);
      expect(find.text('Mira Kaya'), findsWidgets);
      // The rail stays beside it, so the other sections are one tap away.
      expect(find.text('admin.auditLog'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('/admin/users opens the admin area with Benutzer selected', (
    tester,
  ) async {
    window(tester, desktop);
    final router = GoRouter(
      initialLocation: '/admin/users',
      routes: [
        GoRoute(
          path: '/admin',
          builder: (_, state) => Scaffold(
            body: AdminScreen(
              initialSection: state.uri.queryParameters['section'],
              focusUserId: state.uri.queryParameters['user'],
            ),
          ),
        ),
        GoRoute(
          path: '/admin/users',
          redirect: (_, state) => adminUsersRedirect(state.uri),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      providers(MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();

    expect(router.state.uri.toString(), '/admin?section=users');
    expect(usersInPane(), findsOneWidget);
    expect(find.text('Mira Kaya'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('an old link keeps the user its drawer should open', () {
    expect(
      adminUsersRedirect(Uri.parse('/admin/users?user=u1')),
      '/admin?section=users&user=u1',
    );
    // The Connect relay hands the user over as its token.
    expect(
      adminUsersRedirect(Uri.parse('/admin/users?user=&token=u2')),
      '/admin?section=users',
    );
    expect(
      adminUsersRedirect(Uri.parse('/admin/users?token=u2')),
      '/admin?section=users&user=u2',
    );
  });
}

const _mira = AdminUser(
  id: 'u1',
  name: 'Mira Kaya',
  username: 'mira',
  email: 'mira@example.org',
  title: '',
  role: AdminRole.user,
  orgAdmin: false,
  origin: UserOrigin.local,
  status: UserStatus.active,
  twoFA: false,
  sso: false,
  sessions: 0,
);

class _FakeAdmin implements AdminRepository {
  @override
  Future<Map<String, dynamic>> adminSettings() async => <String, dynamic>{};

  @override
  Future<AuditPage> auditLog({
    String query = '',
    AuditCategory? category,
    AuditSeverity? severity,
    String? action,
    String? outcome,
    String? actorId,
    int page = 1,
    int perPage = 30,
  }) async => AuditPage(items: const [], total: 0, page: 1, perPage: perPage);

  @override
  Future<AdminUserPage> adminUsersPage({
    String query = '',
    AdminRole? role,
    UserStatus? status,
    UserOrigin? origin,
    UserSortKey sort = UserSortKey.lastActive,
    bool desc = true,
    int page = 1,
    int perPage = 25,
  }) async => AdminUserPage(
    items: const [_mira],
    total: 1,
    page: 1,
    perPage: perPage,
    counts: AdminUserCounts.empty,
  );

  @override
  Future<AdminUser> adminUser(String id) async => _mira;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc()
    : super(
        const AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'admin',
            email: 'admin@example.org',
            username: 'admin',
            displayName: 'Admin',
            roles: {'ADMIN'},
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
