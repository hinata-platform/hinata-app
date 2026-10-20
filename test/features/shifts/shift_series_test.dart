import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/models/shift_series.dart';
import 'package:hinata/features/shifts/bloc/shift_calendar_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_changes.dart';
import 'package:hinata/features/shifts/bloc/shift_editor_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_event_editor_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_planning_cubit.dart';
import 'package:hinata/features/shifts/widgets/series_repeat_picker.dart';
import 'package:hinata/features/shifts/widgets/series_scope_dialog.dart';
import 'package:hinata/features/shifts/widgets/shift_event_card.dart';
import 'package:hinata/features/shifts/widgets/shift_event_editor.dart';

import 'shift_fakes.dart';

/// Recurring events (HIN-161): the rule the app builds, the cubits that send
/// it with the scope the planner picked, and the surfaces that ask.
void main() {
  // 26 October 2026 is a Monday.
  final monday = DateTime(2026, 10, 26, 18);

  group('SeriesRule builds the server\'s subset', () {
    test('daily, weekly on the start\'s weekday, monthly on its day', () {
      expect(const SeriesRule.daily().toRrule(), 'FREQ=DAILY');
      expect(SeriesRule.weekly(monday).toRrule(), 'FREQ=WEEKLY;BYDAY=MO');
      expect(
        SeriesRule.monthly(monday).toRrule(),
        'FREQ=MONTHLY;BYMONTHDAY=26',
      );
    });

    test('several weekdays sorted, an interval, never an RRULE prefix', () {
      const rule = SeriesRule(
        frequency: SeriesFrequency.weekly,
        interval: 2,
        weekdays: {DateTime.friday, DateTime.monday, DateTime.wednesday},
      );
      expect(rule.toRrule(), 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR');
      expect(rule.toRrule(), isNot(startsWith('RRULE:')));
    });

    test('an end is COUNT or UNTIL as a date, never both', () {
      final weekly = SeriesRule.weekly(monday);
      expect(
        weekly.withEnd(count: 6).toRrule(),
        'FREQ=WEEKLY;BYDAY=MO;COUNT=6',
      );
      expect(
        weekly.withEnd(until: DateTime(2026, 12, 31)).toRrule(),
        'FREQ=WEEKLY;BYDAY=MO;UNTIL=20261231',
      );
      final both = weekly
          .withEnd(until: DateTime(2026, 12, 31))
          .withEnd(count: 3);
      expect(both.until, isNull);
      expect(both.toRrule(), 'FREQ=WEEKLY;BYDAY=MO;COUNT=3');
      expect(both.withEnd().toRrule(), 'FREQ=WEEKLY;BYDAY=MO');
    });

    test('the interval stays within 1 to 100, COUNT within 5000', () {
      expect(
        const SeriesRule(
          frequency: SeriesFrequency.daily,
          interval: 400,
          count: 9000,
        ).toRrule(),
        'FREQ=DAILY;INTERVAL=100;COUNT=5000',
      );
    });

    test('a BYDAY on a monthly rule is never written', () {
      const rule = SeriesRule(
        frequency: SeriesFrequency.monthly,
        weekdays: {DateTime.monday},
        monthDay: 15,
      );
      expect(rule.toRrule(), 'FREQ=MONTHLY;BYMONTHDAY=15');
    });

    test('reads back what the server holds, prefix or not', () {
      const rule = SeriesRule(
        frequency: SeriesFrequency.weekly,
        interval: 3,
        weekdays: {DateTime.monday, DateTime.wednesday},
        until: null,
        count: 12,
      );
      expect(SeriesRule.parse(rule.toRrule()), rule);
      expect(
        SeriesRule.parse('RRULE:FREQ=MONTHLY;BYMONTHDAY=20;UNTIL=20270101'),
        SeriesRule(
          frequency: SeriesFrequency.monthly,
          monthDay: 20,
          until: DateTime(2027),
        ),
      );
      expect(SeriesRule.parse('FREQ=YEARLY'), isNull);
      expect(SeriesRule.parse(null), isNull);
    });
  });

  group('series models', () {
    test('a draft sends wall clocks without seconds or offset', () {
      final draft = SeriesDraft(
        title: ' Thekendienst ',
        firstStart: monday,
        durationMinutes: 240,
        rule: SeriesRule.weekly(monday),
        location: 'Vereinsheim',
        timezone: 'Europe/Berlin',
        shifts: const [
          SeriesTemplate(
            title: 'Theke',
            startMinutes: 18 * 60,
            endMinutes: 20 * 60,
            requiredHelpers: 2,
          ),
        ],
      );
      final json = draft.toJson();
      expect(json['title'], 'Thekendienst');
      expect(json['firstStart'], '2026-10-26T18:00');
      expect(json['rrule'], 'FREQ=WEEKLY;BYDAY=MO');
      expect(json['description'], isNull);
      expect((json['shifts'] as List).single, {
        'key': null,
        'title': 'Theke',
        'dayOffset': 0,
        'start': '18:00',
        'end': '20:00',
        'requiredHelpers': 2,
        'maxHelpers': null,
      });
    });

    test('times are read with and without seconds', () {
      expect(parseSeriesTime('18:00'), 18 * 60);
      expect(parseSeriesTime('07:30:00'), 7 * 60 + 30);
      expect(parseSeriesTime('25:00'), isNull);
      final series = ShiftSeries.fromJson(const {
        'id': 'sr1',
        'firstStart': '2026-10-26T18:00',
        'durationMinutes': 240,
        'rrule': 'FREQ=WEEKLY;BYDAY=MO,WE',
        'recurrenceLabel': 'wöchentlich Mo, Mi',
        'exdates': ['2026-11-02'],
        'shifts': [
          {'key': 'k1', 'title': 'Theke', 'start': '18:00:00', 'end': '20:00'},
        ],
        'next': [
          {
            'date': '2026-10-26',
            'startsAt': '2026-10-26T17:00:00Z',
            'endsAt': '2026-10-26T21:00:00Z',
            'startsLocal': '2026-10-26T18:00:00',
            'endsLocal': '2026-10-26T22:00:00',
          },
        ],
        'occurrencesCreated': 26,
      });
      expect(series.firstStart, monday);
      expect(series.exdates, [DateTime(2026, 11, 2)]);
      expect(series.shifts.single.startMinutes, 18 * 60);
      expect(series.next.single.date, DateTime(2026, 10, 26));
      expect(series.rule!.weekdays, {DateTime.monday, DateTime.wednesday});
      expect(series.occurrencesCreated, 26);
    });

    test('events and heads say their series, older answers none', () {
      final summary = ShiftEventSummary.fromJson(const {
        'id': 'e1',
        'seriesId': 'sr1',
        'recurrenceLabel': 'wöchentlich Mo',
        'detached': true,
      });
      expect(summary.inSeries, isTrue);
      expect(summary.recurrenceLabel, 'wöchentlich Mo');
      expect(summary.detached, isTrue);
      final head = ShiftEventHead.fromJson(const {'id': 'e1', 'title': 'x'});
      expect(head.inSeries, isFalse);
      expect(head.detached, isFalse);
      expect(ShiftEventHead.fromJson(head.toJson()), head);
    });
  });

  group('ShiftEventEditorCubit with a rule', () {
    late FakeShiftRepository repo;

    setUp(() => repo = FakeShiftRepository());

    ShiftEventEditorCubit fresh() {
      final cubit = ShiftEventEditorCubit(
        repo,
        projectId: 'p1',
        projectName: 'Verein',
        deviceZone: 'Europe/Berlin',
        day: monday,
        previewDelay: Duration.zero,
      );
      addTearDown(cubit.close);
      return cubit;
    }

    Future<void> rest() async {
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('starts at "Nie" and asks the server for the words', () async {
      repo.preview = SeriesPreview(
        recurrenceLabel: 'wöchentlich Mo',
        next: [
          SeriesOccurrence(
            date: DateTime(2026, 10, 26),
            startsAt: DateTime.utc(2026, 10, 26, 9),
            endsAt: DateTime.utc(2026, 10, 26, 17),
            startsLocal: DateTime(2026, 10, 26, 10),
            endsLocal: DateTime(2026, 10, 26, 18),
          ),
        ],
      );
      final cubit = fresh();
      expect(cubit.state.repeat, SeriesRepeat.never);
      expect(cubit.state.rule, isNull);
      cubit.setRepeat(SeriesRepeat.weekly);
      expect(cubit.state.previewing, isTrue);
      await rest();
      expect(repo.calls, ['previewSeries:p1']);
      expect(repo.lastDraft!.rule.toRrule(), 'FREQ=WEEKLY;BYDAY=MO');
      // The server wants a name even for a preview.
      expect(repo.lastDraft!.toJson()['title'], isNotEmpty);
      expect(cubit.state.preview!.recurrenceLabel, 'wöchentlich Mo');
      expect(cubit.state.previewing, isFalse);
    });

    test('a preset follows the start to another weekday', () async {
      final cubit = fresh();
      cubit.setRepeat(SeriesRepeat.weekly);
      cubit.setStart(DateTime(2026, 10, 27, 10));
      expect(cubit.state.rule!.toRrule(), 'FREQ=WEEKLY;BYDAY=TU');
      await rest();
      // Only the last change is asked, once.
      expect(repo.calls.where((c) => c.startsWith('previewSeries')), [
        'previewSeries:p1',
      ]);
    });

    test('a refused preview says why', () async {
      repo.failure = refusal('error.shifts.seriesTooLarge', status: 400);
      final cubit = fresh();
      cubit.setRepeat(SeriesRepeat.daily);
      await rest();
      expect(cubit.state.previewErrorKey, 'error.shifts.seriesTooLarge');
      expect(cubit.state.preview, isNull);
    });

    test('saving a rule creates a series and finds its first event', () async {
      final first = SeriesOccurrence(
        date: DateTime(2026, 10, 26),
        startsAt: DateTime.utc(2026, 10, 26, 9),
        endsAt: DateTime.utc(2026, 10, 26, 17),
        startsLocal: DateTime(2026, 10, 26, 10),
        endsLocal: DateTime(2026, 10, 26, 18),
      );
      repo.createdSeries = ShiftSeries(
        id: 'sr1',
        projectId: 'p1',
        title: 'Sprechstunde',
        firstStart: DateTime(2026, 10, 26, 10),
        durationMinutes: 480,
        rrule: 'FREQ=MONTHLY;BYMONTHDAY=26;COUNT=6',
        recurrenceLabel: 'monatlich am 26., 6 Mal',
        next: [first],
        occurrencesCreated: 3,
      );
      repo.eventPage = (
        items: [
          sampleSummary(id: 'other'),
          sampleSummary(seriesId: 'sr1'),
        ],
        total: 2,
      );
      final cubit = fresh();
      cubit.setTitle('Sprechstunde');
      cubit.setRepeat(
        SeriesRepeat.custom,
        custom: SeriesRule.monthly(monday).withEnd(count: 6),
      );
      final saved = await cubit.save();
      expect(saved!.series!.id, 'sr1');
      expect(saved.eventId, 'e1');
      expect(repo.calls, contains('createSeries:p1'));
      expect(repo.calls, isNot(contains('createEvent:p1')));
      final body = repo.lastDraft!.toJson();
      expect(body['rrule'], 'FREQ=MONTHLY;BYMONTHDAY=26;COUNT=6');
      expect(body['firstStart'], '2026-10-26T10:00');
      expect(body['durationMinutes'], 8 * 60);
      expect(body['timezone'], 'Europe/Berlin');
      expect(repo.lastFrom, first.startsAt);
    });

    test('a single event offers no rule afterwards', () {
      final cubit = ShiftEventEditorCubit(
        repo,
        existing: ShiftEventDetail(summary: sampleSummary()),
        deviceZone: 'Europe/Berlin',
      );
      addTearDown(cubit.close);
      expect(cubit.canRepeat, isFalse);
    });

    group('an occurrence', () {
      ShiftEventEditorCubit occurrence() {
        repo.seriesAnswer = ShiftSeries(
          id: 'sr1',
          projectId: 'p1',
          title: 'Sommerfest',
          firstStart: DateTime(2026, 10, 24, 14),
          durationMinutes: 780,
          rrule: 'FREQ=WEEKLY;BYDAY=SA',
          recurrenceLabel: 'wöchentlich Sa',
        );
        repo.eventChange = ShiftEventChange(
          event: ShiftEventDetail(summary: sampleSummary(seriesId: 'sr2')),
        );
        final cubit = ShiftEventEditorCubit(
          repo,
          existing: ShiftEventDetail(
            summary: sampleSummary(
              seriesId: 'sr1',
              recurrenceLabel: 'wöchentlich Sa',
            ),
          ),
          deviceZone: 'Europe/Berlin',
          previewDelay: Duration.zero,
        );
        addTearDown(cubit.close);
        return cubit;
      }

      test('opens on its series\' rule', () async {
        final cubit = occurrence();
        await cubit.loadSeries();
        expect(repo.calls, ['series:sr1']);
        expect(cubit.state.repeat, SeriesRepeat.weekly);
        expect(cubit.ruleChanged, isFalse);
      });

      test('nothing changed asks nothing; a change asks the scope', () async {
        final cubit = occurrence();
        await cubit.loadSeries();
        expect(await cubit.asksScope(), isFalse);
        cubit.setTitle('Sommerfest am See');
        expect(await cubit.asksScope(), isTrue);
        final saved = await cubit.save(scope: ShiftScope.single);
        expect(repo.calls.last, 'updateEvent:e1:this');
        expect(repo.lastPatch, {'title': 'Sommerfest am See'});
        expect(saved!.event!.summary.seriesId, 'sr2');
      });

      test('a new rule goes along only for all future ones', () async {
        final cubit = occurrence();
        await cubit.loadSeries();
        cubit.setRepeat(SeriesRepeat.daily);
        expect(cubit.ruleChanged, isTrue);
        expect(await cubit.asksScope(), isTrue);
        await rest();
        expect(repo.calls, contains('previewSeries:p1'));
        await cubit.save(scope: ShiftScope.future);
        expect(repo.calls.last, 'updateEvent:e1:future');
        expect(repo.lastPatch, {'rrule': 'FREQ=DAILY'});
      });
    });
  });

  group('writes to an occurrence carry the scope', () {
    late FakeShiftRepository repo;

    setUp(() => repo = FakeShiftRepository());

    final occurrence = sampleSummary(seriesId: 'sr1');

    test('a new shift for all future ones is one shift, not a batch', () async {
      repo.createdShift = sampleShift(id: 'n1');
      final cubit = ShiftEditorCubit(
        repo,
        event: occurrence,
        deviceZone: 'Europe/Berlin',
      );
      addTearDown(cubit.close);
      expect(await cubit.asksScope(), isTrue);
      expect(await cubit.save(scope: ShiftScope.future), isTrue);
      expect(repo.calls, ['createShift:e1:future']);
    });

    test('only this one goes as a batch with scope this', () async {
      final cubit = ShiftEditorCubit(
        repo,
        event: occurrence,
        deviceZone: 'Europe/Berlin',
      );
      addTearDown(cubit.close);
      expect(await cubit.save(scope: ShiftScope.single), isTrue);
      expect(repo.calls, ['createShifts:e1:1:this']);
    });

    test(
      'a changed shift names its scope; an unchanged one asks nothing',
      () async {
        final shift = sampleShift(id: 's1', start: DateTime(2026, 10, 24, 14));
        repo.shiftEdit = ShiftEdit(shift: shift);
        final cubit = ShiftEditorCubit(
          repo,
          event: occurrence,
          shift: shift,
          deviceZone: 'Europe/Berlin',
        );
        addTearDown(cubit.close);
        expect(await cubit.asksScope(), isFalse);
        cubit.stepRequired(1);
        expect(await cubit.asksScope(), isTrue);
        await cubit.save(scope: ShiftScope.future);
        expect(repo.calls, ['updateShift:s1:future']);
      },
    );

    test('an event outside a series sends no scope', () async {
      final cubit = ShiftEditorCubit(
        repo,
        event: sampleSummary(),
        deviceZone: 'Europe/Berlin',
      );
      addTearDown(cubit.close);
      expect(await cubit.asksScope(), isFalse);
      await cubit.save(scope: ShiftScope.future);
      expect(repo.calls, ['createShifts:e1:1']);
    });

    test('calling off, deleting and moving name their scope', () async {
      repo.eventDetail = ShiftEventDetail(summary: occurrence);
      final planning = ShiftPlanningCubit(repo);
      addTearDown(planning.close);
      await planning.cancelEvent('e1', scope: ShiftScope.future);
      await planning.deleteEvent('e1', scope: ShiftScope.single);
      await planning.deleteShift(sampleShift(), scope: ShiftScope.future);
      expect(repo.calls, [
        'cancelEvent:e1:future',
        'deleteEvent:e1:this',
        'deleteShift:s1:future',
      ]);

      final bus = StreamController<ShiftChange>.broadcast();
      addTearDown(bus.close);
      final shift = sampleShift(id: 's1');
      repo.shiftEdit = ShiftEdit(shift: shift);
      final calendar = ShiftCalendarCubit(
        repo,
        focused: DateTime(2026, 10, 24),
        changes: bus.stream,
      );
      addTearDown(calendar.close);
      await calendar.move(
        shift,
        DateTime(2026, 10, 24, 15),
        DateTime(2026, 10, 24, 18),
        scope: ShiftScope.single,
      );
      expect(repo.calls, contains('updateShift:s1:this'));
    });
  });

  group('surfaces', () {
    late FakeShiftRepository repo;

    setUp(() => repo = FakeShiftRepository());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    for (final (width, scale) in [(320.0, 2.0), (1180.0, 1.0)]) {
      testWidgets('the scope dialog chooses nothing ahead, $width px x$scale', (
        tester,
      ) async {
        ShiftScope? picked;
        var done = false;
        await pumpShiftsUi(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await askSeriesScope(
                  context,
                  write: SeriesWrite.delete,
                  day: DateTime(2026, 10, 24),
                  recurrenceLabel: 'wöchentlich Sa',
                );
                done = true;
              },
              child: const Text('open'),
            ),
          ),
          repository: repo,
          width: width,
          height: 1400,
          scale: scale,
        );
        await tester.tap(find.text('open'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Nur dieses'), findsOneWidget);
        expect(find.text('Alle künftigen'), findsOneWidget);
        expect(find.text('Abbrechen'), findsOneWidget);
        expect(find.textContaining('wöchentlich Sa'), findsOneWidget);
        // Neither choice is marked or filled in advance.
        expect(find.byType(FilledButton), findsNothing);
        await tester.ensureVisible(find.text('Alle künftigen'));
        await tester.pump();
        await tester.tap(find.text('Alle künftigen'));
        await settle(tester);
        expect(done, isTrue);
        expect(picked, ShiftScope.future);
      });
    }

    testWidgets('a locked choice says why and cannot be picked', (
      tester,
    ) async {
      ShiftScope? picked;
      await pumpShiftsUi(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await askSeriesScope(
              context,
              write: SeriesWrite.save,
              day: DateTime(2026, 10, 24),
              singleLockedKey: 'shifts.series.scope.ruleOnlyFuture',
            ),
            child: const Text('open'),
          ),
        ),
        repository: repo,
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.textContaining('Eine neue Regel gilt immer'), findsOneWidget);
      await tester.tap(find.text('Nur dieses'));
      await settle(tester);
      expect(find.text('Alle künftigen'), findsOneWidget);
      expect(picked, isNull);
    });

    for (final (width, scale) in [(320.0, 2.0), (390.0, 1.0), (1180.0, 1.0)]) {
      testWidgets('"Wiederholen" opens its choices, $width px x$scale', (
        tester,
      ) async {
        final cubit = ShiftEventEditorCubit(
          repo,
          projectId: 'p1',
          projectName: 'Verein',
          deviceZone: 'Europe/Berlin',
          day: DateTime(2026, 10, 24),
          previewDelay: Duration.zero,
        );
        addTearDown(cubit.close);
        repo.preview = const SeriesPreview(recurrenceLabel: 'wöchentlich Sa');
        await pumpShiftsUi(
          tester,
          BlocProvider.value(
            value: cubit,
            child: const SingleChildScrollView(
              child: ShiftEventEditorBody(projectLocked: true),
            ),
          ),
          repository: repo,
          width: width,
          height: 1400,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Wiederholen'), findsOneWidget);
        expect(find.text('Nie'), findsOneWidget);
        await tester.tap(find.text('Wiederholen'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Täglich'), findsOneWidget);
        expect(find.text('Wöchentlich am Samstag'), findsOneWidget);
        expect(find.text('Monatlich am 24.'), findsOneWidget);
        expect(find.text('Eigene Regel'), findsOneWidget);
        // Only "Eigene Regel" shows weekdays, interval and end.
        expect(find.text('An diesen Tagen'), findsNothing);
        await tester.tap(find.text('Wöchentlich am Samstag'));
        await settle(tester);
        expect(cubit.state.repeat, SeriesRepeat.weekly);
        // The field and the head show the server's words.
        expect(find.text('wöchentlich Sa'), findsWidgets);
      });
    }

    for (final (width, scale) in [(320.0, 2.0), (1180.0, 1.0)]) {
      testWidgets('"Eigene Regel" shows days, interval and end, $width px', (
        tester,
      ) async {
        SeriesRepeatPick? picked;
        await pumpShiftsUi(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await showSeriesRepeatPicker(
                context,
                anchorRect: const Rect.fromLTWH(20, 20, 300, 56),
                start: monday,
                current: SeriesRepeat.never,
              ),
              child: const Text('open'),
            ),
          ),
          repository: repo,
          width: width,
          height: 1400,
          scale: scale,
        );
        await tester.tap(find.text('open'));
        await settle(tester);
        await tester.tap(find.text('Eigene Regel'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('An diesen Tagen'), findsOneWidget);
        expect(find.text('jede Woche'), findsOneWidget);
        expect(find.text('Kein Ende'), findsOneWidget);
        await tester.ensureVisible(find.text('Mi'));
        await tester.tap(find.text('Mi'));
        await tester.pump();
        await tester.ensureVisible(find.byTooltip('Abstand erhöhen'));
        await tester.tap(find.byTooltip('Abstand erhöhen'));
        await tester.pump();
        expect(find.text('alle 2 Wochen'), findsOneWidget);
        await tester.ensureVisible(find.text('Nach Anzahl'));
        await tester.tap(find.text('Nach Anzahl'));
        await tester.pump();
        expect(find.text('10 Mal'), findsOneWidget);
        await tester.ensureVisible(find.text('Übernehmen'));
        await tester.tap(find.text('Übernehmen'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        expect(picked!.repeat, SeriesRepeat.custom);
        expect(
          picked!.rule!.toRrule(),
          'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;COUNT=10',
        );
      });
    }

    testWidgets('a card says the rule and that it went its own way', (
      tester,
    ) async {
      await pumpShiftsUi(
        tester,
        ShiftEventCard(
          event: sampleSummary(
            seriesId: 'sr1',
            recurrenceLabel: 'wöchentlich Sa',
            detached: true,
          ),
        ),
        repository: repo,
        width: 320,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('wöchentlich Sa · abweichend von der Serie'),
        findsOneWidget,
      );
    });
  });
}
