import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/widgets/coverage_hex.dart';
import 'package:hinata/features/shifts/widgets/next_shift_hero.dart';
import 'package:hinata/features/shifts/widgets/shift_actions.dart';
import 'package:hinata/features/shifts/widgets/shift_row.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'shift_fakes.dart';

/// The building blocks of the helper surfaces (HIN-44): the coverage cell in
/// its four states, the one-action table, the row and the hero at a phone's
/// width and twice the text size, and every refusal in the reader's words.
void main() {
  group('shiftOfferFor follows the state table', () {
    test('assigned: confirm first, decline beside it', () {
      final offer = shiftOfferFor(
        sampleShift(mine: true),
        status: ShiftAssignmentStatus.assigned,
      );
      expect(offer.primary, ShiftAction.confirm);
      expect(offer.secondary, ShiftAction.decline);
    });

    test('confirmed: give up, quietly', () {
      final offer = shiftOfferFor(
        sampleShift(mine: true),
        status: ShiftAssignmentStatus.confirmed,
      );
      expect(offer.primary, isNull);
      expect(offer.secondary, ShiftAction.release);
    });

    test('free: sign up; full: the waiting list, or words without sign-up', () {
      expect(shiftOfferFor(sampleShift()).primary, ShiftAction.join);
      final full = shiftOfferFor(sampleShift(assigned: 5, required: 5, max: 5));
      expect(full.primary, isNull);
      expect(full.secondary, ShiftAction.waitlistJoin);
      final closed = shiftOfferFor(
        sampleShift(assigned: 5, required: 5, max: 5),
        selfAssignable: false,
      );
      expect(closed.secondary, isNull);
      expect(closed.noteKey, 'shifts.offer.full');
    });

    test('closed for sign-up or cancelled: nothing to press', () {
      expect(
        shiftOfferFor(sampleShift(), selfAssignable: false).noteKey,
        'shifts.offer.plannersOnly',
      );
      expect(
        shiftOfferFor(sampleShift(), eventCancelled: true).noteKey,
        'shifts.offer.cancelled',
      );
    });
  });

  testWidgets('the coverage cell in all four states: glyph, figure, sentence', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final samples = <(Coverage, IconData, String, String)>[
      (
        const Coverage(assigned: 1, required: 2),
        LucideIcons.triangleAlert,
        '1 / 2',
        'Besetzung 1 von 2, Es fehlt noch 1 Person',
      ),
      (
        const Coverage(assigned: 3, required: 3),
        LucideIcons.check,
        '3 / 3',
        'Besetzung 3 von 3, Besetzt',
      ),
      (
        const Coverage(assigned: 4, required: 3, max: 5),
        LucideIcons.check,
        '4 / 3 · max. 5',
        'Besetzung 4 von 3, 1 Person mehr als gebraucht',
      ),
      (
        const Coverage(assigned: 5, required: 5, max: 5),
        LucideIcons.lock,
        '5 / 5',
        'Besetzung 5 von 5, Voll, 5 von 5',
      ),
    ];
    await pumpShiftsUi(
      tester,
      Column(
        children: [
          for (final (coverage, _, _, _) in samples)
            CoverageHex(coverage: coverage),
        ],
      ),
      repository: FakeShiftRepository(),
    );
    for (final (_, glyph, figure, sentence) in samples) {
      expect(find.byIcon(glyph), findsWidgets);
      expect(find.text(figure), findsOneWidget);
      expect(find.bySemanticsLabel(sentence), findsOneWidget);
    }
    handle.dispose();
  });

  testWidgets('a row outside a day list names its day first', (tester) async {
    await pumpShiftsUi(
      tester,
      ListView(
        children: [
          ShiftRow(
            shift: sampleShift(assigned: 1, required: 2),
            day: 'Mo., 26. Okt.',
            eventTitle: 'Messewoche',
            location: 'Halle 4',
          ),
        ],
      ),
      repository: FakeShiftRepository(),
    );
    expect(find.text('Mo., 26. Okt. · Messewoche · Halle 4'), findsOneWidget);
  });

  for (final scale in const [1.0, 2.0]) {
    testWidgets('a row at 320 px and text x$scale does not overflow', (
      tester,
    ) async {
      await pumpShiftsUi(
        tester,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ShiftRow(
              shift: sampleShift(assigned: 12, required: 15),
              eventTitle: 'Messewoche der Zulieferbetriebe',
              location: 'Halle 4, Stand B12',
              people: const ['Lena Vogt', 'Tomáš Horák', 'Amara Okafor'],
              stacked: true,
              trailing: const Text('Eintragen'),
            ),
          ],
        ),
        repository: FakeShiftRepository(),
        width: 320,
        scale: scale,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('12 / 15'), findsOneWidget);
    });
  }

  for (final status in [
    ShiftAssignmentStatus.assigned,
    ShiftAssignmentStatus.confirmed,
  ]) {
    testWidgets(
      'the hero at 390 px, text x2, ${status.name}: one primary action',
      (tester) async {
        final next = sampleMine(status: status);
        final actions = ShiftActionsCubit(FakeShiftRepository());
        addTearDown(actions.close);
        await pumpShiftsUi(
          tester,
          SingleChildScrollView(
            child: NextShiftHero(
              next: next,
              now: DateTime(2026, 10, 23, 20),
              detail: ShiftDetail(
                shift: next.shift.copyWith(),
                event: sampleEvent,
                users: const {
                  'u1': ShiftUser(name: 'Lena Vogt'),
                  'me': ShiftUser(name: 'Ich'),
                },
              ),
              selfId: 'me',
              onAction: (_) {},
            ),
          ),
          repository: FakeShiftRepository(),
          blocs: [BlocProvider<ShiftActionsCubit>.value(value: actions)],
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('NÄCHSTE SCHICHT'), findsOneWidget);
        if (status == ShiftAssignmentStatus.assigned) {
          expect(find.text('Bestätigen'), findsOneWidget);
          expect(find.text('Ablehnen'), findsOneWidget);
          expect(find.text('Abgeben'), findsNothing);
        } else {
          expect(find.text('Bestätigen'), findsNothing);
          expect(find.text('Abgeben'), findsOneWidget);
        }
        expect(find.textContaining('in 18 Std.'), findsOneWidget);
      },
    );
  }

  testWidgets('offline the hero counts the others and names nobody', (
    tester,
  ) async {
    final actions = ShiftActionsCubit(FakeShiftRepository());
    addTearDown(actions.close);
    await pumpShiftsUi(
      tester,
      NextShiftHero(
        next: sampleMine(
          shift: sampleShift(assigned: 2, mine: true, assigneeIds: ['u1']),
        ),
        now: DateTime(2026, 10, 23, 20),
        offline: true,
        onAction: (_) {},
      ),
      repository: FakeShiftRepository(),
      blocs: [BlocProvider<ShiftActionsCubit>.value(value: actions)],
    );
    expect(find.text('mit 1 weiteren Person'), findsOneWidget);
    expect(find.text('Abgeben'), findsNothing);
  });

  const codes = [
    'error.shifts.alreadyAssigned',
    'error.shifts.assigneeNotMember',
    'error.shifts.assignmentNotPending',
    'error.shifts.batchInvalid',
    'error.shifts.busy',
    'error.shifts.eventHasAssignments',
    'error.shifts.maxBelowAssigned',
    'error.shifts.notPlanner',
    'error.shifts.overlappingAssignment',
    'error.shifts.plannerNotMember',
    'error.shifts.selfAssignDisabled',
    'error.shifts.shiftFull',
    'error.shifts.shiftUnavailable',
  ];
  for (final locale in const ['de', 'en']) {
    testWidgets('every error.shifts key reads as a sentence in $locale', (
      tester,
    ) async {
      final bundle = FileI18nSource.bundle(locale);
      final errors = (bundle['error'] as Map)['shifts'] as Map;
      late BuildContext context;
      await pumpShiftsUi(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
        repository: FakeShiftRepository(),
        locale: locale,
      );
      for (final code in codes) {
        final sentence = errors[code.split('.').last] as String?;
        expect(sentence, isNotNull, reason: '$locale lacks $code');
        announceShiftOutcome(context, ShiftActionOutcome.failed(code));
        await tester.pump();
        expect(find.text(sentence!), findsOneWidget, reason: code);
        expect(find.text(code), findsNothing);
      }
      // Let the last toast run out.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
