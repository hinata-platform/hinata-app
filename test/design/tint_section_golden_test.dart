// Settings → Darstellung → Anpassen (HIN-150) as the person meets it: the
// tinted style light and dark, at text scale 1.0 and 2.0, on a phone and wide,
// and the standard style once.
// Widget tests render raw i18n keys; the goldens are about layout and colour.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/theme_cubit.dart';
import 'package:hinata/core/blocs/tint_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/theme/tint_palette.dart';
import 'package:hinata/features/account/tint_section.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../support/timer_surface_fakes.dart';
import '../support/tint_fakes.dart';

void main() {
  const tinted = TintPreferences(style: TintStyle.tinted, hue: 200, level: 70);

  final cases = [
    for (final dark in const [false, true])
      for (final scale in const [1.0, 2.0])
        for (final width in const [390.0, 1100.0])
          (dark: dark, scale: scale, width: width, prefs: tinted),
    (dark: false, scale: 1.0, width: 390.0, prefs: TintPreferences.standard),
  ];
  for (final c in cases) {
    {
      {
        final dark = c.dark;
        final scale = c.scale;
        final width = c.width;
        final mode = dark ? 'dark' : 'light';
        final style = c.prefs.style == TintStyle.tinted ? '' : '_standard';
        final name =
            'tint_section_${mode}_x${scale.toInt()}_${width.toInt()}$style';
        testWidgets(name, (tester) async {
          HydratedBloc.storage = MemoryStorage();
          AppColors.brightness = dark ? Brightness.dark : Brightness.light;
          addTearDown(() => AppColors.brightness = Brightness.light);
          final tint = TintCubit(FakeTintAccountRepository());
          addTearDown(tint.close);
          tint.adopt(c.prefs);
          AppColors.palette = tint.state.palette;
          addTearDown(() => AppColors.palette = TintPalette.standard);
          final theme = ThemeCubit();
          addTearDown(theme.close);
          tester.view.physicalSize = Size(width, 1400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: Size(width, 1400),
                textScaler: TextScaler.linear(scale),
              ),
              child: MaterialApp(
                theme: dark
                    ? AppTheme.dark(palette: tint.state.palette)
                    : AppTheme.light(palette: tint.state.palette),
                home: Scaffold(
                  body: MultiBlocProvider(
                    providers: [
                      BlocProvider<TintCubit>.value(value: tint),
                      BlocProvider<ThemeCubit>.value(value: theme),
                    ],
                    child: SingleChildScrollView(
                      child: RepaintBoundary(
                        key: const ValueKey('section'),
                        child: Container(
                          color: AppColors.canvas,
                          padding: const EdgeInsets.all(16),
                          child: const TintSection(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('section')),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}
