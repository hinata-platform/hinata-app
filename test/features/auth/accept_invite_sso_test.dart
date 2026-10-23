/// An invitation on a server with SSO can be followed with SSO (HIN-179): the
/// sign-in carries the invitation, which proves the address, and completes it.
/// With local sign-in off it is the only way: a password there could not be
/// used to sign in, and an account accepted with one would stay unbound until
/// somebody's first SSO sign-in with its address.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/auth/accept_invite_screen.dart';
import 'package:hinata/features/auth/sso_launch.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'server_url': 'https://server.test',
    });
    FlutterSecureStorage.setMockInitialValues({});
    storage = AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  });

  Future<void> pumpInvite(
    WidgetTester tester, {
    required bool localAuth,
    List<SsoProvider> providers = const [_provider],
    bool providersFail = false,
  }) async {
    tester.view
      ..physicalSize = const Size(900, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = _FakeAuthRepository(
      providers: providers,
      providersFail: providersFail,
    );
    // Left open on purpose: awaiting Bloc.close() inside a testWidgets body
    // runs against the fake clock and never settles.
    final auth = AuthBloc(repository: repository, storage: storage);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/invite',
          builder: (_, _) => const AcceptInviteScreen(token: _token),
        ),
      ],
      initialLocation: '/invite',
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AuthRepository>.value(value: repository),
          RepositoryProvider<AppStorage>.value(value: storage),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: auth),
            BlocProvider<AppConfigBloc>.value(
              value: _FixedConfig(localAuth: localAuth, storage: storage),
            ),
          ],
          // Scaled down: raw i18n keys in the square test font are far wider
          // than any translation.
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(0.5)),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  final joinButton = find.byIcon(LucideIcons.shield);
  final passwordField = find.byType(TextFormField);

  testWidgets('with local sign-in off, the invitation is followed with SSO', (
    tester,
  ) async {
    await pumpInvite(tester, localAuth: false);

    expect(passwordField, findsNothing);
    expect(find.text('invite.createAccount'), findsNothing);
    expect(find.text('invite.subtitleSso'), findsOneWidget);
    expect(joinButton, findsOneWidget);
    expect(find.text('invite.joinWith'), findsOneWidget);
  });

  testWidgets('with both ways open, the invitee chooses', (tester) async {
    await pumpInvite(tester, localAuth: true);

    expect(passwordField, findsOneWidget);
    expect(find.text('invite.createAccount'), findsOneWidget);
    expect(find.text('auth.or'), findsOneWidget);
    expect(joinButton, findsOneWidget);
  });

  testWidgets('a server without SSO keeps the password form alone', (
    tester,
  ) async {
    await pumpInvite(tester, localAuth: true, providers: const []);

    expect(passwordField, findsOneWidget);
    expect(find.text('auth.or'), findsNothing);
    expect(joinButton, findsNothing);
  });

  testWidgets('SSO the only way, and the lookup failed: said, with a retry', (
    tester,
  ) async {
    await pumpInvite(tester, localAuth: false, providersFail: true);

    expect(joinButton, findsNothing);
    expect(find.text('auth.ssoLoadFailed'), findsOneWidget);
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
  });

  test('the sign-in started from an invitation carries it', () {
    final uri = ssoStartUri(
      'https://server.test',
      _provider,
      returnTo: 'https://app.test',
      invite: _token,
    );

    expect(uri.path, '/api/v1/auth/sso/start/oidc');
    expect(uri.queryParameters, {
      'return': 'https://app.test',
      'invite': _token,
    });
  });

  test('an ordinary native sign-in starts at the bare address', () {
    expect(
      ssoStartUri('https://server.test', _provider).toString(),
      'https://server.test/api/v1/auth/sso/start/oidc',
    );
  });
}

const _token = '64f0c0ffee.s3cret';

const _provider = SsoProvider(
  id: 'oidc',
  displayName: 'Lokaler IdP',
  loginUrl: '/api/v1/auth/sso/start/oidc',
);

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository({required this.providers, this.providersFail = false})
    : super(ApiClient(_UnusedStorage()));

  final List<SsoProvider> providers;
  final bool providersFail;

  @override
  Future<({String email, String displayName})> inviteInfo(String token) async =>
      (email: 'neu@example.org', displayName: 'Neu');

  @override
  Future<List<SsoProvider>> ssoProviders() async {
    if (providersFail) throw ApiFailure('errors.unexpected');
    return providers;
  }
}

/// One fixed answer about the server; reads nothing.
class _FixedConfig extends AppConfigBloc {
  _FixedConfig({required bool localAuth, required super.storage})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          localAuthEnabled: localAuth,
        ),
      ),
      super(repository: _UnusedMeta());

  final AppConfigState _fixed;

  @override
  AppConfigState get state => _fixed;

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
