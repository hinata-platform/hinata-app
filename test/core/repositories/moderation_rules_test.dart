import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/repositories/moderation_repository.dart';

import '../../support/recording_fake.dart';

/// The house rules a decision rests on are the same for every decision on an
/// instance: one read serves the dialogs that follow for a while, per server
/// and per language.
void main() {
  late FakeApiClient api;
  late ModerationRepository moderation;
  late String server;
  late String locale;
  late DateTime now;

  setUp(() {
    server = 'https://a.test';
    locale = 'de';
    now = DateTime(2026, 10, 24, 12);
    api = FakeApiClient()
      ..answerWith(#baseUrl, (_) => server)
      ..answerWith(#localeCode, (_) => locale)
      ..answerWith(
        #get,
        (_) => Future<dynamic>.value(<String, dynamic>{
          'rules': [
            {'number': 2, 'title': 'Niemanden herabsetzen'},
          ],
        }),
      );
    moderation = ModerationRepository(api, now: () => now);
  });

  int reads() => api.calls.where((call) => call.memberName == #get).length;

  test('one read serves the decisions that follow', () async {
    final first = await moderation.rules();
    final second = await moderation.rules();

    expect(reads(), 1);
    expect(second, first);
    expect(second.rules.single.title, 'Niemanden herabsetzen');
  });

  test('another language or another server reads again', () async {
    await moderation.rules();
    locale = 'en';
    await moderation.rules();
    server = 'https://b.test';
    await moderation.rules();

    expect(reads(), 3);
  });

  test('rules an administrator changed arrive after a while', () async {
    await moderation.rules();
    now = now.add(ModerationRepository.rulesHeldFor);
    await moderation.rules();

    expect(reads(), 2);
  });
}
