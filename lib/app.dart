import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'core/api/api_client.dart';
import 'core/api/hivora_repository.dart';
import 'core/blocs/app_config_bloc.dart';
import 'core/blocs/auth_bloc.dart';
import 'core/blocs/locale_cubit.dart';
import 'core/i18n/i18n.dart';
import 'core/router/app_router.dart';
import 'core/storage/app_storage.dart';
import 'core/theme/app_theme.dart';

class HivoraApp extends StatefulWidget {
  const HivoraApp({
    super.key,
    required this.storage,
    required this.apiClient,
    required this.repository,
  });

  final AppStorage storage;
  final ApiClient apiClient;
  final HivoraRepository repository;

  @override
  State<HivoraApp> createState() => _HivoraAppState();
}

class _HivoraAppState extends State<HivoraApp> {
  late final AppConfigBloc _appConfig;
  late final AuthBloc _auth;
  late final GoRouter _router;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _appConfig = AppConfigBloc(repository: widget.repository, storage: widget.storage)
      ..add(const AppConfigStarted());
    _auth = AuthBloc(repository: widget.repository, storage: widget.storage)
      ..add(const AuthChecked());
    widget.apiClient.onSessionExpired =
        () => _auth.add(const LogoutRequested());
    _router = buildRouter(
      appConfig: _appConfig,
      auth: _auth,
      storage: widget.storage,
    );
    _listenForSsoCallback();
  }

  /// Receives hivora://auth-callback?access_token=...&refresh_token=... after
  /// a successful OIDC/OAuth2/SAML login in the external browser.
  void _listenForSsoCallback() {
    _linkSubscription = AppLinks().uriLinkStream.listen((uri) {
      if (uri.scheme == 'hivora' && uri.host == 'auth-callback') {
        final access = uri.queryParameters['access_token'];
        final refresh = uri.queryParameters['refresh_token'];
        if (access != null && refresh != null) {
          _auth.add(SsoTokensReceived(access, refresh));
        }
      }
    });
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
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
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: _appConfig),
          BlocProvider.value(value: _auth),
          BlocProvider(create: (_) => LocaleCubit()),
        ],
        child: BlocBuilder<LocaleCubit, Locale>(
          builder: (context, locale) {
            return MaterialApp.router(
              title: 'Hivora',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              locale: locale,
              supportedLocales: I18n.supportedLocales,
              localizationsDelegates: I18n.delegates(),
              routerConfig: _router,
            );
          },
        ),
      ),
    );
  }
}
