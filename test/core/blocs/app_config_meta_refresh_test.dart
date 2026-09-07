import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/repositories/meta_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `/api/v1/meta` is read once at boot, but what it says does not stand still:
/// an admin can switch a module on, or raise the minimum app version, while
/// this app is running. [MetaRefreshRequested] is how the app finds out — on
/// resume, after an admin save, and when the server answers that a module it
/// was asked for is switched off.
///
/// What matters is as much what it must *not* do: a refresh is not a boot, so a
/// failed read keeps the metadata we have instead of throwing a working session
/// back to the connect screen.
void main() {
  const server = 'https://example.test';

  TestWidgetsFlutterBinding.ensureInitialized();

  ServerMeta meta({
    bool advancedTime = false,
    String minAppVersion = '1.0.0',
  }) => ServerMeta(
    serverVersion: '2.0.0',
    minAppVersion: minAppVersion,
    setupCompleted: true,
    featureFlags: {PlatformFlags.advancedTimeTracking: advancedTime},
  );

  Future<AppStorage> storageWithServer() async {
    SharedPreferences.setMockInitialValues({
      'server_url': server,
      'servers.v1': '[{"url":"$server"}]',
    });
    return AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  }

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'hinata',
      packageName: 'hn.asta.hinata',
      version: '10.3.3',
      buildNumber: '87',
      buildSignature: '',
    );
  });

  /// A bloc already past boot, with the module switched off.
  Future<(AppConfigBloc, _FakeMetaRepository)> ready() async {
    final repository = _FakeMetaRepository(meta());
    final bloc = AppConfigBloc(
      repository: repository,
      storage: await storageWithServer(),
    )..add(const AppConfigStarted());
    await bloc.stream.firstWhere((s) => s.status == AppConfigStatus.ready);
    return (bloc, repository);
  }

  test('picks up a flag an admin switched on, without a restart', () async {
    final (bloc, repository) = await ready();
    addTearDown(bloc.close);
    expect(bloc.state.meta!.advancedTimeTracking, isFalse);

    repository.next = meta(advancedTime: true);
    bloc.add(const MetaRefreshRequested());

    final state = await bloc.stream.first;
    expect(state.status, AppConfigStatus.ready);
    expect(state.meta!.advancedTimeTracking, isTrue);
  });

  test('a burst of triggers costs one read, not one each', () async {
    // On desktop and web `resumed` fires on every window focus, so alt-tabbing
    // would be a round trip each time; and a screen calling a switched-off route
    // asks once per failed request. /meta shares the per-IP rate-limit budget
    // with everything else, and behind an office NAT that budget is shared with
    // colleagues doing unrelated work.
    final (bloc, repository) = await ready();
    addTearDown(bloc.close);
    final before = repository.calls;

    for (var i = 0; i < 5; i++) {
      bloc.add(const MetaRefreshRequested());
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repository.calls - before, 1);
  });

  test(
    'a refresh that never reached the server is not held against the next',
    () async {
      // The cooldown starts when an answer arrives, not when one is attempted:
      // going offline for a moment must not also mean waiting out the window
      // before the app may try again.
      final (bloc, repository) = await ready();
      addTearDown(bloc.close);
      repository.fail = true;
      bloc.add(const MetaRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      repository.fail = false;
      repository.next = meta(advancedTime: true);
      bloc.add(const MetaRefreshRequested());

      final state = await bloc.stream.first;
      expect(state.meta!.advancedTimeTracking, isTrue);
    },
  );

  test('a failed refresh keeps the metadata we already have', () async {
    final (bloc, repository) = await ready();
    addTearDown(bloc.close);
    final before = bloc.state.meta;

    repository.fail = true;
    bloc.add(const MetaRefreshRequested());
    // Give the handler a turn; it must emit nothing at all.
    await Future<void>.delayed(Duration.zero);

    expect(bloc.state.status, AppConfigStatus.ready);
    expect(bloc.state.meta, same(before));
  });

  test('a raised minimum app version still closes the door', () async {
    final (bloc, repository) = await ready();
    addTearDown(bloc.close);

    repository.next = meta(minAppVersion: '99.0.0');
    bloc.add(const MetaRefreshRequested());

    final state = await bloc.stream.first;
    expect(state.status, AppConfigStatus.updateRequired);
  });

  test('is ignored before the app is up — boot owns that flow', () async {
    final repository = _FakeMetaRepository(meta());
    final bloc = AppConfigBloc(
      repository: repository,
      storage: await storageWithServer(),
    );
    addTearDown(bloc.close);

    bloc.add(const MetaRefreshRequested());
    await Future<void>.delayed(Duration.zero);

    expect(repository.calls, 0);
    expect(bloc.state.status, AppConfigStatus.initial);
  });
}

class _FakeMetaRepository implements MetaRepository {
  _FakeMetaRepository(this.next);

  ServerMeta next;
  bool fail = false;
  int calls = 0;

  @override
  Future<ServerMeta> meta() async {
    calls++;
    if (fail) throw Exception('offline');
    return next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
