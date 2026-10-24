import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';

/// A server that answers with one fixed meta and dispatches nothing: what it
/// knows of moderation, and its name.
class FixedAppConfig extends AppConfigBloc {
  FixedAppConfig({
    ModerationMeta moderation = const ModerationMeta(version: 1),
    String? organizationName,
  })
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

/// An auth bloc that keeps what it is asked to do instead of doing it, with
/// [user] signed in when given.
class RecordingAuth extends AuthBloc {
  RecordingAuth({this.user})
    : super(repository: _UnusedAuth(), storage: _UnusedStorage());

  final AuthUser? user;

  final List<AuthEvent> events = [];

  @override
  AuthState get state => user == null
      ? super.state
      : AuthState(status: AuthStatus.authenticated, user: user);

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
