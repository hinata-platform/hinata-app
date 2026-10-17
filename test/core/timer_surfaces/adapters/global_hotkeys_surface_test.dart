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
  final triggerChanges = StreamController<Map<String, String>>.broadcast();
  HotKeyResult answer = HotKeyResult.bound;
  final sets = <Map<String, HotKey>>[];
  Map<String, String> descriptions = const {};
  String? applicationId;
  int configured = 0;

  @override
  void identify(String applicationId) => this.applicationId = applicationId;

  @override
  Future<Map<String, HotKeyResult>> registerAll(
    Map<String, HotKey> hotKeys, {
    Map<String, String> descriptions = const {},
  }) async {
    sets.add(hotKeys);
    this.descriptions = descriptions;
    if (answer == HotKeyResult.bound) bound.addAll(hotKeys);
    return {for (final id in hotKeys.keys) id: answer};
  }

  final released = <String>[];

  @override
  Future<void> unregister(String id) async {
    released.add(id);
    bound.remove(id);
  }

  @override
  Future<void> unregisterAll() async {
    released.add('*');
    bound.clear();
  }

  @override
  Stream<HotKeyEvent> get events => presses.stream;

  @override
  Stream<Map<String, String>> get triggers => triggerChanges.stream;

  @override
  Future<bool> configure() async {
    configured++;
    return true;
  }
}

