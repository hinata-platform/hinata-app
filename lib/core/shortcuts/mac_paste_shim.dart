/// Lets ⌘V into a text field arrive the way a launcher sends it, on macOS.
///
/// Raycast's emoji picker, Alfred and clipboard managers paste by writing to
/// the pasteboard and posting ⌘V into the front app. Typed by hand that works
/// everywhere; posted by a launcher it reached no text field in the app, for
/// two reasons that each lose the key on their own:
///
/// * While the launcher's panel is up the app is inactive and the framework
///   parks focus on the root scope. It hands focus back on resume, but only at
///   its next focus update, and the posted key-down is dispatched before that.
///   Nothing is focused when it arrives, so nothing pastes.
/// * The posted event carries only the side-less command flag. The macOS
///   engine synthesizes modifier keys from the left- and right-hand bits
///   alone, so [HardwareKeyboard] never hears of ⌘ and the paste shortcut,
///   which asks it, does not match.
///
/// Both belong to Flutter. The rich-text editor works around them in the
/// lexical_flutter package; this covers every [EditableText] in the app, from
/// the comment line to a dialog's field. It does nothing on other platforms,
/// nothing for a paste Flutter already handles, and nothing for a field that
/// is not the one the framework is about to give focus back to.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Installs the macOS paste repair for the subtree, once, above the router.
class MacPasteShim extends StatefulWidget {
  const MacPasteShim({required this.child, super.key});

  final Widget child;

  @override
  State<MacPasteShim> createState() => _MacPasteShimState();
}

class _MacPasteShimState extends State<MacPasteShim> {
  /// Whether this platform needs the repair at all.
  static bool get _active =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// What had focus before the latest focus change.
  FocusNode? _previous;

  /// The text field whose focus the framework parked, until focus moves on.
  FocusNode? _parked;

  bool _installed = false;

  @override
  void initState() {
    super.initState();
    if (!_active) return;
    _installed = true;
    _previous = FocusManager.instance.primaryFocus;
    FocusManager.instance.addListener(_onFocusChanged);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    if (_installed) {
      FocusManager.instance.removeListener(_onFocusChanged);
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    super.dispose();
  }

  static bool get _focusIsParked {
    final manager = FocusManager.instance;
    return manager.primaryFocus == manager.rootScope;
  }

  /// The text field [node] focuses, or null when it is not one.
  static EditableTextState? _editableOf(FocusNode? node) {
    final context = node?.context;
    if (context == null || !context.mounted) return null;
    if (context is StatefulElement && context.state is EditableTextState) {
      return context.state as EditableTextState;
    }
    return context.findAncestorStateOfType<EditableTextState>();
  }

  /// Remembers a text field when focus is parked away from it, and forgets it
  /// the moment focus lands anywhere else — that is a claim of its own.
  void _onFocusChanged() {
    final now = FocusManager.instance.primaryFocus;
    if (_focusIsParked) {
      _parked ??= _editableOf(_previous) != null ? _previous : null;
    } else {
      _parked = null;
    }
    _previous = now;
  }

  /// Whether the event being dispatched carries ⌘.
  ///
  /// The raw keyboard reads the modifiers off each event and accepts the
  /// side-less flag; [HardwareKeyboard] knows only the keys it was told about.
  static bool get _commandOnEvent {
    if (HardwareKeyboard.instance.isMetaPressed) return true;
    // ignore: deprecated_member_use
    final pressed = RawKeyboard.instance.keysPressed;
    return pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return false;
    }
    if (!_commandOnEvent) return false;

    if (_focusIsParked) {
      final node = _parked;
      final field = _editableOf(node);
      if (node == null || field == null) return false;
      // The framework is about to give focus back to exactly this field; the
      // key only arrived first. The text goes in once focus is applied, so
      // the field has its caret back. Applying focus right here instead would
      // hand this very key to the field's own paste shortcut as well, since
      // the focus tree is asked after the keyboard handlers.
      node.requestFocus();
      scheduleMicrotask(() {
        if (node.hasFocus) field.pasteText(SelectionChangedCause.keyboard);
      });
      return true;
    }

    // Focus is where it should be. With ⌘ known to HardwareKeyboard the
    // field's own paste shortcut runs, and running it here too would paste
    // twice; only the side-less flag needs help.
    if (HardwareKeyboard.instance.isMetaPressed) return false;
    final field = _editableOf(FocusManager.instance.primaryFocus);
    if (field == null) return false;
    field.pasteText(SelectionChangedCause.keyboard);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
