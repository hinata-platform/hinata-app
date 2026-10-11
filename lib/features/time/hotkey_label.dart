import 'package:system_hotkeys/system_hotkeys.dart';

import '../../core/timer_surfaces/surface_platform.dart';

/// The words printed on modifier keys and the space bar in the reader's
/// language ("Strg" on a German Windows keyboard). A Mac prints symbols.
class KeyNames {
  const KeyNames({
    required this.ctrl,
    required this.alt,
    required this.shift,
    required this.win,
    required this.space,
  });

  final String ctrl;
  final String alt;
  final String shift;
  final String win;
  final String space;
}

/// [hotKey] the way the platform writes a shortcut: `⌃⌥⇧⌘S` on a Mac, in
/// Apple's order, and `Ctrl+Alt+Shift+Win+S` (in [names]) elsewhere.
String hotkeyLabel(
  HotKey hotKey,
  SurfacePlatform platform, {
  required KeyNames names,
}) {
  final key = keyLabel(hotKey.key.usbHidUsage, space: names.space);
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
    if (m.contains(HotKeyModifier.control)) names.ctrl,
    if (m.contains(HotKeyModifier.alt)) names.alt,
    if (m.contains(HotKeyModifier.shift)) names.shift,
    if (m.contains(HotKeyModifier.meta)) names.win,
    key,
  ].join('+');
}

/// The key of a USB HID usage in the keyboard page, as printed on a US key:
/// A to Z, 0 to 9, F1 to F12, [space]. Positions, not characters — the same
/// key on a German keyboard reads the same here. Covers exactly
/// [HotKey.supportedUsages] (a test holds the two together).
String keyLabel(int usage, {required String space}) {
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
