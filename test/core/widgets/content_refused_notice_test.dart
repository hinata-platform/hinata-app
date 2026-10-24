import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/widgets/content_refused_notice.dart';

/// The text check's refusal (HIN-176): read off the failure by its code, and
/// shown where the person was writing, on a phone with large text.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  ApiFailure refused(Map<String, String> details) => ApiFailure(
    'Not allowed here',
    statusCode: 422,
    details: {'code': 'moderation.refused', ...details},
  );

  test('a refusal is read by its code, with the words it names', () {
    final refusal = ContentRefusal.of(
      refused({'category': 'THREAT', 'terms': 'ich steche dich, kill you'}),
    );

    expect(refusal?.terms, ['ich steche dich', 'kill you']);
  });

  test('a refusal without words is still one', () {
    expect(ContentRefusal.of(refused({}))?.terms, isEmpty);
  });

  test('another 422 is not a refusal', () {
    final validation = ApiFailure(
      'error.validation',
      statusCode: 422,
      details: const {'code': 'something.else'},
    );

    expect(ContentRefusal.of(validation), isNull);
    expect(ContentRefusal.of(StateError('boom')), isNull);
  });

  Future<void> pump(WidgetTester tester, {VoidCallback? onReadRules}) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: app!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ContentRefusedNotice(
              refusal: const ContentRefusal([
                'ein sehr langes Wort aus einer Liste',
              ]),
              onReadRules: onReadRules,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the notice fits a phone at double text size and leads to '
      'the rules', (tester) async {
    var opened = 0;
    await pump(tester, onReadRules: () => opened++);

    expect(tester.takeException(), isNull);
    expect(find.text('moderation.refused.title'), findsOneWidget);
    expect(find.text('moderation.refused.body'), findsOneWidget);

    await tester.tap(find.text('moderation.refused.readRules'));
    expect(opened, 1);
  });

  testWidgets('without a way to the rules there is no link', (tester) async {
    await pump(tester);

    expect(find.text('moderation.refused.readRules'), findsNothing);
  });
}
