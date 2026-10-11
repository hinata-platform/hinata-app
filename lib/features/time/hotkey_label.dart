import 'package:system_hotkeys/system_hotkeys.dart';

import '../../core/timer_surfaces/surface_platform.dart';

/// [hotKey] the way the platform writes a shortcut: `⌃⌥⇧⌘S` on a Mac, in
/// Apple's order, and `Ctrl+Alt+Shift+Win+S` elsewhere.
String hotkeyLabel(
  HotKey hotKey,
  SurfacePlatform platform, {
  String space = 'Space',
}) {
  final key = keyLabel(hotKey.key.usbHidUsage, space: space);
  final m = hotKey.modifiers;
  if (platform == SurfacePlatform.macos) {
    return [
      if (m.contains(HotKeyModifier.control)) '⌃',
      if (m.contains(HotKeyModifier.alt)) '⌥',
      if (m.contains(HotKeyModifier.shift)) '⇧',
      if (m.contains(HotKeyModifier.meta)) '⌘',
      key,
    ].join();
  }
  return [
    if (m.contains(HotKeyModifier.control)) 'Ctrl',
    if (m.contains(HotKeyModifier.alt)) 'Alt',
    if (m.contains(HotKeyModifier.shift)) 'Shift',
    if (m.contains(HotKeyModifier.meta)) 'Win',
    key,
  ].join('+');
}

/// The key of a USB HID usage in the keyboard page, as printed on a US key:
/// A to Z, 0 to 9, F1 to F12, [space]. Positions, not characters — the same
/// key on a German keyboard reads the same here.
String keyLabel(int usage, {String space = 'Space'}) {
  if (usage >= 0x00070004 && usage <= 0x0007001d) {
    return String.fromCharCode(0x41 + usage - 0x00070004);
  }
  if (usage >= 0x0007001e && usage <= 0x00070026) {
    return '${usage - 0x0007001e + 1}';
  }
  if (usage == 0x00070027) return '0';
  if (usage >= 0x0007003a && usage <= 0x00070045) {
    return 'F${usage - 0x0007003a + 1}';
  }
  if (usage == 0x0007002c) return space;
  return '?';
}
