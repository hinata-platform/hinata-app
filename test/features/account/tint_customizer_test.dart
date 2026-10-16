import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/theme_cubit.dart';
import 'package:hinata/core/blocs/tint_cubit.dart';
import 'package:hinata/core/models/account_models.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/theme/app_theme.dart';
import 'package:hinata/core/widgets/hue_slider.dart';
import 'package:hinata/features/account/tint_customizer.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../support/timer_surface_fakes.dart';
import '../../support/tint_fakes.dart';

/// Settings → Darstellung → Anpassen (HIN-150): a row that opens the
/// Customize panel, a glass popover on wide screens and a glass sheet on
/// compact ones; in it two style tiles, two sliders that appear with
/// "Eingefärbt", and Light / Dark / Automatic. Widget tests render raw i18n
/// keys.
void main() {
  late MemoryStorage storage;
  late FakeTintAccountRepository account;
  late TintCubit tint;
  late ThemeCubit theme;

  setUp(() {
    AppColors.brightness = Brightness.light;
    storage = MemoryStorage();
    HydratedBloc.storage = storage;
    account = FakeTintAccountRepository();
    tint = TintCubit(account);
    theme = ThemeCubit();
  });

  tearDown(() async {
    await tint.close();
    await theme.close();
  });

  Future<void> pump(WidgetTester tester, {double width = 1200}) =>
      tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(size: Size(width, 900)),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: MultiBlocProvider(
                providers: [
                  BlocProvider<TintCubit>.value(value: tint),
                  BlocProvider<ThemeCubit>.value(value: theme),
                ],
                child: const SingleChildScrollView(
                  child: TintCustomizerPanel(),
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('the standard style hides the sliders', (tester) async {
    await pump(tester);
    expect(find.text('account.tint.title'), findsOneWidget);
    expect(find.text('account.tint.styleDefault'), findsOneWidget);
    expect(find.text('account.tint.styleTinted'), findsOneWidget);
    expect(find.byType(HueSlider), findsNothing);
    expect(find.byType(LevelSlider), findsNothing);
    expect(find.text('account.tint.modeAuto'), findsOneWidget);
  });

  testWidgets('the tinted style shows hue and level', (tester) async {
    await pump(tester);
    await tester.tap(find.text('account.tint.styleTinted'));
    await tester.pump();
    expect(find.byType(HueSlider), findsOneWidget);
    expect(find.byType(LevelSlider), findsOneWidget);
    // Each slider is named for a reader (4.1.2); the panel shows no caption.
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('account.tint.hue'), findsOneWidget);
    expect(find.bySemanticsLabel('account.tint.level'), findsOneWidget);
    handle.dispose();
    expect(tint.state.preferences.style, TintStyle.tinted);
    expect(account.saved.last.style, TintStyle.tinted);
  });

  testWidgets('a drag previews, the release commits once', (tester) async {
    await tint.commit(
      const TintPreferences(style: TintStyle.tinted, hue: 79, level: 100),
    );
    account.saved.clear();
    await pump(tester);
    final slider = find.descendant(
      of: find.byType(HueSlider),
      matching: find.byType(Slider),
    );
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(account.saved, isEmpty);
    expect(tint.previewPalette.value, isNot(same(tint.state.palette)));
    await gesture.up();
    await tester.pump();
    expect(account.saved, hasLength(1));
    expect(tint.state.preferences.hue, isNot(79));
  });

  testWidgets(
    'a held arrow key previews at once and commits once after the settle',
    (tester) async {
      await tint.commit(
        const TintPreferences(style: TintStyle.tinted, hue: 79, level: 100),
      );
      account.saved.clear();
      await pump(tester);
      // Tab past the two tiles to the first slider; a tap would move the
      // thumb first.
      final hue = find.descendant(
        of: find.byType(HueSlider),
        matching: find.byType(Focus),
      );
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus;
        if (tester.widgetList<Focus>(hue).any((f) => f.focusNode == focused)) {
          break;
        }
      }
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(account.saved, isEmpty);
      // Nothing app-wide until the settle: the preview moved, the state did not.
      expect(tint.state.preferences.hue, 79);
      expect(tint.previewPalette.value, isNot(same(tint.state.palette)));
      await tester.pump(TintCubit.settle + const Duration(milliseconds: 50));
      expect(account.saved, hasLength(1));
      expect(account.saved.single.hue, greaterThan(79));
      expect(tint.state.preferences.hue, greaterThan(79));
    },
  );

  testWidgets('Light, Dark and Automatic drive the theme cubit', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('settings.themeDark'));
    await tester.pump();
    expect(theme.state, ThemeMode.dark);
    await tester.tap(find.text('account.tint.modeAuto'));
    await tester.pump();
    expect(theme.state, ThemeMode.system);
  });

  Future<void> pumpRow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The cubits sit above the app, as in app.dart: the panel opens on the
    // root navigator and reads them from there.
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<TintCubit>.value(value: tint),
          BlocProvider<ThemeCubit>.value(value: theme),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: Center(child: TintCustomizeRow())),
        ),
      ),
    );
  }

  testWidgets('the row says what is set and opens a popover when wide', (
    tester,
  ) async {
    await tint.commit(
      const TintPreferences(style: TintStyle.tinted, hue: 155, level: 100),
    );
    await pumpRow(tester, const Size(1280, 900));
    expect(find.textContaining('account.tint.styleTinted'), findsOneWidget);
    expect(find.textContaining('account.tint.modeAuto'), findsOneWidget);
    expect(find.byType(TintCustomizerPanel), findsNothing);
    await tester.tap(find.text('account.tint.title'));
    await tester.pumpAndSettle();
    expect(find.byType(TintCustomizerPanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(HueSlider), findsOneWidget);
  });

  testWidgets('the row opens a bottom sheet on a phone', (tester) async {
    await pumpRow(tester, const Size(390, 844));
    await tester.tap(find.text('account.tint.title'));
    await tester.pumpAndSettle();
    expect(find.byType(TintCustomizerPanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('does not overflow at text scale 2 on a phone', (tester) async {
    await tint.commit(
      const TintPreferences(style: TintStyle.tinted, hue: 200, level: 30),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: MultiBlocProvider(
              providers: [
                BlocProvider<TintCubit>.value(value: tint),
                BlocProvider<ThemeCubit>.value(value: theme),
              ],
              child: const SingleChildScrollView(child: TintCustomizerPanel()),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(LevelSlider), findsOneWidget);
  });
}
