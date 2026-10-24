import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/moderation_models.dart';
import 'package:hinata/core/repositories/moderation_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/blocks/hidden_content_cubit.dart';
import 'package:hinata/features/moderation/report/report_sheet.dart';

import '../../support/recording_fake.dart';

/// The report sheet (HIN-173): a sheet on a phone, a popover beside the menu
/// on a wide window, two steps, and every refusal kept in it.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  const subject = ReportSubject(
    target: TargetRef(ContentKind.comment, 'c1', parentId: 'i1'),
    title: 'Kommentar melden',
    subtitle: 'Von Jonas Becker in MESSE-14',
    authorId: 'jonas',
    authorName: 'Jonas Becker',
  );

  late FakeModerationRepository moderation;
  late HiddenContentCubit hidden;
  late List<bool> outcomes;

  setUp(() {
    moderation = FakeModerationRepository()
      ..answer<Set<String>>(#reportedIds, const {});
    hidden = HiddenContentCubit(
      FakeAccountRepository(),
      moderation,
      enabled: () => true,
    );
    outcomes = [];
  });

  tearDown(() => hidden.close());

  Future<void> open(
    WidgetTester tester, {
    Size screen = const Size(390, 844),
    double textScale = 2,
    bool anchored = false,
    Rect anchor = const Rect.fromLTWH(40, 40, 40, 40),
  }) async {
    tester.view
      ..physicalSize = screen
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepositoryProvider<ModerationRepository>.value(
        value: moderation,
        child: BlocProvider<HiddenContentCubit>.value(
          value: hidden,
          child: MaterialApp(
            builder: (context, app) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: app!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: TextButton(
                    onPressed: () async => outcomes.add(
                      await showReportSheet(
                        context,
                        subject: subject,
                        anchorRect: anchored ? anchor : null,
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('on a phone at twice the text size: the reason, then send', (
    tester,
  ) async {
    moderation.answer<void>(#report, null);
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('moderation.report.whyTitle'), findsOneWidget);

    await tapText(tester, 'moderation.category.harassment');
    expect(find.text('moderation.report.alsoBlock'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // The caption is a sentence: at this size it wraps rather than being cut.
    expect(
      tester
          .widget<Text>(find.text('moderation.report.explanationOptional'))
          .maxLines,
      isNull,
    );

    final alsoBlock = find.byType(HiveSwitch);
    await tester.ensureVisible(alsoBlock);
    await tester.tap(alsoBlock);
    await tester.pump();
    await tapText(tester, 'moderation.report.send');

    expect(
      moderation.callTo(#report),
      invoked(
        #report,
        positional: [subject.target, ReportCategory.harassment],
        named: {#explanation: null, #alsoBlock: true},
      ),
    );
    expect(outcomes, [true]);
    expect(find.text('moderation.report.whyTitle'), findsNothing);
    // Folded for the reader at once, and the author with it.
    expect(hidden.state.reported, {'c1'});
    expect(hidden.state.blocked, {'jonas'});
  });

  testWidgets('a reason that needs words asks for them first', (tester) async {
    await open(tester);
    await tapText(tester, 'moderation.category.other');
    await tapText(tester, 'moderation.report.send');

    expect(find.text('moderation.report.explanationTooShort'), findsOneWidget);
    expect(
      moderation.calls.where((call) => call.memberName == #report),
      isEmpty,
    );
  });

  testWidgets('a refusal stays in the sheet and keeps what was typed', (
    tester,
  ) async {
    moderation.fail(
      #report,
      ApiFailure('Dieser Inhalt wurde entfernt', statusCode: 410),
    );
    await open(tester);
    await tapText(tester, 'moderation.category.spam');
    await tester.enterText(find.byType(TextField), 'Werbung für Kaffee');
    await tapText(tester, 'moderation.report.send');

    expect(find.text('Dieser Inhalt wurde entfernt'), findsOneWidget);
    expect(find.text('Werbung für Kaffee'), findsOneWidget);
    expect(outcomes, isEmpty);
  });

  testWidgets('on a wide window it hangs off the menu, never as a sheet', (
    tester,
  ) async {
    await open(
      tester,
      screen: const Size(1400, 1000),
      textScale: 1,
      anchored: true,
    );
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text('Kommentar melden'));
    // Beside the anchor at the top left, not centred or rising from below.
    expect(title.left, lessThan(700));
    expect(title.top, lessThan(500));
  });

  testWidgets('from a menu low in a short window it opens above, where the '
      'reasons have room', (tester) async {
    // A comment's menu near the foot of an 800 by 632 window: 166 points
    // below it, 402 above.
    await open(
      tester,
      screen: const Size(800, 632),
      textScale: 1,
      anchored: true,
      anchor: const Rect.fromLTWH(300, 420, 32, 28),
    );
    expect(tester.takeException(), isNull);
    final reason = tester.getRect(find.text('moderation.category.harassment'));
    expect(tester.getRect(find.text('Kommentar melden')).bottom, lessThan(420));
    expect(reason.bottom, lessThan(420));
  });

  testWidgets('the reasons are buttons, and the next step is announced', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester, textScale: 1);

    expect(
      tester.getSemantics(find.text('moderation.category.threat')),
      isSemantics(isButton: true, hasTapAction: true),
    );

    await tapText(tester, 'moderation.category.threat');
    expect(
      tester.getSemantics(find.text('moderation.report.change')),
      isSemantics(isLiveRegion: true),
    );
    semantics.dispose();
  });
}
