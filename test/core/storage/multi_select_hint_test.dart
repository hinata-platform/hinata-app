import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Issues page's long-press tip is shown once per server, like the Connect
/// hint: each self-hosted instance is its own workspace.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStorage> storage(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return AppStorage(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  }

  test('is unseen on a server until it is dismissed there', () async {
    final store = await storage({'server_url': 'https://a.test'});
    expect(store.multiSelectHintSeen, isFalse);

    await store.setMultiSelectHintSeen();

    expect(store.multiSelectHintSeen, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('multi_select_hint_seen::https://a.test'), isTrue);
  });

  test('dismissing it on one server leaves the other untouched', () async {
    final store = await storage({
      'server_url': 'https://b.test',
      'multi_select_hint_seen::https://a.test': true,
    });

    expect(store.multiSelectHintSeen, isFalse);
  });

  test('stays quiet while no server is selected', () async {
    final store = await storage({});

    expect(store.multiSelectHintSeen, isTrue);
    // Nothing to scope the flag to, so nothing is written.
    await store.setMultiSelectHintSeen();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });
}
