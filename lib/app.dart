import 'dart:async';
import 'dart:convert';

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

class _HinataAppState extends State<HinataApp> with WidgetsBindingObserver {
  late final AppConfigBloc _appConfig;
  late final AuthBloc _auth;
  late final GoRouter _router;
  late final AccountEventStream _accountEvents;
  late final FcmService _fcm;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<AppConfigState>? _configSub;
  // The server the auth session was last (re)checked against. When the user
  // switches servers, AppConfig re-verifies the new backend and reaches `ready`
  // with a different URL than this — that's our cue to re-check auth so the
  // session reflects the new server (its own token, or a sign-in prompt).
  String? _authServer;
  // The server the realtime streams (SSE sign-out + FCM) are currently bound to,
  // so a switch tears them down and reopens them against the new backend.
  String? _streamServer;
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
    WidgetsBinding.instance.addObserver(this);
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
    _router = buildRouter(
      appConfig: _appConfig,
      auth: _auth,
      storage: widget.storage,
    );
    // Push: a tapped notification carries the in-app route in its data payload;
    // forward it straight to the router (same routes as the web deep links).
    // Must exist before the first _syncAccountStream call below, which starts
    // FCM when the persisted session is already authenticated.
    _fcm = FcmService(
      apiClient: widget.apiClient,
      onDeepLink: (link) => _router.go(link),
    );
    // Record the server the boot-time AuthChecked above runs against, so the
    // listener below doesn't redundantly re-check it on the first `ready`.
    _authServer = widget.storage.serverUrl;
    _syncAccountStream(_auth.state);
    _authSub = _auth.stream.listen(_syncAccountStream);
    _configSub = _appConfig.stream.listen(_onAppConfig);
    _listenForDeepLinks();
  }

  /// Re-checks the auth session whenever AppConfig settles on a *different*
  /// server than the one auth was last validated against. This is the single
  /// place that reacts to a server switch (from the switcher, the connect
  /// screen, or a deep link), regardless of who triggered it: the new backend
  /// either has a stored token (→ straight back in) or doesn't (→ sign-in).
  void _onAppConfig(AppConfigState state) {
    if (state.status != AppConfigStatus.ready) return;
    final server = widget.storage.serverUrl;
    if (_authServer == server) return;
    _authServer = server;
    _auth.add(const AuthChecked());
  }

  /// Opens the account event stream once authenticated and closes it otherwise,
  /// so the real-time sign-out channel is only live for a signed-in user.
  void _syncAccountStream(AuthState state) {
    if (state.status == AuthStatus.authenticated) {
      final server = widget.storage.serverUrl;
      // Switched backends while signed in (same `authenticated` status, new
      // server): tear the streams down so they reopen against the new host
      // below — start() is a no-op while already running and would otherwise
      // keep streaming from the old server.
      if (_streamServer != server) {
        _accountEvents.stop();
        _fcm.stop();
        _streamServer = server;
      }
      _accountEvents.start();
      _fcm.start();
    } else {
      _streamServer = null;
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
        case 'verify-email':
          await _openTokenFlow(uri, '/verify-email');
      }
      return;
    }

    // Universal / App Links (https) from the production web domain. Verified
    // against /.well-known/{assetlinks.json,apple-app-site-association}, these
    // carry the same in-app routes as the website (e.g. /issues/MOB-9), so we
    // forward the path straight to the router. The token flows still need their
    // server-URL handoff, so they keep going through _openTokenFlow.
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      if (uri.path.startsWith('/l/')) {
        await _openRelayLink(uri);
      } else if (uri.path.startsWith('/invite')) {
        await _openTokenFlow(uri, '/invite');
      } else if (uri.path.startsWith('/reset-password')) {
        await _openTokenFlow(uri, '/reset-password');
      } else if (uri.path.startsWith('/verify-email')) {
        await _openTokenFlow(uri, '/verify-email');
      } else if (uri.path.isNotEmpty && uri.path != '/') {
        _router.go(uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path);
      }
    }
  }

  /// Hinata Connect relay links: `https://connect…/l/<base64url(payload)>.<sig>`.
  /// The payload carries the originating server's API URL (`a`), the in-app path
  /// (`p`) and, for invite/reset flows only, a one-time token (`t`) — plain
  /// notification links (mentions, assignments, …) omit it. We decode it
  /// locally (the gateway's signature is only for its own web-fallback
  /// redirect; a token, when present, is validated server-side anyway), point
  /// the app at that server, and open the flow.
  Future<void> _openRelayLink(Uri uri) async {
    final seg = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
    final dot = seg.indexOf('.');
    final b64 = dot > 0 ? seg.substring(0, dot) : seg;
    if (b64.isEmpty) return;
    try {
      final padded = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
      final payload = jsonDecode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
      final token = payload['t'] as String?;
      final route = payload['p'] as String?;
      final server = payload['a'] as String?;
      if (route == null || route.isEmpty) return;
      if (server != null && server.isNotEmpty) {
        await widget.storage.setServerUrl(server);
        _appConfig.add(ServerUrlSubmitted(server));
      }
      // Invite/reset links carry a one-time token; plain notification links
      // (mentions, assignments, team changes, …) route with just the path.
      // `route` may already carry its own query string (e.g.
      // "/admin/users?user=…"), so merge rather than appending a second "?".
      final qIndex = route.indexOf('?');
      final path = qIndex < 0 ? route : route.substring(0, qIndex);
      final queryParts = <String>[
        if (qIndex >= 0) route.substring(qIndex + 1),
        if (token != null && token.isNotEmpty)
          'token=${Uri.encodeQueryComponent(token)}',
      ];
      _router.go(queryParts.isEmpty ? path : '$path?${queryParts.join('&')}');
    } catch (_) {
      // Malformed/garbage relay link — ignore silently.
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

  /// Dismiss the keyboard whenever the app leaves the foreground. If a TextField
  /// is still focused (keyboard up) when iOS snapshots the app for the background,
  /// UIKit's own keyboard layout (TUIKeyboardContentView / UIKeyboardImpl) logs a
  /// spurious "Unable to simultaneously satisfy constraints" warning — its
  /// internal 250 vs. 216 height conflict, not ours. Unfocusing first removes the
  /// trigger so the keyboard is already gone before the snapshot is taken.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    _authSub?.cancel();
    _configSub?.cancel();
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
