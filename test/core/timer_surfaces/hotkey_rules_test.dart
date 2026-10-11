import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/timer_surfaces/hotkey_rules.dart';
import 'package:hinata/core/timer_surfaces/surface_platform.dart';
import 'package:hinata/core/timer_surfaces/timer_surface_prefs.dart';
import 'package:hinata/features/time/hotkey_label.dart';
import 'package:system_hotkeys/system_hotkeys.dart';

/// A system-wide shortcut is taken from every app: it must not be anything
/// people type.
void main() {
  HotKey combo(Set<HotKeyModifier> modifiers) =>
      HotKey(key: PhysicalKeyboardKey.keyQ, modifiers: modifiers);
  const mac = SurfacePlatform.macos;
  const windows = SurfacePlatform.windows;

  test('the defaults are safe on their platform', () {
    for (final p in [mac, windows]) {
      expect(isSafeHotkey(TimerSurfacePrefs.defaultToggleHotkey(p), p), isTrue);
      expect(isSafeHotkey(TimerSurfacePrefs.defaultFocusHotkey(p), p), isTrue);
    }
  });

  test('Shift or Alt alone type characters', () {
    for (final p in [mac, windows]) {
      expect(isSafeHotkey(combo({HotKeyModifier.shift}), p), isFalse);
      expect(isSafeHotkey(combo({HotKeyModifier.alt}), p), isFalse);
      expect(
        isSafeHotkey(combo({HotKeyModifier.alt, HotKeyModifier.shift}), p),
        isFalse,
      );
    }
  });

  test('Ctrl+Alt is AltGr off the Mac', () {
    final altGr = combo({HotKeyModifier.control, HotKeyModifier.alt});
    expect(isSafeHotkey(altGr, windows), isFalse);
    expect(isSafeHotkey(altGr, mac), isTrue);
    expect(
      isSafeHotkey(
        combo({
          HotKeyModifier.control,
          HotKeyModifier.alt,
          HotKeyModifier.shift,
        }),
        windows,
      ),
      isTrue,
    );
  });

  test('every key the plugin binds has a printed name', () {
    for (final usage in HotKey.supportedUsages) {
      expect(keyLabel(usage, space: 'Space'), isNot('?'), reason: '$usage');
    }
  });
}
