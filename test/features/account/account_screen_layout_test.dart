import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/blocs/time_preferences_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/settings_split.dart';
import 'package:hinata/features/account/account_screen.dart';

/// Settings on a wide window (HIN-110): a rail of the phone's sections and
/// exactly one of them open, instead of every card at once. The phone keeps its
/// index list.
///
/// Widget tests render raw i18n keys, so the subtitles in the cards' headers
/// are the probes: the rail lists titles only, so a subtitle on screen means
/// that card (or, on the phone, its index row) is on screen.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(
    WidgetTester tester,
    Size size, {
    String? section,
    Set<String> roles = const {'USER'},
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = _FakeAccountRepository();
    final prefs = TimePreferencesCubit(account);
    addTearDown(prefs.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: RepositoryProvider<AccountRepository>.value(
          value: account,
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: _FakeAuthBloc(roles)),
              BlocProvider<AppConfigBloc>.value(value: _FakeAppConfig()),
              BlocProvider<TimePreferencesCubit>.value(value: prefs),
            ],
            child: Scaffold(body: AccountScreen(section: section)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const security = 'account.security.subtitle';
  // The sessions card heads itself with the device count instead.
  const sessions = 'account.sessions.devices';
  const notifications = 'account.notifications.subtitle';

  testWidgets('wide: one section open, the rail opens another', (tester) async {
    await pump(tester, const Size(1440, 1000));

    expect(find.byType(SettingsNavRail<Object>), findsOneWidget);
    // The account opens: the profile and email & security, nothing else.
    expect(find.text('account.editProfile'), findsOneWidget);
    expect(find.text(security), findsOneWidget);
    expect(find.text(sessions), findsNothing);
    expect(find.text(notifications), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(SettingsNavRail<Object>),
        matching: find.text('account.sessions.title'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(sessions), findsOneWidget);
    expect(find.text(security), findsNothing);
    expect(find.text('account.editProfile'), findsNothing);
  });

  testWidgets('wide: a section link opens that section', (tester) async {
    await pump(tester, const Size(1440, 1000), section: 'notifications');

    expect(find.text(notifications), findsOneWidget);
    expect(find.text(security), findsNothing);
  });

  testWidgets('wide: the admin area is a rail entry for admins', (
    tester,
  ) async {
    await pump(tester, const Size(1440, 1000), roles: {'USER', 'ADMIN'});

    expect(
      find.descendant(
        of: find.byType(SettingsNavRail<Object>),
        matching: find.text('settings.adminArea'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('compact: the index list with the profile, no rail', (
    tester,
  ) async {
    await pump(tester, const Size(400, 900));

    expect(find.byType(SettingsNavRail<Object>), findsNothing);
    expect(find.text('account.editProfile'), findsOneWidget);
    // Every row of the index carries its subtitle, and no card is open.
    expect(find.text(security), findsOneWidget);
    expect(find.text('account.sessions.subtitle'), findsOneWidget);
    expect(find.text(notifications), findsOneWidget);
    expect(find.text(sessions), findsNothing);
    expect(find.text('account.security.email'), findsNothing);
  });
}

class _FakeAccountRepository implements AccountRepository {
  @override
  Future<Me> meAccount() async => Me.fromJson(const {
    'id': 'u1',
    'displayName': 'Lena Vogt',
    'username': 'lena',
    'email': 'lena@example.org',
    'roles': ['USER'],
  });

  @override
  Future<({List<DeviceSession> items, int total})> sessionsPage({
    int page = 0,
    int size = 25,
  }) async => (
    items: const [
      DeviceSession(id: 's1', current: true, kind: 'desktop', os: 'macOS'),
    ],
    total: 1,
  );

  @override
  Future<List<AccessTeam>> myTeams() async => const [];

  @override
  Future<List<AccessProject>> myProjects() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  _FakeAuthBloc(Set<String> roles)
    : super(
        AuthState(
          status: AuthStatus.authenticated,
          user: AuthUser(
            id: 'u1',
            email: 'lena@example.org',
            username: 'lena',
            displayName: 'Lena Vogt',
            roles: roles,
          ),
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAppConfig extends AppConfigBloc {
  _FakeAppConfig()
    : super(repository: _UnusedMeta(), storage: _UnusedStorage());

  @override
  AppConfigState get state => const AppConfigState(
    meta: ServerMeta(
      serverVersion: '1.0.0',
      minAppVersion: '1.0.0',
      setupCompleted: true,
    ),
  );

  @override
  void add(AppConfigEvent event) {}
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
