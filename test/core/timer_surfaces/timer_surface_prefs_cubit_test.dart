import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../../support/timer_surface_fakes.dart';

void main() {
  late MemoryStorage storage;

  setUp(() {
    storage = MemoryStorage();
    HydratedBloc.storage = storage;
  });

  test('everything starts off and unconfirmed', () {
    final cubit = TimerSurfacePrefsCubit(storageId: 'surfaces#a');

    expect(cubit.state, const TimerSurfacePrefs());
    expect(cubit.state.consented, isFalse);
  });

  test('the suggestion is notification and running timer, no details', () {
    const suggested = TimerSurfacePrefs.suggested;

    expect(suggested.phaseEndNotification, isTrue);
    expect(suggested.runningSurface, isTrue);
    expect(suggested.surfaceDetails, isFalse);
    expect(suggested.lockScreenDetails, isFalse);
    expect(suggested.titleClock, isFalse);
  });

  test('consenting confirms, later only marks the card as seen', () {
    final cubit = TimerSurfacePrefsCubit(storageId: 'surfaces#a');

    cubit.postpone();
    expect(cubit.state.introSeen, isTrue);
    expect(cubit.state.consented, isFalse);
    expect(cubit.state.phaseEndNotification, isFalse);

    cubit.consent(const TimerSurfacePrefs(phaseEndNotification: true));
    expect(cubit.state.consented, isTrue);
    expect(cubit.state.phaseEndNotification, isTrue);
  });

  test('garbage in the store reads as off', () {
    expect(
      TimerSurfacePrefs.fromJson(const {
        'consented': 'yes',
        'phaseEndNotification': 1,
        'titleClock': null,
      }),
      const TimerSurfacePrefs(),
    );
  });

  test('each identity keeps its own switches', () async {
    final a = TimerSurfacePrefsCubit(storageId: 'surfaces#a')
      ..consent(TimerSurfacePrefs.suggested);
    await Future<void>.delayed(Duration.zero);
    final b = TimerSurfacePrefsCubit(storageId: 'surfaces#b');

    expect(a.state.consented, isTrue);
    expect(b.state.consented, isFalse);
  });

  test('the platform table matches what each platform can do', () {
    expect(
      capabilitiesForPlatform(SurfacePlatform.android).runningSurface,
      isTrue,
    );
    expect(
      capabilitiesForPlatform(SurfacePlatform.android).exactAlarms,
      isTrue,
    );
    // The Live Activity and the widgets (HIN-102), on the lock screen too.
    expect(capabilitiesForPlatform(SurfacePlatform.ios).runningSurface, isTrue);
    expect(capabilitiesForPlatform(SurfacePlatform.ios).lockScreen, isTrue);
    // A Mac has the menu bar for that (HIN-101), not the lock screen.
    expect(capabilitiesForPlatform(SurfacePlatform.macos).lockScreen, isFalse);
    expect(
      capabilitiesForPlatform(SurfacePlatform.linux).schedulesAhead,
      isFalse,
    );
    expect(
      capabilitiesForPlatform(SurfacePlatform.web).schedulesAhead,
      isFalse,
    );
    expect(capabilitiesForPlatform(SurfacePlatform.web).titleClock, isTrue);
    expect(
      capabilitiesForPlatform(SurfacePlatform.windows).schedulesAhead,
      isTrue,
    );
  });

  test('the desktop table: menu bar, close behaviour, shortcuts, taskbar', () {
    final mac = capabilitiesForPlatform(SurfacePlatform.macos);
    final windows = capabilitiesForPlatform(SurfacePlatform.windows);
    final linux = capabilitiesForPlatform(SurfacePlatform.linux);
    expect(
      [mac.trayIcon, mac.keepRunning, mac.globalHotkeys],
      [true, true, true],
    );
    expect(mac.taskbar, isFalse);
    expect(windows.taskbar, isTrue);
    expect(windows.globalHotkeys, isTrue);
    // Linux: the tray best effort, shortcuts with the portal in stage 25.
    expect([linux.trayIcon, linux.globalHotkeys], [true, false]);
  });

  test('a Mac keeps the timer in the menu bar by default, others quit', () {
    expect(
      TimerSurfacePrefs.suggestedOn(SurfacePlatform.macos).keepInTray,
      isTrue,
    );
    expect(
      TimerSurfacePrefs.suggestedOn(SurfacePlatform.windows).keepInTray,
      isFalse,
    );
    expect(
      TimerSurfacePrefs.suggestedOn(SurfacePlatform.macos).globalHotkeys,
      isFalse,
    );
  });

  test('the shortcuts survive the store, broken ones read as none', () {
    final prefs = const TimerSurfacePrefs(consented: true, globalHotkeys: true)
        .copyWith(
          toggleHotkey: TimerSurfacePrefs.defaultToggleHotkey(
            SurfacePlatform.windows,
          ),
        );
    final back = TimerSurfacePrefs.fromJson(
      Map<String, dynamic>.from(prefs.toJson()),
    );
    expect(back, prefs);
    final broken = TimerSurfacePrefs.fromJson(const {
      'globalHotkeys': true,
      'toggleHotkey': {'usage': 0x00070004, 'modifiers': 0},
      'focusHotkey': 'ctrl+f',
    });
    expect(broken.toggleHotkey, isNull);
    expect(broken.focusHotkey, isNull);
  });
}
