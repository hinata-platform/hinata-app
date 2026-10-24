import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';

/// A phone at 390 points, with the text as large as a person may set it.
void onPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// [child] in an app with the blocs and the account repository the
/// moderation screens read, at text scale [textScale].
Widget moderationApp({
  required Widget child,
  required AccountRepository account,
  AuthBloc? auth,
  ModerationMeta moderation = const ModerationMeta(version: 1),
  String? organizationName = 'Werkhaus',
  double textScale = 2.0,
}) => RepositoryProvider<AccountRepository>.value(
  value: account,
  child: MultiBlocProvider(
    providers: [
      BlocProvider<AppConfigBloc>.value(
        value: FixedAppConfig(
          moderation: moderation,
          organizationName: organizationName,
        ),
      ),
      BlocProvider<AuthBloc>.value(value: auth ?? RecordingAuth()),
    ],
    child: MaterialApp(
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: child,
    ),
  ),
);

/// A server with moderation, and its name.
class FixedAppConfig extends AppConfigBloc {
  FixedAppConfig({required ModerationMeta moderation, String? organizationName})
    : _fixed = AppConfigState(
        status: AppConfigStatus.ready,
        appVersion: '10.8.0',
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          organizationName: organizationName,
          moderation: moderation,
        ),
      ),
      super(repository: _UnusedMeta(), storage: _UnusedStorage());

  final AppConfigState _fixed;

  @override
  AppConfigState get state => _fixed;
}

/// An auth bloc that keeps what it is asked to do instead of doing it.
class RecordingAuth extends AuthBloc {
  RecordingAuth() : super(repository: _UnusedAuth(), storage: _UnusedStorage());

  final List<AuthEvent> events = [];

  @override
  void add(AuthEvent event) => events.add(event);
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
