// Design preview of the team absence calendar (HIN-118), rendered as goldens.
//
// Not under test/: goldens render differently on the CI's Linux runners, and a
// preview is for looking at, not a gate. The PNGs go to the workspace review
// folder, never into the repository.
//
//   fvm flutter test design_preview/team_absence_preview_test.dart --update-goldens

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/models/team_absence_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/features/absences/team_absence_agenda.dart';
import 'package:hinata/features/absences/team_absence_calendar.dart';

final _today = DateTime.now();
final _from = DateTime(_today.year, _today.month);
final _to = DateTime(_today.year, _today.month + 1, 0);

DateTime _d(int day) => DateTime(_from.year, _from.month, day);

final _rows = [
  TeamAbsenceRow(
    userId: 'a',
    name: 'Amira Haddad',
    entries: [
      TeamAbsenceEntry(
        from: _d(3),
        to: _d(7),
        typeId: 'v',
        typeSystemKey: 'vacation',
        icon: 'palmtree',
        hue: 150,
      ),
    ],
  ),
  TeamAbsenceRow(
    userId: 'b',
    name: 'Ben Krüger',
    entries: [TeamAbsenceEntry(from: _d(10), to: _d(11))],
  ),
  TeamAbsenceRow(
    userId: 'c',
    name: 'Chiara Rossi',
    holidays: [TeamAbsenceHoliday(date: _d(14), name: 'Feiertag')],
    entries: [
      TeamAbsenceEntry(
        from: _d(15),
        to: _d(19),
        requested: true,
        typeId: 'v',
        typeSystemKey: 'vacation',
        icon: 'palmtree',
        hue: 150,
      ),
    ],
  ),
  TeamAbsenceRow(
    userId: 'd',
    name: 'Dmitri Volkov',
    entries: [
      TeamAbsenceEntry(
        from: _d(8),
        to: _d(9),
        typeId: 't',
        typeName: 'Fortbildung',
        icon: 'graduation-cap',
        hue: 260,
      ),
      TeamAbsenceEntry(from: _d(22), to: _d(22), halfDay: true),
    ],
  ),
  const TeamAbsenceRow(userId: 'e', name: 'Elif Demir'),
];

final _band = CapacityBand(
  resolution: CapacityResolution.day,
  people: 5,
  buckets: [
    for (var day = _from; !day.isAfter(_to); day = day.add(const Duration(days: 1)))
      CapacityBucket(
        from: day,
        to: day,
        scheduledMinutes: day.weekday >= 6 ? 0 : 5 * 480,
        capacityMinutes: day.weekday >= 6
            ? 0
            : 5 * 480 -
                  (_rows.where((row) => row.entries.any((e) => !e.requested && e.covers(day))).length * 480),
        away: _rows.where((row) => row.entries.any((e) => !e.requested && e.covers(day))).length,
        requested: _rows.where((row) => row.entries.any((e) => e.requested && e.covers(day))).length,
      ),
  ],
);

const viewports = {'phone-390': Size(390, 700), 'desktop-1280': Size(1280, 640)};

Future<void> _loadFonts() async {
  for (final (family, files) in const [
    ('IBMPlexSans', ['IBMPlexSans-Regular.ttf', 'IBMPlexSans-SemiBold.ttf', 'IBMPlexSans-Bold.ttf']),
    ('Sora', ['Sora-Variable.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final asset = File('assets/fonts/$file');
      if (asset.existsSync()) {
        loader.addFont(Future.value(ByteData.view(asset.readAsBytesSync().buffer)));
      }
    }
    await loader.load();
  }
  // Icons: a package font registers under the package's name.
  final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
    ..addFont(rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'));
  await lucide.load();
}

void main() {
  setUpAll(_loadFonts);

  for (final viewport in viewports.entries) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        final name = 'team_${viewport.key}_${brightness.name}_ts${scale.toStringAsFixed(1)}';
        testWidgets(name, (tester) async {
          tester.view
            ..physicalSize = viewport.value
            ..devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          AppColors.brightness = brightness;
          addTearDown(() => AppColors.brightness = Brightness.light);

          await tester.runAsync(() async {
            await tester.pumpWidget(
              MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('de'),
                supportedLocales: I18n.supportedLocales,
                localizationsDelegates: I18n.delegates(),
                theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  backgroundColor: AppColors.canvas,
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (viewport.value.width < 600)
                          Expanded(
                            child: TeamAbsenceAgenda(from: _from, to: _to, rows: _rows, capacity: _band),
                          )
                        else ...[
                          Flexible(
                            child: TeamAbsenceBand(from: _from, to: _to, rows: _rows, capacity: _band),
                          ),
                          const SizedBox(height: 10),
                          const TeamAbsenceLegend(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
            await Future<void>.delayed(const Duration(milliseconds: 300));
          });
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('../../hin-118-review/mockup/$name.png'),
          );
        });
      }
    }
  }
}
