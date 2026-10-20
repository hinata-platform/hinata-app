// The helper surfaces of HIN-44 as the reader meets them: the hero card, a
// row in each of the four coverage states (one of them `12 / 15`) and an
// event card, at 390 and 320 points, light and dark, text scale 1.0 and 2.0.
// Real fonts and the German strings, so type, wording and the 200 % layout
// are what is guarded.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/models/shift_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/features/shifts/bloc/shift_actions_cubit.dart';
import 'package:hinata/features/shifts/widgets/next_shift_hero.dart';
import 'package:hinata/features/shifts/widgets/shift_actions.dart';
import 'package:hinata/features/shifts/widgets/shift_event_card.dart';
import 'package:hinata/features/shifts/widgets/shift_row.dart';
import 'package:hinata/features/shifts/widgets/shift_status_badge.dart';
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

  for (final width in const [390.0, 320.0]) {
    for (final dark in const [false, true]) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            'shifts_${width.toInt()}_${dark ? 'dark' : 'light'}_x${scale.toInt()}';
        testWidgets(name, (tester) async {
          AppColors.brightness = dark ? Brightness.dark : Brightness.light;
          addTearDown(() => AppColors.brightness = Brightness.light);
          tester.view.physicalSize = Size(width, 3200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final actions = ShiftActionsCubit(FakeShiftRepository());
          addTearDown(actions.close);
          await tester.pumpWidget(
            BlocProvider.value(
              value: actions,
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
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: const _Sheet(),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('shifts')),
            matchesGoldenFile('goldens/$name.png'),
          );
        }, skip: skipGoldensOffMac);
      }
    }
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet();

  @override
  Widget build(BuildContext context) {
    final next = sampleMine(
      status: ShiftAssignmentStatus.assigned,
      shift: sampleShift(
        id: 'n',
        title: 'Messestand',
        mine: true,
        assigned: 2,
        required: 2,
        start: DateTime(2026, 10, 21, 10),
        assigneeIds: const ['me', 'u1'],
      ),
    );
    final rows = [
      sampleShift(id: 'a', title: 'Aufbau', assigned: 1, required: 2),
      sampleShift(id: 'b', title: 'Kasse', assigned: 3, required: 3, max: 4),
      sampleShift(id: 'c', title: 'Theke', assigned: 5, required: 4),
      sampleShift(id: 'd', title: 'Einlass', assigned: 2, required: 2, max: 2),
      sampleShift(id: 'e', title: 'Messestand', assigned: 12, required: 15),
    ];
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SingleChildScrollView(
        child: RepaintBoundary(
          key: const ValueKey('shifts'),
          child: ColoredBox(
            color: AppColors.canvas,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NextShiftHero(
                    next: next,
                    now: DateTime(2026, 10, 20, 16),
                    detail: ShiftDetail(
                      shift: next.shift,
                      event: sampleEvent,
                      users: const {
                        'me': ShiftUser(name: 'Hinata'),
                        'u1': ShiftUser(name: 'Mei Lin'),
                      },
                    ),
                    selfId: 'me',
                    onAction: (_) {},
                  ),
                  const SizedBox(height: 24),
                  ShiftSectionLabel(
                    'Sa., 24. Okt.',
                    trailing: context.t('shifts.mine.openCount', count: 3),
                  ),
                  for (final shift in rows) ...[
                    ShiftRow(
                      shift: shift,
                      eventTitle: 'Sommerfest',
                      location: 'Festwiese',
                      people: const ['Lena Vogt', 'Tomáš Horák'],
                      stacked: true,
                      trailing: shift.id == 'b'
                          ? const ShiftStatusBadge(
                              status: ShiftAssignmentStatus.confirmed,
                            )
                          : ShiftOfferView(
                              offer: shiftOfferFor(shift),
                              shift: shift,
                              showSecondary: false,
                              onAction: (_) {},
                            ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 14),
                  ShiftEventCard(event: sampleSummary()),
                  const SizedBox(height: 10),
                  ShiftEventCard(
                    event: sampleSummary(
                      id: 'e2',
                      taken: 2,
                      required: 2,
                      understaffed: 0,
                      mine: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
