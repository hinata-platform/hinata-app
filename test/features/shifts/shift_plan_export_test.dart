import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/models/shift_plan_export.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/shell/page_chrome.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_plan_export_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_planning_cubit.dart';
import 'package:hinata/features/shifts/view/shift_event_screen.dart';
import 'package:hinata/features/shifts/widgets/shift_plan_export.dart';

import 'shift_fakes.dart';

/// "Schichtplan exportieren" (HIN-163): the file name, the cubit that keeps
/// names to planners, and the dialog.
void main() {
  group('file name', () {
    test('reads the UTF-8 name out of Content-Disposition first', () {
      expect(
        fileNameFromDisposition(
          'attachment; filename="=?UTF-8?Q?x?="; '
          "filename*=UTF-8''schichtplan-Stra%C3%9Fenfest-20261024.pdf",
        ),
        'schichtplan-Straßenfest-20261024.pdf',
      );
      expect(
        fileNameFromDisposition('attachment; filename="shift-plan-a.xlsx"'),
        'shift-plan-a.xlsx',
      );
      // An encoded word alone is not a name, and a path is cut to its end.
      expect(
        fileNameFromDisposition('attachment; filename="=?UTF-8?Q?a?="'),
        null,
      );
      expect(
        fileNameFromDisposition("attachment; filename*=UTF-8''..%2F..%2Fx.pdf"),
        'x.pdf',
      );
      expect(fileNameFromDisposition(null), null);
      expect(fileNameFromDisposition('attachment'), null);
    });

    test('builds the name by the server rule', () {
      expect(
        shiftPlanFileName(
          word: 'schichtplan',
          title: '  Tag der offenen Tür: Halle 3! ',
          startsLocal: DateTime(2026, 3, 7, 23, 30),
          format: ShiftPlanFormat.docx,
        ),
        'schichtplan-Tag-der-offenen-Tür-Halle-3-20260307.docx',
      );
      expect(
        shiftPlanFileName(
          word: 'shift-plan',
          title: '!!!',
          startsLocal: DateTime(2026, 10, 24),
          format: ShiftPlanFormat.xlsx,
        ),
        'shift-plan-event-20261024.xlsx',
      );
      final long = shiftPlanFileName(
        word: 'w',
        title: '${'a' * 79} b',
        startsLocal: DateTime(2026, 1, 2),
        format: ShiftPlanFormat.pdf,
      );
      // Cut at the server's 80 characters, without a dash left dangling.
      expect(long, 'w-${'a' * 79}-20260102.pdf');
    });
  });

  group('cubit', () {
    late FakeShiftRepository repo;
    setUp(() => repo = FakeShiftRepository());

    blocTest<ShiftPlanExportCubit, ShiftPlanExportState>(
      'a helper cannot switch names on',
      build: () => ShiftPlanExportCubit(repo, sampleSummary()),
      act: (cubit) async {
        cubit
          ..setNames(true)
          ..selectFormat(ShiftPlanFormat.xlsx);
        await cubit.fetch();
      },
      expect: () => const [
        ShiftPlanExportState(format: ShiftPlanFormat.xlsx),
        ShiftPlanExportState(format: ShiftPlanFormat.xlsx, running: true),
        ShiftPlanExportState(format: ShiftPlanFormat.xlsx),
      ],
      verify: (_) {
        expect(repo.lastNames, isFalse);
        expect(repo.calls, ['exportPlan:e1:xlsx']);
      },
    );

    blocTest<ShiftPlanExportCubit, ShiftPlanExportState>(
      'a planner asks for names and the chosen format',
      build: () => ShiftPlanExportCubit(repo, sampleSummary(canPlan: true)),
      act: (cubit) async {
        cubit
          ..selectFormat(ShiftPlanFormat.docx)
          ..setNames(true);
        repo.planFile = ShiftPlanFile(
          bytes: Uint8List.fromList([1, 2]),
          truncated: true,
        );
        expect(await cubit.fetchTo('/tmp/plan.docx'), isTrue);
      },
      expect: () => const [
        ShiftPlanExportState(format: ShiftPlanFormat.docx),
        ShiftPlanExportState(format: ShiftPlanFormat.docx, names: true),
        ShiftPlanExportState(
          format: ShiftPlanFormat.docx,
          names: true,
          running: true,
        ),
        ShiftPlanExportState(format: ShiftPlanFormat.docx, names: true),
      ],
      verify: (_) {
        expect(repo.lastNames, isTrue);
        expect(repo.calls, ['exportPlanTo:e1:docx']);
      },
    );

    test('a second press while a file is on its way does nothing', () async {
      final cubit = ShiftPlanExportCubit(repo, sampleSummary());
      addTearDown(cubit.close);
      repo.gate = Completer<void>();
      final first = cubit.fetch();
      expect(cubit.state.running, isTrue);
      expect(await cubit.fetch(), isNull);
      repo.gate!.complete();
      expect(await first, isNotNull);
      expect(cubit.state.running, isFalse);
      expect(repo.calls, ['exportPlan:e1:pdf']);
    });

    test('a refusal travels up and the cubit is ready again', () async {
      final cubit = ShiftPlanExportCubit(repo, sampleSummary(canPlan: true));
      addTearDown(cubit.close);
      repo.failure = ApiFailure('Zu viele Exporte', statusCode: 429);
      await expectLater(cubit.fetch(), throwsA(isA<ApiFailure>()));
      expect(cubit.state.running, isFalse);
    });

    test('names the file in the format chosen', () {
      final cubit = ShiftPlanExportCubit(repo, sampleSummary())
        ..selectFormat(ShiftPlanFormat.xlsx);
      addTearDown(cubit.close);
      expect(
        cubit.fileName('schichtplan'),
        'schichtplan-Sommerfest-20261024.xlsx',
      );
    });
  });

  group('dialog', () {
    late FakeShiftRepository repo;
    setUp(() => repo = FakeShiftRepository());

    Future<ShiftPlanExportCubit> pumpBody(
      WidgetTester tester, {
      required bool canPlan,
      String locale = 'de',
      double width = 440,
      double scale = 1,
    }) async {
      final cubit = ShiftPlanExportCubit(repo, sampleSummary(canPlan: canPlan));
      addTearDown(cubit.close);
      await pumpShiftsUi(
        tester,
        SingleChildScrollView(
          child: BlocProvider.value(
            value: cubit,
            child: const ShiftPlanExportBody(),
          ),
        ),
        repository: repo,
        locale: locale,
        width: width,
        scale: scale,
      );
      await tester.pump();
      return cubit;
    }

    testWidgets('a helper picks a format; no names switch', (tester) async {
      final cubit = await pumpBody(tester, canPlan: false);
      expect(find.text('Schichtplan exportieren'), findsOneWidget);
      for (final label in ['PDF', 'Word', 'Tabelle']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Mit Namen'), findsNothing);
      expect(
        find.text('Die Datei enthält dann Namen von Personen.'),
        findsNothing,
      );
      expect(find.text('Exportieren'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      await tester.tap(find.text('Tabelle'));
      await tester.pump();
      expect(cubit.state.format, ShiftPlanFormat.xlsx);
      expect(
        tester.getSemantics(find.text('Tabelle')),
        containsSemantics(isSelected: true, isButton: true),
      );
    });

    testWidgets('a planner switches names on with the sentence beside it', (
      tester,
    ) async {
      final cubit = await pumpBody(tester, canPlan: true);
      expect(find.text('Mit Namen'), findsOneWidget);
      expect(
        find.text('Die Datei enthält dann Namen von Personen.'),
        findsOneWidget,
      );
      expect(cubit.state.names, isFalse);
      await tester.tap(find.byType(HiveSwitch));
      await tester.pump();
      expect(cubit.state.names, isTrue);
    });

    for (final (width, scale) in [(320.0, 2.0), (320.0, 1.0), (1440.0, 2.0)]) {
      for (final locale in ['de', 'en']) {
        testWidgets('fits $width px at ${scale}x text ($locale)', (
          tester,
        ) async {
          await pumpBody(
            tester,
            canPlan: true,
            locale: locale,
            width: width,
            scale: scale,
          );
          expect(tester.takeException(), isNull);
          final segment = tester.getSize(
            find.text(locale == 'de' ? 'Tabelle' : 'Spreadsheet'),
          );
          expect(segment.width, greaterThan(0));
          final hit = tester.getSize(
            find
                .ancestor(of: find.text('PDF'), matching: find.byType(InkWell))
                .first,
          );
          expect(hit.height, greaterThanOrEqualTo(48));
        });
      }
    }
  });

  group('event menu', () {
    late FakeShiftRepository repo;
    late ShiftActionsCubit actions;
    late ShiftPlanningCubit planning;

    setUp(() {
      repo = FakeShiftRepository();
      actions = ShiftActionsCubit(repo);
      planning = ShiftPlanningCubit(repo);
      addTearDown(actions.close);
      addTearDown(planning.close);
    });

    Future<void> pumpEvent(WidgetTester tester, {required bool canPlan}) async {
      repo.eventDetail = ShiftEventDetail(
        summary: sampleSummary(canPlan: canPlan),
        shifts: [sampleShift()],
      );
      await pumpShiftsUi(
        tester,
        const ShiftEventScreen(eventId: 'e1'),
        repository: repo,
        blocs: [
          BlocProvider<ShiftActionsCubit>.value(value: actions),
          BlocProvider<ShiftPlanningCubit>.value(value: planning),
        ],
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> openMenu(WidgetTester tester) async {
      final chrome = tester.widget<PageChrome>(find.byType(PageChrome));
      final more = chrome.actions.singleWhere((a) => a.label == 'Mehr');
      more.onTap!(const Rect.fromLTWH(300, 20, 40, 40));
      // The glass spring opens over most of a second.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('a helper gets "Mehr" with the export alone', (tester) async {
      await pumpEvent(tester, canPlan: false);
      await openMenu(tester);
      expect(find.text('Schichtplan exportieren'), findsOneWidget);
      expect(find.text('Bearbeiten'), findsNothing);
      expect(find.text('Löschen'), findsNothing);
    });

    testWidgets('a planner gets the export beside the planning entries', (
      tester,
    ) async {
      await pumpEvent(tester, canPlan: true);
      await openMenu(tester);
      expect(find.text('Schichtplan exportieren'), findsOneWidget);
      expect(find.text('Bearbeiten'), findsOneWidget);
    });

    testWidgets('a refusal shows the server sentence as a toast', (
      tester,
    ) async {
      final temp = Directory.systemTemp.createTempSync('hin163');
      addTearDown(() => temp.deleteSync(recursive: true));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      await pumpEvent(tester, canPlan: false);
      await openMenu(tester);
      await tester.tap(find.text('Schichtplan exportieren'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      repo.failure = ApiFailure(
        'Zu viele Exporte. Versuch es in einer Minute noch einmal.',
        statusCode: 429,
      );
      await tester.tap(find.text('Exportieren'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.text('Zu viele Exporte. Versuch es in einer Minute noch einmal.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
    });
  });
}
