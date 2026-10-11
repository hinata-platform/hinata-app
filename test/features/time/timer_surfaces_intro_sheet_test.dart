import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/time/timer_surfaces_intro_sheet.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import 'fake_timer_surface_gate.dart';

/// "Timer outside the app" (HIN-100): asked once, preset with the suggestion,
/// and nothing shows outside the app before the person said yes.
void main() {
  late TimerSurfacePrefsCubit prefs;
  late FakeTimerSurfaceGate gate;

  setUp(() {
    AppColors.brightness = Brightness.light;
    HydratedBloc.storage = MemoryStorage();
    prefs = TimerSurfacePrefsCubit(storageId: 'surfaces#test');
    gate = FakeTimerSurfaceGate();
  });

  tearDown(() => prefs.close());

  Future<void> pump(WidgetTester tester, SurfacePlatform platform) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TimerSurfacesIntroBody(
            prefs: prefs,
            platform: platform,
            gate: gate,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder switchOf(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(HiveSwitch),
  );

  bool valueOf(WidgetTester tester, String label) =>
      tester.widget<HiveSwitch>(switchOf(label)).value;

  testWidgets('the suggestion is preset: notification and running timer on, '
      'details off', (tester) async {
    await pump(tester, SurfacePlatform.android);

    expect(valueOf(tester, 'account.timerSurfaces.phaseEnd'), isTrue);
    expect(valueOf(tester, 'account.timerSurfaces.running'), isTrue);
    expect(valueOf(tester, 'account.timerSurfaces.details'), isFalse);
    expect(valueOf(tester, 'account.timerSurfaces.lockDetails'), isFalse);
    // Android has no tab title.
    expect(find.text('account.timerSurfaces.titleClock'), findsNothing);
    expect(find.text('time.surface.intro.runningLocked'), findsOneWidget);
    expect(find.text('time.surface.intro.endClosed'), findsOneWidget);
    expect(prefs.state.consented, isFalse);
  });

  testWidgets('"Later" leaves everything off and does not ask again', (
    tester,
  ) async {
    await pump(tester, SurfacePlatform.android);

    await tester.tap(find.text('time.surface.intro.later'));
    await tester.pump();

    expect(prefs.state, const TimerSurfacePrefs(introSeen: true));
    expect(gate.requests, 0);
  });

  testWidgets('no row for what the platform lacks', (tester) async {
    await pump(tester, SurfacePlatform.macos);

    expect(find.text('account.timerSurfaces.phaseEnd'), findsOneWidget);
    expect(find.text('account.timerSurfaces.running'), findsNothing);
    expect(find.text('account.timerSurfaces.details'), findsNothing);
    expect(find.text('account.timerSurfaces.lockDetails'), findsNothing);
    expect(find.text('account.timerSurfaces.titleClock'), findsNothing);
  });

  testWidgets('iOS offers the Live Activity and says where it shows', (
    tester,
  ) async {
    await pump(tester, SurfacePlatform.ios);

    expect(valueOf(tester, 'account.timerSurfaces.runningIos'), isTrue);
    expect(find.text('time.surface.intro.runningIos'), findsOneWidget);
    expect(find.text('account.timerSurfaces.details'), findsNothing);
  });

  testWidgets('the web offers the tab title, preset off, and says the '
      'notification only comes while the app runs', (tester) async {
    await pump(tester, SurfacePlatform.web);

    expect(valueOf(tester, 'account.timerSurfaces.titleClock'), isFalse);
    expect(find.text('time.surface.intro.endBackground'), findsOneWidget);
  });

  testWidgets('without the notification nothing is asked of the system', (
    tester,
  ) async {
    await pump(tester, SurfacePlatform.ios);

    await tester.tap(switchOf('account.timerSurfaces.phaseEnd'));
    await tester.pump();
    await tester.tap(find.text('time.surface.intro.switchOn'));
    await tester.pump();

    expect(gate.requests, 0);
    expect(prefs.state.consented, isTrue);
    expect(prefs.state.phaseEndNotification, isFalse);
  });

  testWidgets('"Switch on" asks once and keeps the choices', (tester) async {
    await pump(tester, SurfacePlatform.android);

    await tester.tap(find.text('time.surface.intro.switchOn'));
    await tester.pump();

    expect(gate.requests, 1);
    expect(prefs.state, TimerSurfacePrefs.suggested);
  });

  testWidgets('a refused permission still consents, with notifications off', (
    tester,
  ) async {
    gate.grants = false;
    await pump(tester, SurfacePlatform.android);

    await tester.tap(find.text('time.surface.intro.switchOn'));
    await tester.pump();

    expect(prefs.state.consented, isTrue);
    expect(prefs.state.introSeen, isTrue);
    expect(prefs.state.phaseEndNotification, isFalse);
    expect(prefs.state.runningSurface, isFalse);
    expect(find.text('time.surface.intro.denied'), findsOneWidget);
    // Past the toast, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 6));
  });
}
