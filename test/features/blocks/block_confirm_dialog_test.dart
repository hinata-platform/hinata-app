import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/blocks/block_confirm_dialog.dart';

import '../../support/recording_fake.dart';

/// The question before a block (HIN-168): what ends, what stays, and a refusal
/// shown in the dialog rather than after it closed.
///
/// Widget tests render raw i18n keys, so the assertions look for keys.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  /// Opens the dialog from a button and hands back what it answered.
  Future<List<bool?>> open(
    WidgetTester tester,
    Future<void> Function() onConfirm, {
    double width = 1200,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final answers = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => answers.add(
                await showBlockConfirm(
                  context,
                  name: 'Jonas Becker',
                  onConfirm: onConfirm,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answers;
  }

  const lines = [
    'blocks.confirm.notifications',
    'blocks.confirm.folded',
    'blocks.confirm.contact',
    'blocks.confirm.work',
    'blocks.confirm.private',
  ];

  testWidgets('says what ends and what stays, and blocks on confirm', (
    tester,
  ) async {
    var blocked = 0;
    final answers = await open(tester, () async => blocked++);
    expect(find.text('blocks.confirm.title'), findsOneWidget);
    for (final line in lines) {
      expect(find.text(line), findsOneWidget, reason: line);
    }

    await tester.tap(find.text('blocks.confirm.button'));
    await tester.pumpAndSettle();

    expect(blocked, 1);
    expect(answers, [true]);
    expect(find.text('blocks.confirm.title'), findsNothing);
  });

  testWidgets('cancelling blocks nobody', (tester) async {
    var blocked = 0;
    final answers = await open(tester, () async => blocked++);
    await tester.tap(find.text('common.cancel'));
    await tester.pumpAndSettle();
    expect(blocked, 0);
    expect(answers, [null]);
  });

  testWidgets('a refusal stays in the dialog, in words', (tester) async {
    final answers = await open(tester, () => Future<void>.error(failure));
    await tester.tap(find.text('blocks.confirm.button'));
    await tester.pumpAndSettle();
    expect(find.text('blocks.confirm.title'), findsOneWidget);
    expect(find.text('errors.test'), findsOneWidget);
    expect(answers, isEmpty);
  });

  testWidgets('holds at 390 points and text at 200 %', (tester) async {
    await open(tester, () async {}, width: 390, textScale: 2);
    expect(tester.takeException(), isNull);
    // Both buttons stay reachable at full size, however the lines wrap.
    for (final label in ['common.cancel', 'blocks.confirm.button']) {
      final button = find.text(label);
      expect(button, findsOneWidget, reason: label);
      expect(tester.getSize(button).height, greaterThan(0));
      expect(tester.getBottomLeft(button).dy, lessThanOrEqualTo(844));
    }
    await tester.ensureVisible(find.text('blocks.confirm.private'));
    expect(find.text('blocks.confirm.private'), findsOneWidget);
  });
}
