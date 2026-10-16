import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/theme_cubit.dart';
import 'package:hinata/core/blocs/tint_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/tint_palette.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_colors_refresh.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../support/timer_surface_fakes.dart';
import '../../support/tint_fakes.dart';

/// A card that reads its colour through the AppColors getters and depends on
/// nothing: const, so a rebuild above it hands back the same instance and
/// Flutter skips it. The settings card that stayed white in dark mode.
class _Card extends StatelessWidget {
  const _Card();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surface,
    child: const SizedBox.square(dimension: 10),
  );
}

void main() {
  tearDown(() => AppColors.brightness = Brightness.light);

  testWidgets('a const subtree takes the new colours when the mode switches', (
    tester,
  ) async {
    HydratedBloc.storage = MemoryStorage();
    final theme = ThemeCubit();
    final tint = TintCubit(FakeTintAccountRepository());
    addTearDown(theme.close);
    addTearDown(tint.close);
    theme.setMode(ThemeMode.light);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>.value(value: theme),
          BlocProvider<TintCubit>.value(value: tint),
        ],
        child: AppColorsRefresh(
          child: BlocBuilder<ThemeCubit, ThemeMode>(
            builder: (context, mode) => MaterialApp(
              themeMode: mode,
              builder: (context, child) {
                AppColors.brightness = mode == ThemeMode.dark
                    ? Brightness.dark
                    : Brightness.light;
                return child!;
              },
              home: const _Card(),
            ),
          ),
        ),
      ),
    );
    Color painted() =>
        tester.widget<ColoredBox>(find.byType(ColoredBox).last).color;
    expect(painted(), AppColors.surfaceLight);

    theme.setMode(ThemeMode.dark);
    await tester.pump();
    expect(painted(), AppColors.surfaceDark);
  });

  testWidgets('a const subtree takes the new tint when the tint changes', (
    tester,
  ) async {
    HydratedBloc.storage = MemoryStorage();
    final theme = ThemeCubit();
    final tint = TintCubit(FakeTintAccountRepository());
    addTearDown(theme.close);
    addTearDown(tint.close);
    addTearDown(() => AppColors.palette = TintPalette.standard);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>.value(value: theme),
          BlocProvider<TintCubit>.value(value: tint),
        ],
        child: AppColorsRefresh(
          child: BlocBuilder<TintCubit, TintState>(
            builder: (context, state) {
              AppColors.palette = state.palette;
              return const MaterialApp(home: _Accent());
            },
          ),
        ),
      ),
    );
    Color painted() =>
        tester.widget<ColoredBox>(find.byType(ColoredBox).last).color;
    expect(painted(), TintPalette.standard.accent);

    tint.adopt(
      const TintPreferences(style: TintStyle.tinted, hue: 155, level: 100),
    );
    await tester.pump();
    expect(painted(), tint.state.palette.accent);
    expect(painted(), isNot(TintPalette.standard.accent));
  });
}

class _Accent extends StatelessWidget {
  const _Accent();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.accent,
    child: const SizedBox.square(dimension: 10),
  );
}
