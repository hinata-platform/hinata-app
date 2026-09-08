import 'package:flutter/services.dart';

import '../../features/search/global_search_dialog.dart' show openGlobalSearch;
import 'app_shortcuts.dart';
import 'shortcuts_sheet.dart';

/// The two shortcuts that belong to the application rather than to a feature.
///
/// A single list, built once, because [ScopedShortcuts] compares the list it was
/// given with the one before it — a fresh literal on every build would
/// unregister and re-register the lot on every frame.
/// ⌘K. Named, because the search bar prints its label as a hint and must not
/// have to find it by id — a rename would then be a red screen on every route
/// rather than a compile error here.
const AppShortcut kSearchShortcut = AppShortcut(
  id: 'app.search',
  key: LogicalKeyboardKey.keyK,
  labelKey: 'shortcuts.app.search',
  onInvoke: openGlobalSearch,
);

final List<AppShortcut> kGlobalShortcuts = [
  kSearchShortcut,
  const AppShortcut(
    id: 'app.shortcuts',
    key: LogicalKeyboardKey.slash,
    labelKey: 'shortcuts.app.shortcuts',
    // Held until the sheet closes: it is slow to animate in, and pressing again
    // because nothing seemed to happen would stack a second full-screen blur.
    exclusive: true,
    onInvoke: showShortcutsSheet,
  ),
];
