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

import 'app_shortcuts.dart' show editableTextOf;

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

  /// The text field that had focus before the latest focus change, if focus
  /// was in one. Nothing else is kept, so a field that was taken down with its
  /// dialog is not held on to.
  FocusNode? _previous;

  /// The text field whose focus the framework parked, until focus moves on or
  /// a key finds it taken down.
  FocusNode? _parked;

  bool _installed = false;

  @override
  void initState() {
    super.initState();
    if (!_active) return;
    _installed = true;
    _remember(FocusManager.instance.primaryFocus);
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

  void _remember(FocusNode? node) =>
      _previous = editableTextOf(node) != null ? node : null;

  /// Remembers a text field when focus is parked away from it because the
  /// app went inactive, and forgets it the moment focus lands anywhere else —
  /// that is a claim of its own.
  ///
  /// Focus parked while the app is resumed means the window itself lost focus
  /// — no launcher pastes into that — and is left alone, as lexical_flutter
  /// does for the editor.
  void _onFocusChanged() {
    if (_focusIsParked) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) {
        _parked ??= _previous;
      }
    } else {
      _parked = null;
    }
    _remember(FocusManager.instance.primaryFocus);
  }

  /// The keys held while the event is dispatched, as the raw keyboard reads
  /// them off the event's own modifier flags.
  ///
  /// [HardwareKeyboard] knows only the modifier keys the engine told it about,
  /// and the macOS engine tells it nothing for a side-less flag. The raw
  /// keyboard accepts the side-less flag, so a modifier counts when either of
  /// the two knows it.
  static Set<LogicalKeyboardKey> get _heldOnEvent {
    // TODO(rebar): Remove once the macOS engine turns a side-less modifier
    // flag into a modifier key for HardwareKeyboard, or RawKeyboard goes
    // away — whichever comes first. The upstream report is still a draft:
    // "[macOS] ⌘V posted by another app (Raycast, Alfred, clipboard managers)
    // never pastes into a TextField".
    // ignore: deprecated_member_use
    final raw = RawKeyboard.instance.keysPressed;
    return {...HardwareKeyboard.instance.logicalKeysPressed, ...raw};
  }

  /// Whether the event is ⌘V and nothing else, as `SingleActivator(V,
  /// meta: true)` matches it: ⌘⇧V, ⌥⌘V and ⌃⌘V mean other things.
  static bool get _isPlainCommandV {
    final held = _heldOnEvent;
    bool any(LogicalKeyboardKey left, LogicalKeyboardKey right) =>
        held.contains(left) || held.contains(right);
    return any(LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.metaRight) &&
        !any(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight) &&
        !any(LogicalKeyboardKey.altLeft, LogicalKeyboardKey.altRight) &&
        !any(LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.controlRight);
  }

  static const _paste = PasteTextIntent(SelectionChangedCause.keyboard);

  /// Whether the field [node] focuses would paste now: it is mounted, not
  /// read-only, and its paste action is there and enabled.
  ///
  /// A key this answers no for is left alone, not swallowed: the field's
  /// paste action does not check read-only before it is invoked, so that is
  /// asked here.
  static bool _canPaste(FocusNode node) {
    final context = node.context;
    if (context == null || !context.mounted) return false;
    final field = editableTextOf(node);
    if (field == null || field.widget.readOnly) return false;
    final action = Actions.maybeFind<PasteTextIntent>(context, intent: _paste);
    if (action == null) return false;
    return action is ContextAction<PasteTextIntent>
        ? action.isEnabled(_paste, context)
        : action.isEnabled(_paste);
  }

  /// Pastes through the field's own action, so an override of it still
  /// applies and the field reports its own clipboard errors.
  static void _invokePaste(FocusNode node) {
    final context = node.context;
    if (context == null || !context.mounted) return;
    Actions.maybeInvoke<PasteTextIntent>(context, _paste);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
      return false;
    }
    if (!_isPlainCommandV) return false;

    if (_focusIsParked) {
      final node = _parked;
      if (node == null) return false;
      // A field taken down while focus was parked — its dialog closed — is
      // dropped here: it is neither focused nor pasted into, and not held on
      // to any longer.
      if (editableTextOf(node) == null) {
        _parked = null;
        return false;
      }
      if (!_canPaste(node)) return false;
      // The framework is about to give focus back to exactly this field; the
      // key only arrived first. Nothing is decided here: in a microtask, after
      // whatever focus change is already pending has been applied, the field
      // either has focus again or focus is still parked, and only then does
      // it get focus and the text. Focus that went anywhere else in the
      // meantime — a request already marked for focus when the key came in is
      // applied before this runs — wins, and the key is dropped.
      //
      // Asking for focus right here instead would hand this very key to the
      // field's own paste shortcut as well, since the focus tree is asked after
      // the keyboard handlers.
      scheduleMicrotask(() {
        if (_focusIsParked) {
          node.requestFocus();
          scheduleMicrotask(() {
            if (node.hasPrimaryFocus) _invokePaste(node);
          });
        } else if (node.hasPrimaryFocus) {
          _invokePaste(node);
        }
      });
      return true;
    }

    // Focus is where it should be. With ⌘ known to HardwareKeyboard the
    // field's own paste shortcut runs, and running it here too would paste
    // twice; only the side-less flag needs help.
    if (HardwareKeyboard.instance.isMetaPressed) return false;
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !_canPaste(node)) return false;
    _invokePaste(node);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
