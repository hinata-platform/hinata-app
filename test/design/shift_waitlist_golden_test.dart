// The waiting list of HIN-162 as people meet it: a full shift with "Auf
// Warteliste setzen", a waiting row with its rank, a planner's waiting chips,
// and "Meine Schichten" with the waiting group and a place that came off the
// list. A phone at 320 and 390 with text at 1.0 and 2.0, light and dark, and
// a wide window. Real fonts and German strings.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/repositories/shift_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/features/shifts/bloc/my_shifts_snapshot_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_planning_cubit.dart';
import 'package:hinata/features/shifts/view/my_shifts_view.dart';
import 'package:hinata/features/shifts/view/shift_event_screen.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:i18next/i18next.dart';

import '../features/shifts/shift_fakes.dart';
import '../support/timer_surface_fakes.dart' show MemoryStorage;
import 'golden_platform.dart';

Future<void> _loadFonts() async {
  Future<void> load(String family, Iterable<String> files) async {
    final loader = FontLoader(family);
    for (final file in files) {
      loader.addFont(
        File(file).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await loader.load();
  }

  final fonts = Directory('assets/fonts').listSync().whereType<File>();
  await load(
    AppTheme.fontUi,
    fonts.where((f) => f.path.contains('IBMPlexSans')).map((f) => f.path),
  );
  await load(
    AppTheme.fontBrand,
    fonts.where((f) => f.path.contains('Sora')).map((f) => f.path),
  );
  final cache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final lucideTtf = Directory('$cache/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.contains('lucide_icons_flutter-'))
      .map((d) => '${d.path}/assets/lucide.ttf')
      .last;
  await load('packages/lucide_icons_flutter/Lucide', [lucideTtf]);
}

enum _Scene { helper, planner, mine }

ShiftEventDetail _event({required bool canPlan}) => ShiftEventDetail(
  summary: ShiftEventSummary(
    id: 'e1',
    projectId: 'p1',
    title: 'Vereinsfest',
    location: 'Bürgerhaus',
    startsAt: DateTime(2026, 10, 24, 14),
    endsAt: DateTime(2026, 10, 24, 23),
    startsLocal: DateTime(2026, 10, 24, 14),
    endsLocal: DateTime(2026, 10, 24, 23),
    canPlan: canPlan,
    placesRequired: 9,
    placesTaken: 8,
    shiftsUnderstaffed: 1,
  ),
  shifts: [
    sampleShift(
      id: 's1',
      title: 'Kasse',
      assigned: 5,
      required: 5,
      max: 5,
      waitingCount: 3,
      waitingIds: canPlan ? const ['u1', 'u2', 'u3'] : const [],
      start: DateTime(2026, 10, 24, 14),
    ),
    sampleShift(
      id: 's2',
      title: 'Garderobe',
      assigned: 3,
      required: 4,
      max: 4,
      waitingCount: 2,
      myWaitPosition: canPlan ? null : 2,
      myWaitAssignmentId: canPlan ? null : 'w2',
      waitingIds: canPlan ? const ['u4', 'u5'] : const [],
      start: DateTime(2026, 10, 24, 18),
    ),
  ],
  users: const {
    'u1': ShiftUser(name: 'Ann Berg'),
    'u2': ShiftUser(name: 'Dana Ruiz'),
    'u3': ShiftUser(name: 'Kemal Aydın'),
    'u4': ShiftUser(name: 'Lena Vogt'),
    'u5': ShiftUser(name: 'Tom Okafor'),
  },
);

void main() {
  setUpAll(_loadFonts);

  const cases = [
    (width: 320.0, scale: 2.0, dark: false),
    (width: 390.0, scale: 1.0, dark: false),
    (width: 390.0, scale: 1.0, dark: true),
    (width: 1440.0, scale: 1.0, dark: false),
  ];
  for (final scene in _Scene.values) {
    for (final c in cases) {
      final name =
          'shift_waitlist_${scene.name}_${c.width.toInt()}_'
          '${c.dark ? 'dark' : 'light'}_x${c.scale.toInt()}';
      testWidgets(name, (tester) async {
        HydratedBloc.storage = MemoryStorage();
        AppColors.brightness = c.dark ? Brightness.dark : Brightness.light;
        addTearDown(() => AppColors.brightness = Brightness.light);
        tester.view.physicalSize = Size(c.width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final promoted = sampleMine(
          assignmentId: 'p1',
          status: ShiftAssignmentStatus.assigned,
          confirmByLocal: DateTime(2026, 10, 21, 18),
          shift: sampleShift(
            id: 'sp',
            title: 'Getränke',
            mine: true,
            myStatus: ShiftAssignmentStatus.assigned,
            myAssignmentId: 'p1',
            assigned: 2,
            start: DateTime(2026, 10, 22, 10),
          ),
        );
        final later = sampleMine(
          assignmentId: 'a2',
          shift: sampleShift(
            id: 'sl',
            title: 'Abbau',
            mine: true,
            myStatus: ShiftAssignmentStatus.confirmed,
            myAssignmentId: 'a2',
            assigned: 3,
            required: 3,
            start: DateTime(2026, 10, 26, 9),
          ),
        );
        final repo = FakeShiftRepository()
          ..eventDetail = _event(canPlan: scene == _Scene.planner)
          ..next = promoted
          ..mine = (items: [promoted, later], total: 2)
          ..shiftDetail = ShiftDetail(shift: promoted.shift, event: sampleEvent)
          ..waiting = [
            sampleMine(
              assignmentId: 'w1',
              status: ShiftAssignmentStatus.waiting,
              shift: sampleShift(
                id: 'sw',
                title: 'Garderobe',
                assigned: 4,
                required: 4,
                max: 4,
                waitingCount: 3,
                myWaitPosition: 1,
                start: DateTime(2026, 10, 25, 18),
              ),
            ),
          ];
        final snapshot = MyShiftsSnapshotCubit(storageId: 'golden');
        final actions = ShiftActionsCubit(repo);
        final planning = ShiftPlanningCubit(repo);
        addTearDown(snapshot.close);
        addTearDown(actions.close);
        addTearDown(planning.close);
        await tester.pumpWidget(
          RepositoryProvider<ShiftRepository>.value(
            value: repo,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>(create: (_) => FakeAuthBloc()),
                BlocProvider.value(value: snapshot),
                BlocProvider.value(value: actions),
                BlocProvider.value(value: planning),
              ],
              child: RepaintBoundary(
                key: const ValueKey('root'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: const Locale('de'),
                  supportedLocales: I18n.supportedLocales,
                  localizationsDelegates: [
                    I18NextLocalizationDelegate(
                      locales: I18n.supportedLocales,
                      dataSource: FileI18nSource(),
                      options: const I18NextOptions(
                        fallbackNamespaces: ['common'],
                        escapeValue: false,
                      ),
                    ),
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  theme: c.dark ? AppTheme.dark() : AppTheme.light(),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(c.scale),
                      disableAnimations: true,
                    ),
                    child: child!,
                  ),
                  home: Scaffold(
                    backgroundColor: AppColors.canvas,
                    body: switch (scene) {
                      _Scene.mine => MyShiftsPage(
                        now: () => DateTime(2026, 10, 20, 12),
                      ),
                      _ => const ShiftEventScreen(eventId: 'e1'),
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('root')),
          matchesGoldenFile('goldens/$name.png'),
        );
      }, skip: skipGoldensOffMac);
    }
  }
}
