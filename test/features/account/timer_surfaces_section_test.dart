import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_clear_signal.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/account/timer_surfaces_section.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../time/fake_timer_surface_gate.dart';

/// Settings → Time tracking → "Timer outside the app" (HIN-100): one row
/// until the person said yes, then one switch per thing the platform has.
void main() {
  late TimerSurfacePrefsCubit prefs;
  late FakeTimerSurfaceGate gate;
  late TimerSurfaceClearSignal clear;

  setUp(() {
    AppColors.brightness = Brightness.light;
    HydratedBloc.storage = MemoryStorage();
    prefs = TimerSurfacePrefsCubit(storageId: 'surfaces#test');
    gate = FakeTimerSurfaceGate();
    clear = TimerSurfaceClearSignal();
  });

  tearDown(() async {
    await prefs.close();
    clear.dispose();
  });

  Future<void> pump(WidgetTester tester, SurfacePlatform platform) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 1600)),
        child: MaterialApp(
          home: Scaffold(
            body: RepositoryProvider<TimerSurfaceClearSignal>.value(
              value: clear,
              child: BlocProvider<TimerSurfacePrefsCubit>.value(
                value: prefs,
                child: SingleChildScrollView(
                  child: TimerSurfacesSection(platform: platform, gate: gate),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // A second frame for the answers the fake gate gives asynchronously.
    await tester.pump();
    await tester.pump();
  }

  Finder switchOf(String label) => find.descendant(
    of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
    matching: find.byType(HiveSwitch),
  );

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
  }

  testWidgets('before the person said yes there is only the set-up row', (
    tester,
  ) async {
    await pump(tester, SurfacePlatform.android);

    expect(find.text('account.timerSurfaces.off'), findsOneWidget);
    expect(find.text('account.timerSurfaces.setUp'), findsOneWidget);
    expect(find.byType(HiveSwitch), findsNothing);
    expect(find.text('account.timerSurfaces.clear'), findsNothing);
  });

  testWidgets('on Android: every switch, and the exact time below the '
      'notification', (tester) async {
    prefs.consent(TimerSurfacePrefs.suggested);
    await pump(tester, SurfacePlatform.android);

    expect(find.text('account.timerSurfaces.phaseEnd'), findsOneWidget);
    expect(find.text('account.timerSurfaces.exact'), findsOneWidget);
    // Not allowed yet: the row offers to ask (its hint folds beside the button).
    expect(find.text('account.timerSurfaces.exactAllow'), findsOneWidget);
    expect(find.text('account.timerSurfaces.running'), findsOneWidget);
    expect(find.text('account.timerSurfaces.details'), findsOneWidget);
    expect(find.text('account.timerSurfaces.lockDetails'), findsOneWidget);
    expect(find.text('account.timerSurfaces.titleClock'), findsNothing);
    expect(find.text('account.timerSurfaces.clear'), findsOneWidget);
    expect(find.text('account.timerSurfaces.turnOff'), findsOneWidget);
  });

  testWidgets('the exact time asks the system and reads the answer again', (
    tester,
  ) async {
    prefs.consent(TimerSurfacePrefs.suggested);
    await pump(tester, SurfacePlatform.android);

    gate.exact = true;
    await tapVisible(tester, find.text('account.timerSurfaces.exactAllow'));
    await tester.pump();

    expect(gate.exactRequests, 1);
    expect(
      find.text('account.timerSurfaces.exactOn', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('account.timerSurfaces.exactAllow'), findsNothing);
  });

  testWidgets('on iOS only the notification', (tester) async {
    prefs.consent(TimerSurfacePrefs.suggested);
    await pump(tester, SurfacePlatform.ios);

    expect(find.byType(HiveSwitch), findsOneWidget);
    expect(find.text('account.timerSurfaces.phaseEnd'), findsOneWidget);
    expect(find.text('account.timerSurfaces.exact'), findsNothing);
    expect(find.text('account.timerSurfaces.running'), findsNothing);
  });

  testWidgets('on the web the tab title', (tester) async {
    prefs.consent(TimerSurfacePrefs.suggested);
    await pump(tester, SurfacePlatform.web);

    expect(find.text('account.timerSurfaces.titleClock'), findsOneWidget);
    expect(find.text('account.timerSurfaces.details'), findsNothing);
    expect(find.text('account.timerSurfaces.lockDetails'), findsNothing);

    await tapVisible(tester, switchOf('account.timerSurfaces.titleClock'));

    expect(prefs.state.titleClock, isTrue);
    expect(gate.requests, 0);
  });

  testWidgets('a switch writes to the cubit', (tester) async {
    prefs.consent(TimerSurfacePrefs.suggested);
    await pump(tester, SurfacePlatform.android);

    await tapVisible(tester, switchOf('account.timerSurfaces.details'));
    expect(prefs.state.surfaceDetails, isTrue);

    // The running timer off takes its details with it.
    await tapVisible(tester, switchOf('account.timerSurfaces.running'));
    expect(prefs.state.runningSurface, isFalse);
    expect(prefs.state.surfaceDetails, isFalse);
    expect(find.text('account.timerSurfaces.details'), findsNothing);
  });

  testWidgets('a refused permission leaves the switch off and says why', (
    tester,
  ) async {
    prefs.consent(const TimerSurfacePrefs());
    gate.grants = false;
    await pump(tester, SurfacePlatform.android);

    await tapVisible(tester, switchOf('account.timerSurfaces.phaseEnd'));
    await tester.pump();

    expect(gate.requests, 1);
    expect(prefs.state.phaseEndNotification, isFalse);
    expect(find.text('account.timerSurfaces.denied'), findsOneWidget);
  });

  testWidgets('"Delete now" asks the host to clear every surface', (
    tester,
  ) async {
    var cleared = 0;
    clear.addListener(() => cleared++);
    prefs.consent(TimerSurfacePrefs.suggested);
    await pump(tester, SurfacePlatform.android);

    await tapVisible(tester, find.text('account.timerSurfaces.clearButton'));

    expect(cleared, 1);
    expect(find.text('account.timerSurfaces.cleared'), findsOneWidget);
    // Past the toast, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('"Switch off" turns everything off and offers set-up again', (
    tester,
  ) async {
    prefs.consent(TimerSurfacePrefs.suggested);
    await pump(tester, SurfacePlatform.android);

    await tapVisible(tester, find.text('account.timerSurfaces.turnOffButton'));

    expect(prefs.state, const TimerSurfacePrefs(introSeen: true));
    expect(find.text('account.timerSurfaces.setUp'), findsOneWidget);
  });

  testWidgets('on a Mac: menu bar, keep running, shortcuts, no permission', (
    tester,
  ) async {
    prefs.consent(TimerSurfacePrefs.suggestedOn(SurfacePlatform.macos));
    await pump(tester, SurfacePlatform.macos);

    expect(find.text('account.timerSurfaces.runningMenuBar'), findsOneWidget);
    expect(find.text('account.timerSurfaces.detailsMenu'), findsOneWidget);
    expect(find.text('account.timerSurfaces.keepRunning'), findsOneWidget);
    expect(find.text('account.timerSurfaces.hotkeys'), findsOneWidget);
    // Off by default: no combinations on screen yet.
    expect(find.text('account.timerSurfaces.hotkeyToggle'), findsNothing);

    await tapVisible(tester, switchOf('account.timerSurfaces.hotkeys'));
    await tester.pump();

    expect(prefs.state.globalHotkeys, isTrue);
    expect(
      prefs.state.toggleHotkey,
      TimerSurfacePrefs.defaultToggleHotkey(SurfacePlatform.macos),
    );
    expect(find.text('account.timerSurfaces.hotkeyToggle'), findsOneWidget);
    expect(find.text('⌃⌥⌘S'), findsOneWidget);
    expect(find.text('⌃⌥⌘F'), findsOneWidget);
    // The menu bar is no notification: nothing was asked of the system.
    expect(gate.requests, 0);
  });

  testWidgets('switching the menu bar off also ends keep running', (
    tester,
  ) async {
    prefs.consent(TimerSurfacePrefs.suggestedOn(SurfacePlatform.macos));
    await pump(tester, SurfacePlatform.macos);
    expect(prefs.state.keepInTray, isTrue);

    await tapVisible(tester, switchOf('account.timerSurfaces.runningMenuBar'));

    expect(prefs.state.runningSurface, isFalse);
    expect(prefs.state.keepInTray, isFalse);
    expect(find.text('account.timerSurfaces.keepRunning'), findsNothing);
  });
}
