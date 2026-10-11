import 'package:system_hotkeys/system_hotkeys.dart';

import 'surface_platform.dart';

/// Whether [hotKey] may be bound system-wide on [platform].
///
/// A system-wide shortcut is taken from every other app, so it must not be
/// something people type. Shift or Alt alone make capitals and the special
/// characters of a layout (⌥S is "ß" on a German Mac), so a combination needs
/// Control or Command/Windows. One of those alone is every app's own
/// shortcuts — ⌘S, Ctrl+C — so it needs a second modifier. And on Windows and
/// Linux, Ctrl+Alt is AltGr: Ctrl+Alt+Q is "@" on a German keyboard, so
/// Ctrl+Alt needs Shift or the Windows key besides.
bool isSafeHotkey(HotKey hotKey, SurfacePlatform platform) {
  final m = hotKey.modifiers;
  if (!HotKey.isSupportedKey(hotKey.key)) return false;
  if (!m.contains(HotKeyModifier.control) && !m.contains(HotKeyModifier.meta)) {
    return false;
  }
  if (m.length < 2) return false;
  final altGr =
      m.length == 2 &&
      m.contains(HotKeyModifier.control) &&
      m.contains(HotKeyModifier.alt);
  return platform == SurfacePlatform.macos || !altGr;
}
