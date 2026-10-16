// Settings → Darstellung → Anpassen (HIN-150) as the person meets it: both
// styles, light and dark, at text scale 1.0 and 2.0, on a phone and wide.
// Widget tests render raw i18n keys; the goldens are about layout and colour.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/theme_cubit.dart';
import 'package:hinata/core/blocs/tint_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/repositories/account_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/theme/tint_palette.dart';
import 'package:hinata/features/account/tint_section.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

void main() {
  const tinted = TintPreferences(style: TintStyle.tinted, hue: 200, level: 70);

  for (final dark in const [false, true]) {
    for (final scale in const [1.0, 2.0]) {
      for (final width in const [390.0, 1100.0]) {
        final mode = dark ? 'dark' : 'light';
        final name = 'tint_section_${mode}_x${scale.toInt()}_${width.toInt()}';
        testWidgets(name, (tester) async {
          HydratedBloc.storage = _MemoryStorage();
          AppColors.brightness = dark ? Brightness.dark : Brightness.light;
          addTearDown(() => AppColors.brightness = Brightness.light);
          final tint = TintCubit(_FakeAccountRepository());
          addTearDown(tint.close);
          tint.adopt(tinted);
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

class _MemoryStorage implements Storage {
  final Map<String, dynamic> _values = {};
  @override
  dynamic read(String key) => _values[key];
  @override
  Future<void> write(String key, dynamic value) async => _values[key] = value;
  @override
  Future<void> delete(String key) async => _values.remove(key);
  @override
  Future<void> clear() async => _values.clear();
  @override
  Future<void> close() async {}
}

class _FakeAccountRepository implements AccountRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
