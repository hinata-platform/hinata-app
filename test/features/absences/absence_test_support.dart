import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';

/// An [AppConfigBloc] holding one fixed answer about the server, for the
/// screens that ask whether absence management is switched on.
///
/// The real bloc reads `/api/v1/meta` and needs a repository and storage to do
/// it; neither is touched here, because the state never changes. Extending it
/// rather than faking the interface keeps `context.select<AppConfigBloc, …>`
/// working, which is how every screen asks.
class FakeAppConfig extends AppConfigBloc {
  FakeAppConfig({bool absenceManagement = true})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          featureFlags: {
            PlatformFlags.advancedTimeTracking: true,
            PlatformFlags.absenceManagement: absenceManagement,
          },
        ),
      ),
      super(repository: _UnusedMeta(), storage: _UnusedStorage());

  final AppConfigState _fixed;

  @override
  AppConfigState get state => _fixed;
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
