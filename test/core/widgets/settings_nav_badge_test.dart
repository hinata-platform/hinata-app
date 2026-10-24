import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/moderation_case_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/count_badge.dart';
import 'package:hinata/core/widgets/settings_split.dart';
import 'package:hinata/features/moderation/queue/moderation_summary_cubit.dart';
import 'package:hinata/features/moderation/queue/open_cases_badge.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../support/recording_fake.dart';

/// A settings entry can carry a count (HIN-174): the cases waiting for
/// moderation, said in words to a screen reader, and nothing at zero. The
/// badge reads the count itself, so a new count rebuilds the badge and not the
/// settings page that lists the entry.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Widget rail() => SettingsNavRail<String>(
    header: const SizedBox.shrink(),
    entries: const [
      SettingsNavEntry(
        id: 'moderation',
        icon: LucideIcons.flag,
        label: 'Moderation',
        trailing: LucideIcons.externalLink,
        badge: OpenCasesBadge(gap: 6),
      ),
    ],
    selected: 'other',
    onSelect: (_) {},
  );

  /// The rail under a count of [open] waiting cases.
  Future<void> pump(WidgetTester tester, int open) async {
    final moderation = FakeModerationRepository()
      ..answer<ModerationSummary>(#summary, ModerationSummary(open: open));
    final summary = ModerationSummaryCubit(moderation);
    await summary.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<ModerationSummaryCubit>.value(
            value: summary,
            child: rail(),
          ),
        ),
      ),
    );
  }

  testWidgets('the count stands before the glyph and is read in words', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, 5);
    expect(find.byType(CountBadge), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(CountBadge)).dx,
      lessThan(tester.getTopLeft(find.byIcon(LucideIcons.externalLink)).dx),
    );
    expect(
      find.bySemanticsLabel(RegExp('moderation.queue.openCount')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('nothing waiting shows no badge', (tester) async {
    await pump(tester, 0);
    expect(find.byType(CountBadge), findsNothing);
  });

  testWidgets('without the count above it there is no badge', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: rail())));
    expect(find.byType(CountBadge), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