void main() {
  late _FakeBinder binder;
  late FakeHost host;
  late GlobalHotkeysSurface surface;
  late HotkeyStatus status;
  final toggle = TimerSurfacePrefs.defaultToggleHotkey(SurfacePlatform.macos);
  final focus = TimerSurfacePrefs.defaultFocusHotkey(SurfacePlatform.macos);

  setUp(() async {
    binder = _FakeBinder();
    host = FakeHost();
    status = HotkeyStatus();
    surface = GlobalHotkeysSurface(
      SurfacePlatform.macos,
      status: status,
      binder: binder,
    );
    await surface.init(host);
  });

  tearDown(() => surface.clear());

  test('binds nothing while switched off', () async {
    await surface.apply(const TimerSurfaceState(running: false));
    expect(binder.bound, isEmpty);
    expect(status.results.value, isEmpty);
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
    expect(status.results.value, {
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
      status.results.value[GlobalHotkeysSurface.toggleId],
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
    status.selfTest.value = true;
    final before = status.lastPress.value;
    binder.presses.add(const HotKeyEvent(GlobalHotkeysSurface.toggleId));
    await pumpEventQueue();
    expect(host.calls, isEmpty);
    expect(status.lastPress.value, isNot(before));
  });

  test('switching off releases everything', () async {
    await surface.apply(
      TimerSurfaceState(running: false, toggleHotkey: toggle),
    );
    await surface.apply(const TimerSurfaceState(running: false));
    expect(binder.bound, isEmpty);
    expect(status.results.value, isEmpty);
  });

  test('switching both off releases them in one call', () async {
    await surface.apply(
      TimerSurfaceState(
        running: false,
        toggleHotkey: toggle,
        focusHotkey: focus,
      ),
    );
    await surface.apply(const TimerSurfaceState(running: false));
    expect(binder.released, ['*']);
  });

  test('changing one shortcut leaves the other bound', () async {
    await surface.apply(
      TimerSurfaceState(
        running: false,
        toggleHotkey: toggle,
        focusHotkey: focus,
      ),
    );
    final calls = <String>[];
    final spy = _SpyBinder(binder, calls);
    final second = GlobalHotkeysSurface(
      SurfacePlatform.macos,
      status: status,
      binder: spy,
    );
    await second.init(host);
    await second.apply(
      TimerSurfaceState(
        running: false,
        toggleHotkey: toggle,
        focusHotkey: focus,
      ),
    );
    calls.clear();
    final other = HotKey(
      key: PhysicalKeyboardKey.keyG,
      modifiers: focus.modifiers,
    );
    await second.apply(
      TimerSurfaceState(
        running: false,
        toggleHotkey: toggle,
        focusHotkey: other,
      ),
    );
    expect(calls, ['register ${GlobalHotkeysSurface.focusId}']);
  });

  test('binds both in one go, so a desktop that asks asks once', () async {
    await surface.apply(
      TimerSurfaceState(
        running: false,
        toggleHotkey: toggle,
        focusHotkey: focus,
      ),
    );
    expect(binder.sets, hasLength(1));
    expect(binder.sets.single.keys, [
      GlobalHotkeysSurface.toggleId,
      GlobalHotkeysSurface.focusId,
    ]);
  });

  group('where the desktop picks the keys (Linux)', () {
    late GlobalHotkeysSurface linux;
    final linuxToggle = TimerSurfacePrefs.defaultToggleHotkey(
      SurfacePlatform.linux,
    );
    final linuxFocus = TimerSurfacePrefs.defaultFocusHotkey(
      SurfacePlatform.linux,
    );
    TimerSurfaceState bothOn() => TimerSurfaceState(
      running: false,
      toggleHotkey: linuxToggle,
      focusHotkey: linuxFocus,
      texts: const TimerSurfaceTexts(
        appName: '',
        countdownOver: '',
        workOver: '',
        breakOver: '',
        running: '',
        onBreak: '',
        stop: '',
        takeBreak: '',
        resume: '',
        hotkeyToggle: 'Start or stop the timer',
        hotkeyFocus: 'Open the focus view',
      ),
    );

    setUp(() async {
      linux = GlobalHotkeysSurface(
        SurfacePlatform.linux,
        status: status,
        binder: binder,
      );
      await linux.init(host);
    });

    tearDown(() => linux.dispose());

    test('names the app and describes both shortcuts', () async {
      await linux.apply(bothOn());
      expect(binder.applicationId, GlobalHotkeysSurface.linuxApplicationId);
      expect(binder.descriptions, {
        GlobalHotkeysSurface.toggleId: 'Start or stop the timer',
        GlobalHotkeysSurface.focusId: 'Open the focus view',
      });
    });

    test('shows the keys the desktop reports', () async {
      await linux.apply(bothOn());
      binder.triggerChanges.add({GlobalHotkeysSurface.toggleId: 'Ctrl+Alt+T'});
      await pumpEventQueue();
      expect(status.triggers.value, {
        GlobalHotkeysSurface.toggleId: 'Ctrl+Alt+T',
      });
    });

    test('configure opens the desktop settings for a bound set', () async {
      await linux.apply(bothOn());
      expect(await status.configure(), isTrue);
      expect(binder.configured, 1);
      expect(binder.sets, hasLength(1));
    });

    test('configure asks again about a declined set', () async {
      binder.answer = HotKeyResult.declined;
      await linux.apply(bothOn());
      binder.answer = HotKeyResult.bound;
      expect(await status.configure(), isTrue);
      expect(binder.configured, 0);
      expect(binder.sets, hasLength(2));
      expect(status.results.value.values, everyElement(HotKeyResult.bound));
    });
  });

  test('configure does nothing where the app picks the keys', () async {
    expect(await status.configure(), isFalse);
  });

  test('a combination people type is never bound', () async {
    const shiftS = HotKey(
      key: PhysicalKeyboardKey.keyS,
      modifiers: {HotKeyModifier.shift},
    );
    await surface.apply(
      const TimerSurfaceState(running: false, toggleHotkey: shiftS),
    );
    expect(binder.bound, isEmpty);
    expect(
      status.results.value[GlobalHotkeysSurface.toggleId],
      HotKeyResult.unsupported,
    );
  });
}

class _SpyBinder implements HotkeyBinder {
  _SpyBinder(this.inner, this.calls);

  final HotkeyBinder inner;
  final List<String> calls;

  @override
  void identify(String applicationId) => inner.identify(applicationId);

  @override
  Future<Map<String, HotKeyResult>> registerAll(
    Map<String, HotKey> hotKeys, {
    Map<String, String> descriptions = const {},
  }) {
    calls.addAll(hotKeys.keys.map((id) => 'register $id'));
    return inner.registerAll(hotKeys, descriptions: descriptions);
  }

  @override
  Future<void> unregister(String id) {
    calls.add('unregister $id');
    return inner.unregister(id);
  }

  @override
  Future<void> unregisterAll() => inner.unregisterAll();

  @override
  Stream<HotKeyEvent> get events => inner.events;

  @override
  Stream<Map<String, String>> get triggers => inner.triggers;

  @override
  Future<bool> configure() => inner.configure();
}
