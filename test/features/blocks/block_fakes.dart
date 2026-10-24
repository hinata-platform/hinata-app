import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/blocks/hidden_content_cubit.dart';

import '../../support/recording_fake.dart';

/// A server that knows blocking (HIN-168), or an older one that does not.
class ModerationAppConfig extends AppConfigBloc {
  ModerationAppConfig({bool supported = true})
    : _fixed = AppConfigState(
        meta: ServerMeta(
          serverVersion: '1.0.0',
          minAppVersion: '1.0.0',
          setupCompleted: true,
          moderation: ModerationMeta(version: supported ? 1 : 0),
        ),
      ),
      super(repository: _UnusedMeta(), storage: _UnusedStorage());

  final AppConfigState _fixed;

  @override
  AppConfigState get state => _fixed;
}

/// A [HiddenContentCubit] that already holds [blocked], over [account] so a
/// test can answer and record what blocking and lifting send.
Future<HiddenContentCubit> hiddenContent(
  FakeAccountRepository account, {
  Set<String> blocked = const {},
}) async {
  account.answer<Set<String>>(#blockedIds, blocked);
  final cubit = HiddenContentCubit(account, enabled: () => true);
  await cubit.load();
  account.calls.clear();
  return cubit;
}

class _UnusedMeta implements MetaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UnusedStorage implements AppStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
