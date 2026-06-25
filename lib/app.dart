import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/api/account_event_stream.dart';
import 'core/api/api_client.dart';
import 'core/api/hinata_repository.dart';
import 'core/blocs/app_config_bloc.dart';
import 'core/blocs/auth_bloc.dart';
import 'core/blocs/locale_cubit.dart';
import 'core/blocs/theme_cubit.dart';
import 'core/i18n/i18n.dart';
import 'core/notifications/fcm_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/app_storage.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/knowledge/data/knowledge_repository.dart';

class HinataApp extends StatefulWidget {
  const HinataApp({
    super.key,
    required this.storage,
    required this.apiClient,
    required this.repository,
  });

  final AppStorage storage;
  final ApiClient apiClient;
  final HinataRepository repository;

  @override
  State<HinataApp> createState() => _HinataAppState();
}

class _HinataAppState extends State<HinataApp> {
  late final AppConfigBloc _appConfig;
  late final AuthBloc _auth;
  late final GoRouter _router;
  late final AccountEventStream _accountEvents;
  late final FcmService _fcm;
  StreamSubscription<AuthState>? _authSub;
  // Shared backend-backed Knowledge Base store: the KB screen and the real
  // issue detail both resolve smart-links / "Documented in" against this single
  // instance. Loaded lazily on first use (post-auth), not at startup.
  late final KnowledgeRepository _knowledge = KnowledgeRepository(
    widget.repository,
  );
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _appConfig = AppConfigBloc(
      repository: widget.repository,
      storage: widget.storage,
    )..add(const AppConfigStarted());
    _auth = AuthBloc(repository: widget.repository, storage: widget.storage)
      ..add(const AuthChecked());
    widget.apiClient.onSessionExpired = () =>
        _auth.add(const LogoutRequested());
    // Real-time sign-out: hold the account event stream open while signed in so
    // the server can push a `logout` (revoked session) and end this device's
    // session at once, rather than waiting for the next request to 401.
    _accountEvents = AccountEventStream(
      repository: widget.repository,
      onLogout: () => _auth.add(const LogoutRequested()),
    );
    _syncAccountStream(_auth.state);
    _authSub = _auth.stream.listen(_syncAccountStream);
    _router = buildRouter(
      appConfig: _appConfig,
      auth: _auth,
      storage: widget.storage,
    );
    // Push: a tapped notification carries the in-app route in its data payload;
    // forward it straight to the router (same routes as the web deep links).
    _fcm = FcmService(
      apiClient: widget.apiClient,
      onDeepLink: (link) => _router.go(link),
    );
    _listenForDeepLinks();
  }

  /// Opens the account event stream once authenticated and closes it otherwise,
  /// so the real-time sign-out channel is only live for a signed-in user.
  void _syncAccountStream(AuthState state) {
    if (state.status == AuthStatus.authenticated) {
      _accountEvents.start();
      _fcm.start();
    } else {
      _accountEvents.stop();
      _fcm.stop();
    }
  }

  /// Handles the app's `hinata://` deep links:
  ///  - `auth-callback?access_token=…&refresh_token=…` after an SSO login;
  ///  - `invite?token=…&server=…` from an invitation email, which opens the
  ///    in-app "set your password" screen (carrying the server URL so a freshly
  ///    installed app knows which backend to talk to).
  void _listenForDeepLinks() {
    final appLinks = AppLinks();
    // Cold start: the link that launched the app (e.g. tapping an email link).
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleUri(uri);
    });
    _linkSubscription = appLinks.uriLinkStream.listen(_handleUri);
  }

  Future<void> _handleUri(Uri uri) async {
    // Custom-scheme links (hinata://…) — SSO callback + token email flows.
    if (uri.scheme == 'hinata') {
      switch (uri.host) {
        case 'auth-callback':
          final access = uri.queryParameters['access_token'];
          final refresh = uri.queryParameters['refresh_token'];
          if (access != null && refresh != null) {
            _auth.add(SsoTokensReceived(access, refresh));
          }
        case 'invite':
          await _openTokenFlow(uri, '/invite');
        case 'reset-password':
          await _openTokenFlow(uri, '/reset-password');
      }
      return;
    }

    // Universal / App Links (https) from the production web domain. Verified
    // against /.well-known/{assetlinks.json,apple-app-site-association}, these
    // carry the same in-app routes as the website (e.g. /issues/MOB-9), so we
    // forward the path straight to the router. The token flows still need their
    // server-URL handoff, so they keep going through _openTokenFlow.
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      if (uri.path.startsWith('/invite')) {
        await _openTokenFlow(uri, '/invite');
      } else if (uri.path.startsWith('/reset-password')) {
        await _openTokenFlow(uri, '/reset-password');
      } else if (uri.path.isNotEmpty && uri.path != '/') {
        _router.go(uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
      }
    }
  }

  /// Shared handoff for the token-carrying email deep links (invite / reset):
  /// persist the server URL from the link so a fresh app can reach the backend,
  /// then route to the in-app screen.
  Future<void> _openTokenFlow(Uri uri, String route) async {
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty) return;
    final server = uri.queryParameters['server'];
    if (server != null && server.isNotEmpty) {
      await widget.storage.setServerUrl(server);
      _appConfig.add(ServerUrlSubmitted(server));
    }
    _router.go('$route?token=${Uri.encodeQueryComponent(token)}');
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    _authSub?.cancel();
    _accountEvents.stop();
    _router.dispose();
    _appConfig.close();
    _auth.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: widget.storage),
        RepositoryProvider.value(value: widget.apiClient),
        RepositoryProvider.value(value: widget.repository),
        RepositoryProvider.value(value: _knowledge),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _appConfig),
          BlocProvider.value(value: _auth),
          BlocProvider(create: (_) => LocaleCubit()),
          BlocProvider(create: (_) => ThemeCubit()),
        ],
        child: BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, themeMode) {
            return BlocBuilder<LocaleCubit, Locale>(
              builder: (context, locale) {
                // Keep the API client's Accept-Language in sync so the server
                // localizes its error messages to the user's chosen language.
                widget.apiClient.localeCode = locale.languageCode;
                return MaterialApp.router(
                  title: 'Hinata',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.light(),
                  darkTheme: AppTheme.dark(),
                  themeMode: themeMode,
                  locale: locale,
                  supportedLocales: I18n.supportedLocales,
                  localizationsDelegates: I18n.delegates(),
                  routerConfig: _router,
                  // Sync the runtime brightness that drives AppColors' neutral
                  // getters with the user's chosen ThemeMode (following the OS
                  // for ThemeMode.system). We resolve this from the mode/platform
                  // directly rather than Theme.of(context).brightness: MaterialApp
                  // *animates* between the light/dark ThemeData and that discrete
                  // brightness flag only flips at the animation midpoint, which
                  // would make AppColors' neutral colors lag the switch by ~100ms.
                  // Runs above the router subtree each build, so screens that read
                  // AppColors get the correct value on the very first frame.
                  builder: (context, child) {
                    AppColors.brightness = switch (themeMode) {
                      ThemeMode.light => Brightness.light,
                      ThemeMode.dark => Brightness.dark,
                      ThemeMode.system => MediaQuery.platformBrightnessOf(
                        context,
                      ),
                    };
                    return child ?? const SizedBox.shrink();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
