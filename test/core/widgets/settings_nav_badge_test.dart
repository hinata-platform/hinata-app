import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/count_badge.dart';
import 'package:hinata/core/widgets/settings_split.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A settings entry can carry a count (HIN-174): the cases waiting for
/// moderation, said in words to a screen reader, and nothing at zero.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(WidgetTester tester, int badge) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SettingsNavRail<String>(
          header: const SizedBox.shrink(),
          entries: [
            SettingsNavEntry(
              id: 'moderation',
              icon: LucideIcons.flag,
              label: 'Moderation',
              trailing: LucideIcons.externalLink,
              badge: badge,
              badgeLabel: '$badge open cases',
            ),
          ],
          selected: 'other',
          onSelect: (_) {},
        ),
      ),
    ),
  );

  testWidgets('the count stands before the glyph and is read in words', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, 5);
    expect(find.byType(CountBadge), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('5 open cases')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('nothing waiting shows no badge', (tester) async {
    await pump(tester, 0);
    expect(find.byType(CountBadge), findsNothing);
  });
}
