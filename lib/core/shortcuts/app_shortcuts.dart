/// Global keyboard shortcuts: one place that knows what they are, one handler
/// that dispatches them, and one sheet that lists them.
///
/// Before this there was a hand-written [HardwareKeyboard] handler in the shell
/// that knew about exactly one combination, and the only way to add a second
/// was to write the same modifier arithmetic again next to it. The cost of that
/// is not the duplication: it is that nothing could *list* the shortcuts,
/// because there was no list — and a shortcut nobody can discover is a shortcut
/// nobody uses.
///
/// A feature registers what it owns and unregisters when it goes away, so the
/// set on screen is the set that works. The shell registers the search palette;
/// the time module registers its three; the focus screen registers Escape while
/// it is mounted and takes it back with it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Which modifier a shortcut is spelled with.
///
/// Only two, because only two are worth having: the platform's own command key,
/// and nothing. A shortcut with no modifier is a single keystroke and belongs
/// to a screen, not to the application — [AppShortcut.allowInTextField] is
/// false for those and the text-field guard is what keeps them from eating
/// somebody's typing.
enum ShortcutModifier {
  /// ⌘ on macOS and iOS, Ctrl everywhere else. Both are accepted everywhere —
  /// an external keyboard on an iPad has Ctrl, and a Mac user on a Windows
  /// keyboard has no ⌘ — but only one of them is *shown*.
  command,

  /// No modifier at all. Escape, and nothing else so far.
  none,
}

/// One shortcut, and what it does.
@immutable
class AppShortcut {
  const AppShortcut({
    required this.id,
    required this.key,
    required this.labelKey,
    required this.onInvoke,
    this.modifier = ShortcutModifier.command,
    this.shift = false,
    this.groupKey = 'shortcuts.group.general',
    this.allowInTextField = false,
    this.listed = true,
  });

  /// What identifies this shortcut in the registry. Registering the same id
  /// twice replaces the first — which is what a hot reload does, and what a
  /// screen re-registering on rebuild would otherwise turn into a leak.
  final String id;

  final LogicalKeyboardKey key;
  final ShortcutModifier modifier;
  final bool shift;

  /// What it does, as an i18n key.
  final String labelKey;

  /// The heading it appears under in the shortcuts sheet.
  final String groupKey;

  /// Whether it still fires while a text field or the editor has focus.
  ///
  /// False by default, and that is the important half: the rich-text editor
  /// owns combinations like ⌘B and ⌘K while it is focused, and a global handler
  /// that ran first would take them away from it. The ⇧ combinations are the
  /// exception — nothing types them, and no editor claims them.
  final bool allowInTextField;

  /// Whether it appears in the shortcuts sheet. False for one that is only
  /// meaningful on the screen that registered it and reads as noise elsewhere.
  final bool listed;

  /// What to do. Handed a context below the router's navigator, so it can push,
  /// show a dialog, or read a bloc.
  final void Function(BuildContext context) onInvoke;

  /// Whether [event] is this shortcut, given what is held down.
  bool matches(KeyEvent event, Set<LogicalKeyboardKey> held) {
    if (event.logicalKey != key) return false;
    final shiftHeld =
        held.contains(LogicalKeyboardKey.shiftLeft) ||
        held.contains(LogicalKeyboardKey.shiftRight);
    if (shiftHeld != shift) return false;
    final commandHeld =
        held.contains(LogicalKeyboardKey.metaLeft) ||
        held.contains(LogicalKeyboardKey.metaRight) ||
        held.contains(LogicalKeyboardKey.controlLeft) ||
        held.contains(LogicalKeyboardKey.controlRight);
    return commandHeld == (modifier == ShortcutModifier.command);
  }

  /// How it is written for a reader — `⌘⇧S`, `Ctrl ⇧ E`, `Esc`.
  String get label {
    final buffer = StringBuffer();
    if (modifier == ShortcutModifier.command) {
      buffer.write(commandKeyLabel);
      if (!_isApple) buffer.write(' ');
    }
    if (shift) buffer.write('⇧');
    buffer.write(_keyLabel);
    return buffer.toString();
  }

  String get _keyLabel {
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.slash) return '/';
    return (key.keyLabel.isEmpty ? '?' : key.keyLabel).toUpperCase();
  }
}

bool get _isApple =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// The command key as this platform spells it. A Windows or Linux keyboard has
/// no ⌘, and a hint that names one is a hint that lies.
String get commandKeyLabel => _isApple ? '⌘' : 'Ctrl';

/// The set of shortcuts that work right now.
///
/// A [ChangeNotifier] rather than a bloc: it holds no state anybody renders
/// except the sheet that lists it, and it is written to from `initState` — a
/// bloc would mean an event class per registration for no gain.
class AppShortcutRegistry extends ChangeNotifier {
  final Map<String, AppShortcut> _shortcuts = {};

  /// Every shortcut, in registration order.
  List<AppShortcut> get all => List.unmodifiable(_shortcuts.values);

  /// The ones worth showing a reader.
  List<AppShortcut> get listed =>
      _shortcuts.values.where((each) => each.listed).toList();

  void register(AppShortcut shortcut) {
    final existing = _shortcuts[shortcut.id];
    if (existing != null && identical(existing, shortcut)) return;
    _shortcuts[shortcut.id] = shortcut;
    notifyListeners();
  }

