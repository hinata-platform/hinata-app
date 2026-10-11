import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/timer_surfaces/adapters/global_hotkeys_surface.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_state.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

import 'fake_host.dart';

class _FakeBinder implements HotkeyBinder {
  final bound = <String, HotKey>{};
  final presses = StreamController<HotKeyEvent>.broadcast();
  HotKeyResult answer = HotKeyResult.bound;

  @override
  Future<HotKeyResult> register(String id, HotKey hotKey) async {
    if (answer == HotKeyResult.bound) bound[id] = hotKey;
    return answer;
  }

  @override
  Future<void> unregister(String id) async => bound.remove(id);

  @override
  Future<void> unregisterAll() async => bound.clear();

  @override
  Stream<HotKeyEvent> get events => presses.stream;
}

void main() {
  late _FakeBinder binder;
  late FakeHost host;
  late GlobalHotkeysSurface surface;
  final toggle = TimerSurfacePrefs.defaultToggleHotkey(SurfacePlatform.macos);
  final focus = TimerSurfacePrefs.defaultFocusHotkey(SurfacePlatform.macos);

  setUp(() async {
    binder = _FakeBinder();
    host = FakeHost();
    surface = GlobalHotkeysSurface(SurfacePlatform.macos, binder: binder);
    await surface.init(host);
    GlobalHotkeysSurface.selfTest.value = false;
  });

  tearDown(() => surface.clear());

  test('binds nothing while switched off', () async {
    await surface.apply(const TimerSurfaceState(running: false));
    expect(binder.bound, isEmpty);
    expect(GlobalHotkeysSurface.results.value, isEmpty);
  });

  test('binds both and reports what the system said', () async {
    await surface.apply(
      TimerSurfaceState(
        running: false,
        toggleHotkey: toggle,
        focusHotkey: focus,
      ),
    );
    expect(binder.bound.values, [toggle, focus]);
    expect(GlobalHotkeysSurface.results.value, {
      GlobalHotkeysSurface.toggleId: HotKeyResult.bound,
      GlobalHotkeysSurface.focusId: HotKeyResult.bound,
    });
  });

  test('a conflict is reported, not swallowed', () async {
    binder.answer = HotKeyResult.conflict;
    await surface.apply(
      TimerSurfaceState(running: false, toggleHotkey: toggle),
    );
    expect(
      GlobalHotkeysSurface.results.value[GlobalHotkeysSurface.toggleId],
      HotKeyResult.conflict,
    );
  });

  test('presses start, stop and open the focus view', () async {
    await surface.apply(
      TimerSurfaceState(
        running: false,
        toggleHotkey: toggle,
        focusHotkey: focus,
      ),
    );
    binder.presses.add(const HotKeyEvent(GlobalHotkeysSurface.toggleId));
    await pumpEventQueue();
    await surface.apply(
      TimerSurfaceState(
        running: true,
        toggleHotkey: toggle,
        focusHotkey: focus,
      ),
    );
    binder.presses.add(const HotKeyEvent(GlobalHotkeysSurface.toggleId));
    binder.presses.add(const HotKeyEvent(GlobalHotkeysSurface.focusId));
    await pumpEventQueue();
    expect(host.calls, ['start', 'end', 'show', 'focus']);
  });

  test('the settings check only counts a press', () async {
    await surface.apply(TimerSurfaceState(running: true, toggleHotkey: toggle));
    GlobalHotkeysSurface.selfTest.value = true;
    final before = GlobalHotkeysSurface.lastPress.value;
    binder.presses.add(const HotKeyEvent(GlobalHotkeysSurface.toggleId));
    await pumpEventQueue();
    expect(host.calls, isEmpty);
    expect(GlobalHotkeysSurface.lastPress.value, isNot(before));
  });

  test('switching off releases everything', () async {
    await surface.apply(
      TimerSurfaceState(running: false, toggleHotkey: toggle),
    );
    await surface.apply(const TimerSurfaceState(running: false));
    expect(binder.bound, isEmpty);
    expect(GlobalHotkeysSurface.results.value, isEmpty);
  });
}
