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
    expect(
      capabilitiesForPlatform(SurfacePlatform.ios).runningSurface,
      isFalse,
    );
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
}