  void registerAll(Iterable<AppShortcut> shortcuts) {
    for (final shortcut in shortcuts) {
      _shortcuts[shortcut.id] = shortcut;
    }
    notifyListeners();
  }

  void unregister(String id) {
    if (_shortcuts.remove(id) != null) notifyListeners();
  }

  void unregisterAll(Iterable<String> ids) {
    var changed = false;
    for (final id in ids) {
      changed |= _shortcuts.remove(id) != null;
    }
    if (changed) notifyListeners();
  }

  /// The shortcut [event] fires, or null.
  ///
  /// [inTextField] is decided by the caller rather than read here, so a test can
  /// state the case it means instead of building a focused text field to get it.
  AppShortcut? resolve(
    KeyEvent event, {
    required Set<LogicalKeyboardKey> held,
    required bool inTextField,
  }) {
    if (event is! KeyDownEvent) return null;
    for (final shortcut in _shortcuts.values) {
      if (!shortcut.matches(event, held)) continue;
      if (inTextField && !shortcut.allowInTextField) return null;
      return shortcut;
    }
    return null;
  }
}

/// Whether what has keyboard focus is somewhere text is being typed.
///
/// Asked of the focus tree rather than tracked, because the app has many text
/// fields and one of them being focused is not something they should each have
/// to announce. The rich-text editor is caught by the same question: it puts an
/// [EditableText] behind its surface, which is what receives the keystrokes.
bool textIsBeingEdited() {
  final focus = FocusManager.instance.primaryFocus;
  final context = focus?.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorStateOfType<EditableTextState>() != null;
}

/// Makes one [AppShortcutRegistry] available to the subtree, and dispatches to it.
///
/// It installs a single [HardwareKeyboard] handler, which is genuinely global:
/// it fires whatever has focus, so a shortcut works while a list is scrolled or
/// a canvas is dragged, without a `Focus` widget anywhere having to be right.
/// The guard on text fields is what keeps that from being a problem.
///
/// Placed above the router, not inside the shell, because the focus screen is a
/// route of its own outside the shell and Escape has to work there.
class ShortcutHost extends StatefulWidget {
  const ShortcutHost({
    super.key,
    required this.registry,
    required this.navigatorKey,
    required this.child,
  });

  final AppShortcutRegistry registry;

  /// Where a shortcut's context comes from. The host sits *above* the router's
  /// navigator, so its own context cannot push a route or show a dialog.
  final GlobalKey<NavigatorState> navigatorKey;

  final Widget child;

  @override
  State<ShortcutHost> createState() => _ShortcutHostState();
}

class _ShortcutHostState extends State<ShortcutHost> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final shortcut = widget.registry.resolve(
      event,
      held: HardwareKeyboard.instance.logicalKeysPressed,
      inTextField: textIsBeingEdited(),
    );
    if (shortcut == null) return false;
    final context = widget.navigatorKey.currentContext;
    if (context == null) return false;
    shortcut.onInvoke(context);
    return true;
  }

  @override
  Widget build(BuildContext context) =>
      ShortcutScope(registry: widget.registry, child: widget.child);
}

/// Reaches the registry from anywhere below [ShortcutHost].
class ShortcutScope extends InheritedWidget {
  const ShortcutScope({
    super.key,
    required this.registry,
    required super.child,
  });

  final AppShortcutRegistry registry;

  static AppShortcutRegistry? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShortcutScope>()?.registry;

  /// The registry, or a detached one when there is no host above.
  ///
  /// Never throws: a screen that registers a shortcut must still work in a test
  /// harness that pumps it on its own, and a shortcut nobody can press is a
  /// perfectly good outcome there.
  static AppShortcutRegistry of(BuildContext context) =>
      maybeOf(context) ?? _detached;

  static final AppShortcutRegistry _detached = AppShortcutRegistry();

  @override
  bool updateShouldNotify(ShortcutScope oldWidget) =>
      registry != oldWidget.registry;
}

/// Registers [shortcuts] while [child] is mounted, and takes them back with it.
///
/// The screen-scoped half of the registry. A screen that owns a key only while
/// it is on screen — Escape, on the focus view — wraps itself in this rather
/// than remembering to unregister in `dispose`.
class ScopedShortcuts extends StatefulWidget {
  const ScopedShortcuts({
    super.key,
    required this.shortcuts,
    required this.child,
  });

  final List<AppShortcut> shortcuts;
  final Widget child;

  @override
  State<ScopedShortcuts> createState() => _ScopedShortcutsState();
}

class _ScopedShortcutsState extends State<ScopedShortcuts> {
  AppShortcutRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ShortcutScope.of(context);
    if (identical(registry, _registry)) return;
    _release();
    _registry = registry;
    registry.registerAll(widget.shortcuts);
  }

  @override
  void didUpdateWidget(ScopedShortcuts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shortcuts == widget.shortcuts) return;
    _registry?.unregisterAll(oldWidget.shortcuts.map((each) => each.id));
    _registry?.registerAll(widget.shortcuts);
  }

  void _release() =>
      _registry?.unregisterAll(widget.shortcuts.map((each) => each.id));

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
