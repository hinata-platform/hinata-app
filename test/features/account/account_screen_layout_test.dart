import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/blocs/time_preferences_cubit.dart';
import 'package:hinata/core/blocs/tint_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/settings_split.dart';
import 'package:hinata/features/account/account_screen.dart';
import 'package:hinata/features/connect/server_switcher.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    bool unreachable = false,
    AuthBloc? auth,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final account = _FakeAccountRepository(unreachable: unreachable);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    await storage.setServerUrl('https://hinata.example');
    final prefs = TimePreferencesCubit(account);
    addTearDown(prefs.close);
    HydratedBloc.storage = _MemoryStorage();
    final tint = TintCubit(account);
    addTearDown(tint.close);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<AccountRepository>.value(value: account),
            RepositoryProvider<AppStorage>.value(value: storage),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth ?? _FakeAuthBloc(roles)),
              BlocProvider<AppConfigBloc>.value(value: _FakeAppConfig()),
              BlocProvider<TimePreferencesCubit>.value(value: prefs),
              BlocProvider<TintCubit>.value(value: tint),
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

  testWidgets('an unreachable server still offers another server and the '
      'sign-out', (tester) async {
    final auth = _RecordingAuthBloc();
    addTearDown(auth.close);
    await pump(tester, const Size(400, 900), unreachable: true, auth: auth);

    expect(find.text('account.retryError'), findsOneWidget);
    expect(find.byType(ServerCard), findsOneWidget);
    await tester.tap(find.text('account.signOut'));
    await tester.pump();

    expect(auth.events, [isA<LogoutRequested>()]);
  });
}

class _FakeAccountRepository implements AccountRepository {
  _FakeAccountRepository({this.unreachable = false});

  /// The server does not answer.
  final bool unreachable;

  @override
  Future<Me> meAccount() async => unreachable
      ? throw Exception('unreachable')
      : Me.fromJson(const {
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

class _RecordingAuthBloc extends Bloc<AuthEvent, AuthState>
    implements AuthBloc {
  _RecordingAuthBloc() : super(const AuthState()) {
    on<AuthEvent>((event, _) => events.add(event));
  }

  final List<AuthEvent> events = [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _MemoryStorage implements Storage {
  final Map<String, dynamic> _values = {};
  @override
  dynamic read(String key) => _values[key];
  @override
  Future<void> write(String key, dynamic value) async => _values[key] = value;
  @override
  Future<void> delete(String key) async => _values.remove(key);
  @override
  Future<void> clear() async => _values.clear();
  @override
  Future<void> close() async {}
}
