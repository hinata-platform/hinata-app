// The series surfaces of HIN-161 as a planner meets them: the event editor
// with "Wiederholen" set and the server's words in the head, the scope
// question on an occurrence, and "Eigene Regel" opened. A phone at text scale
// 1.0 and 2.0, light and dark, and a wide window where the rule hangs off its
// field. Real fonts and German strings.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/models/shift_series.dart';
import 'package:hinata/core/repositories/shift_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/features/shifts/bloc/shift_event_editor_cubit.dart';
import 'package:hinata/features/shifts/widgets/series_repeat_picker.dart';
import 'package:hinata/features/shifts/widgets/series_scope_dialog.dart';
import 'package:hinata/features/shifts/widgets/shift_event_editor.dart';
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

enum _Scene { editor, scope, custom }

void main() {
  setUpAll(_loadFonts);

  const cases = [
    (width: 390.0, scale: 1.0, dark: false),
    (width: 390.0, scale: 2.0, dark: true),
    (width: 1180.0, scale: 1.0, dark: false),
  ];
  for (final scene in _Scene.values) {
    for (final c in cases) {
      final name =
          'shift_series_${scene.name}_${c.width.toInt()}_'
          '${c.dark ? 'dark' : 'light'}_x${c.scale.toInt()}';
      testWidgets(name, (tester) async {
        AppColors.brightness = c.dark ? Brightness.dark : Brightness.light;
        addTearDown(() => AppColors.brightness = Brightness.light);
        tester.view.physicalSize = Size(c.width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repo = FakeShiftRepository()
          ..preview = SeriesPreview(
            recurrenceLabel: 'wöchentlich Sa, 6 Mal',
            next: [
              for (var w = 0; w < 5; w++)
                SeriesOccurrence(
                  date: DateTime(2026, 10, 24 + 7 * w),
                  startsAt: DateTime.utc(2026, 10, 24 + 7 * w, 8),
                  endsAt: DateTime.utc(2026, 10, 24 + 7 * w, 16),
                  startsLocal: DateTime(2026, 10, 24 + 7 * w, 10),
                  endsLocal: DateTime(2026, 10, 24 + 7 * w, 18),
                ),
            ],
          );
        final cubit = ShiftEventEditorCubit(
          repo,
          projectId: 'p1',
          projectName: 'Tafel Nordstadt',
          deviceZone: 'Europe/Berlin',
          day: DateTime(2026, 10, 24),
          previewDelay: Duration.zero,
        );
        addTearDown(cubit.close);
        cubit
          ..setTitle('Ausgabe')
          ..setRepeat(
            SeriesRepeat.custom,
            custom: SeriesRule.weekly(DateTime(2026, 10, 24)).withEnd(count: 6),
          );
        await tester.pumpWidget(
          RepositoryProvider<ShiftRepository>.value(
            value: repo,
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
                  body: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: BlocProvider.value(
                        value: cubit,
                        child: Builder(
                          builder: (context) => switch (scene) {
                            _Scene.editor => const SingleChildScrollView(
                              child: ShiftEventEditorBody(projectLocked: true),
                            ),
                            _Scene.scope => TextButton(
                              onPressed: () => askSeriesScope(
                                context,
                                write: SeriesWrite.save,
                                day: DateTime(2026, 10, 31),
                                recurrenceLabel: 'wöchentlich Sa, 6 Mal',
                              ),
                              child: const Text('open'),
                            ),
                            _Scene.custom => TextButton(
                              onPressed: () => showSeriesRepeatPicker(
                                context,
                                anchorRect: const Rect.fromLTWH(
                                  320,
                                  120,
                                  540,
                                  56,
                                ),
                                start: DateTime(2026, 10, 24, 10),
                                current: SeriesRepeat.custom,
                                custom: cubit.state.rule,
                              ),
                              child: const Text('open'),
                            ),
                          },
                        ),
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
        if (scene != _Scene.editor) {
          await tester.tap(find.text('open'));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          if (scene == _Scene.custom) {
            await tester.tap(find.text('Eigene Regel'));
            await tester.pump(const Duration(milliseconds: 100));
          }
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
