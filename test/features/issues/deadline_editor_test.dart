import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/glass_switch_chip.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/issues/deadline_editor.dart';

/// The deadline field in both of its modes.
///
/// Two things are worth pinning down. The editor must never compute a date
/// itself — it asks, and what it asks with is the rule the form describes, sign
/// and all — and picking a date has to come back as a date rather than as a
/// rule, because that is what tells the server to drop the offset.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  /// The rules the editor asked about, in order.
  late List<RelativeDate> asked;

  setUp(() => asked = []);

  Widget host({
    DateTime? date,
    RelativeDate? offset,
    DateTime? eventDate,
    double width = 900,
    Future<DateTime?> Function(RelativeDate)? resolve,
    void Function(DeadlineChoice?)? onResult,
    RelativeDateBasis defaultBasis = RelativeDateBasis.calendar,
    bool allowOffset = true,
    bool? allowClear,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: SizedBox(
            width: width,
            child: ElevatedButton(
              onPressed: () async {
                final choice = await showDeadlineEditor(
                  context,
                  title: 'issues.dueDate',
                  date: date,
                  offset: offset,
                  eventDate: eventDate,
                  defaultBasis: defaultBasis,
                  allowOffset: allowOffset,
                  allowClear: allowClear,
                  resolve:
                      resolve ??
                      (asked_) async {
                        asked.add(asked_);
                        return DateTime(2026, 10, 1);
                      },
                );
                onResult?.call(choice);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('it opens in date mode when there is no rule', (tester) async {
    await tester.pumpWidget(host(date: DateTime(2026, 11, 12)));
    await open(tester);

    expect(find.text('issues.deadline.modeDate'), findsOneWidget);
    expect(find.text('issues.deadline.fixedDate'), findsOneWidget);
    // Nothing is asked of the server while no rule is being edited.
    expect(asked, isEmpty);
  });

  testWidgets('it opens in rule mode when the issue carries one', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        date: DateTime(2026, 10, 1),
        offset: const RelativeDate(amount: -6, unit: RelativeDateUnit.weeks),
        eventDate: DateTime(2026, 11, 12),
      ),
    );
    await open(tester);

    expect(find.text('issues.deadline.workingDays'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('the rule it asks about carries the sign and the basis', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        offset: const RelativeDate(amount: -6, unit: RelativeDateUnit.weeks),
        eventDate: DateTime(2026, 11, 12),
      ),
    );
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(asked, isNotEmpty);
    expect(asked.last.amount, -6);
    expect(asked.last.unit, RelativeDateUnit.weeks);
    expect(asked.last.basis, RelativeDateBasis.calendar);

    // Switching to working days asks again, with the other basis: the answer
    // differs by whatever the project's holiday calendar says, which is exactly
    // why the app does not compute it.
    await tester.tap(find.byType(HiveSwitch));
    await tester.pump(const Duration(milliseconds: 400));

    expect(asked.last.basis, RelativeDateBasis.working);
  });

  testWidgets('"after" flips the sign rather than adding a second field', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        offset: const RelativeDate(amount: -3),
        eventDate: DateTime(2026, 11, 12),
      ),
    );
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(asked.last.amount, -3);

    // The switcher scrolls its chips past its own width, and a raw i18n key is
    // three times as long as the word it stands for — so in a test, and only in
    // a test, "after" starts life outside the pill.
    await tester.ensureVisible(find.text('issues.deadline.after'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('issues.deadline.after'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(asked.last.amount, 3);
  });

  testWidgets('applying a rule returns the rule and the day it resolved to', (
    tester,
  ) async {
    DeadlineChoice? result;
    await tester.pumpWidget(
      host(
        offset: const RelativeDate(amount: -6, unit: RelativeDateUnit.weeks),
        eventDate: DateTime(2026, 11, 12),
        onResult: (choice) => result = choice,
      ),
    );
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('common.apply'));
    await tester.pumpAndSettle();

    expect(result?.offset?.amount, -6);
    expect(result?.cleared, isFalse);
    // The day travels with the rule, so the row that renders it has something
    // to show instead of claiming the project has no date.
    expect(result?.date, DateTime(2026, 10, 1));
  });

  testWidgets('clearing returns neither a date nor a rule', (tester) async {
    DeadlineChoice? result;
    await tester.pumpWidget(
      host(
        date: DateTime(2026, 10, 1),
        offset: const RelativeDate(amount: -6, unit: RelativeDateUnit.weeks),
        eventDate: DateTime(2026, 11, 12),
        onResult: (choice) => result = choice,
      ),
    );
    await open(tester);
    await tester.tap(find.text('common.clear'));
    await tester.pumpAndSettle();

    expect(result?.cleared, isTrue);
    expect(result?.offset, isNull);
    expect(result?.date, isNull);
  });

  testWidgets('without a project date it says so and asks nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(offset: const RelativeDate(amount: -6), eventDate: null),
    );
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // The rule is kept and editable; there is simply nothing to count from.
    expect(find.text('issues.deadline.noEventDate'), findsOneWidget);
    expect(asked, isEmpty);
  });

  testWidgets('a failing lookup leaves the line blank, never an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        offset: const RelativeDate(amount: -6),
        eventDate: DateTime(2026, 11, 12),
        resolve: (_) async => throw StateError('server said no'),
      ),
    );
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    // Blank, not "working it out": nothing is in flight any more, and a line
    // promising a date that is never coming is worse than an empty one.
    expect(find.text('issues.deadline.calculating'), findsNothing);
  });

  testWidgets('the date the issue already carries is not asked for again', (
    tester,
  ) async {
    // The stored date *is* the server's answer for that rule — it writes it on
    // every save — so opening the editor has nothing to ask.
    await tester.pumpWidget(
      host(
        date: DateTime(2026, 10, 1),
        offset: const RelativeDate(amount: -6, unit: RelativeDateUnit.weeks),
        eventDate: DateTime(2026, 11, 12),
      ),
    );
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(asked, isEmpty);
  });

  testWidgets('touching a control without changing the rule asks nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        offset: const RelativeDate(amount: -6),
        eventDate: DateTime(2026, 11, 12),
      ),
    );
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(asked, hasLength(1));

    // "Before" is already the direction. The line on screen answers this rule
    // already, so there is nothing to ask.
    await tester.tap(find.text('issues.deadline.before'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(asked, hasLength(1));
  });

  testWidgets('switching to date mode warns that the rule goes with it', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        date: DateTime(2026, 10, 1),
        offset: const RelativeDate(amount: -6),
        eventDate: DateTime(2026, 11, 12),
      ),
    );
    await open(tester);
    await tester.tap(find.text('issues.deadline.modeDate'));
    await tester.pumpAndSettle();

    expect(find.text('issues.deadline.dateReplacesOffset'), findsOneWidget);
  });

  group('defaults', () {
    testWidgets('a new rule starts from the default basis', (tester) async {
      DeadlineChoice? result;
      await tester.pumpWidget(
        host(
          eventDate: DateTime(2026, 11, 12),
          defaultBasis: RelativeDateBasis.working,
          onResult: (choice) => result = choice,
        ),
      );
      await open(tester);
      // The raw key in the test font is wider than the 300 px switch bar, so
      // its centre lies outside the chip; call the chip instead of tapping.
      tester
          .widget<GlassSwitchChip>(
            find.ancestor(
              of: find.text('issues.deadline.modeOffset'),
              matching: find.byType(GlassSwitchChip),
            ),
          )
          .onTap!();
      await tester.pumpAndSettle();

      expect(tester.widget<HiveSwitch>(find.byType(HiveSwitch)).value, isTrue);

      await tester.tap(find.text('common.apply'));
      await tester.pumpAndSettle();
      expect(result?.offset?.basis, RelativeDateBasis.working);
    });

    testWidgets('an existing rule keeps its own basis', (tester) async {
      await tester.pumpWidget(
        host(
          date: DateTime(2026, 10, 1),
          offset: const RelativeDate(amount: -6),
          eventDate: DateTime(2026, 11, 12),
          defaultBasis: RelativeDateBasis.working,
        ),
      );
      await open(tester);

      expect(tester.widget<HiveSwitch>(find.byType(HiveSwitch)).value, isFalse);
    });

    testWidgets('without rules on offer there is no mode switch', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(eventDate: DateTime(2026, 11, 12), allowOffset: false),
      );
      await open(tester);

      expect(find.text('issues.deadline.modeOffset'), findsNothing);
      expect(find.text('issues.deadline.modeDate'), findsNothing);
      expect(find.text('issues.deadline.fixedDate'), findsOneWidget);
    });

    testWidgets('clearing is offered on request even with nothing set', (
      tester,
    ) async {
      DeadlineChoice? result;
      await tester.pumpWidget(
        host(allowClear: true, onResult: (choice) => result = choice),
      );
      await open(tester);

      // Nothing picked, nothing to replace: "apply" has no answer to give.
      final apply = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'common.apply'),
      );
      expect(apply.onPressed, isNull);

      await tester.tap(find.text('common.clear'));
      await tester.pumpAndSettle();
      expect(result?.cleared, isTrue);
    });
  });

  for (final width in <double>[360, 700, 1200]) {
    testWidgets('lays out without overflow at ${width}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        host(
          width: width,
          offset: const RelativeDate(amount: -6, unit: RelativeDateUnit.weeks),
          eventDate: DateTime(2026, 11, 12),
        ),
      );
      await open(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    });
  }

  group('the rule in words', () {
    testWidgets('the sign picks the before or after sentence', (tester) async {
      late String before;
      late String after;
      late String working;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              before = offsetSentence(
                context,
                const RelativeDate(amount: -4, unit: RelativeDateUnit.weeks),
              );
              after = offsetSentence(context, const RelativeDate(amount: 3));
              working = offsetSentence(
                context,
                const RelativeDate(
                  amount: -7,
                  basis: RelativeDateBasis.working,
                ),
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // The harness renders raw keys, so what is observable here is which
      // sentence the sign chose — the unit and the basis are interpolated into
      // it and only visible with real translations loaded.
      expect(before, contains('issues.deadline.sentenceBefore'));
      expect(after, contains('issues.deadline.sentenceAfter'));
      expect(working, contains('issues.deadline.sentenceBefore'));
    });
  });
}
