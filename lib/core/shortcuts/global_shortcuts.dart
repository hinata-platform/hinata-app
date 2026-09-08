import 'package:flutter/services.dart';

import '../../features/search/global_search_dialog.dart' show openGlobalSearch;
import 'app_shortcuts.dart';
import 'shortcuts_sheet.dart';

/// The two shortcuts that belong to the application rather than to a feature.
///
/// A single list, built once, because [ScopedShortcuts] compares the list it was
/// given with the one before it — a fresh literal on every build would
/// unregister and re-register the lot on every frame.
final List<AppShortcut> kGlobalShortcuts = [
  const AppShortcut(
    id: 'app.search',
    key: LogicalKeyboardKey.keyK,
    labelKey: 'shortcuts.app.search',
    onInvoke: openGlobalSearch,
  ),
  const AppShortcut(
    id: 'app.shortcuts',
    key: LogicalKeyboardKey.slash,
    labelKey: 'shortcuts.app.shortcuts',
    onInvoke: showShortcutsSheet,
  ),
];
