// The shift calendar of HIN-160 as a planner meets it: one week with an own
// shift that is still short (check and warning), an open one (warning and
// "fehlen 2") and a staffed one (words only), wide and on a phone, light and
// dark, text scale 1.0 and 2.0 on the phone. Real fonts and German strings.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/repositories/shift_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/bloc/shift_calendar_cubit.dart';
import 'package:hinata/features/shifts/view/shift_calendar_view.dart';
import 'package:i18next/i18next.dart';

import '../features/shifts/shift_fakes.dart';
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
    AppTheme.fontMono,
    fonts.where((f) => f.path.contains('IBMPlexMono')).map((f) => f.path),
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

void main() {
  setUpAll(_loadFonts);

  const cases = [
    (width: 1180.0, scale: 1.0),
    (width: 390.0, scale: 1.0),
    (width: 390.0, scale: 2.0),
  ];
  for (final c in cases) {
    for (final dark in const [false, true]) {
      final name =
          'shift_week_${c.width.toInt()}_${dark ? 'dark' : 'light'}_x${c.scale.toInt()}';
      testWidgets(name, (tester) async {
        AppColors.brightness = dark ? Brightness.dark : Brightness.light;
        addTearDown(() => AppColors.brightness = Brightness.light);
        tester.view.physicalSize = Size(c.width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repo = FakeShiftRepository()
          ..calendarMonths[202610] = ShiftCalendar(
            shifts: [
              sampleShift(
                id: 'mine',
                title: 'Kasse',
                assigned: 1,
                required: 2,
                mine: true,
                start: DateTime(2026, 10, 24, 10),
              ),
              sampleShift(
                id: 'open',
                title: 'Aufbau',
                assigned: 0,
                required: 2,
                start: DateTime(2026, 10, 22, 10),
              ),
              sampleShift(
                id: 'fine',
                title: 'Empfang',
                assigned: 2,
                required: 2,
                start: DateTime(2026, 10, 21, 13),
              ),
              sampleShift(
                id: 'mine2',
                title: 'Standdienst',
                assigned: 3,
                required: 3,
                mine: true,
                start: DateTime(2026, 10, 24, 14),
              ),
            ],
            events: const {'e1': sampleEvent},
          );
        final cubit = ShiftCalendarCubit(repo, focused: DateTime(2026, 10, 24));
        addTearDown(cubit.close);
        await cubit.start();
        final actions = ShiftActionsCubit(repo);
        addTearDown(actions.close);
        await tester.pumpWidget(
          RepositoryProvider<ShiftRepository>.value(
            value: repo,
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: actions),
                BlocProvider.value(value: cubit),
              ],
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
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(c.scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: Scaffold(
                  backgroundColor: AppColors.canvas,
                  body: RepaintBoundary(
                    key: const ValueKey('calendar'),
                    child: ColoredBox(
                      color: AppColors.canvas,
                      child: ShiftCalendarView(
                        now: DateTime(2026, 10, 20, 9),
                        deviceZone: 'Europe/Berlin',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byKey(const ValueKey('calendar')),
          matchesGoldenFile('goldens/$name.png'),
        );
      }, skip: skipGoldensOffMac);
    }
  }
}
