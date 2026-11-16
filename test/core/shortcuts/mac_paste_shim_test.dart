// ⌘V into a text field, sent the way Raycast's "Paste to …" and other
// launchers send it on macOS.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/shortcuts/mac_paste_shim.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

const _emoji = '✅😊☀️❤️👨‍👩‍👧';

final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

/// Serves [_emoji] to `Clipboard.getData` and counts the reads.
int Function() _clipboard(WidgetTester tester) {
  var reads = 0;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method != 'Clipboard.getData') return null;
      reads++;
      return {'text': _emoji};
    },
  );
  return () => reads;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MacPasteShim(
        child: Scaffold(body: Column(children: [child])),
      ),
    ),
  );
  await tester.pump();
}

/// Lets the async clipboard read and the field's update land.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

/// Sends V with only the side-less command flag on it, as the engine hands
/// such an event over: key data with no modifier, the raw message with
/// `NSEventModifierFlagCommand` (0x100000) alone.
Future<void> _flagOnlyCommandV(WidgetTester tester) async {
  // The engine's own entry point. Deprecated for apps, and the only way to
  // hand the framework exactly the pair the engine hands it.
  // ignore: deprecated_member_use
  final manager = tester.binding.keyEventManager;
  for (final (type, raw) in [
    (ui.KeyEventType.down, 'keydown'),
    (ui.KeyEventType.up, 'keyup'),
  ]) {
    // ignore: deprecated_member_use
    manager.handleKeyData(
      ui.KeyData(
        timeStamp: Duration.zero,
        type: type,
        physical: PhysicalKeyboardKey.keyV.usbHidUsage,
        logical: LogicalKeyboardKey.keyV.keyId,
        character: type == ui.KeyEventType.down ? 'v' : null,
        synthesized: false,
      ),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.keyEvent.name,
      SystemChannels.keyEvent.codec.encodeMessage(<String, Object?>{
        'type': raw,
        'keymap': 'macos',
        'keyCode': 9,
        'characters': 'v',
        'charactersIgnoringModifiers': 'v',
        'modifiers': 0x100000,
      }),
      (_) {},
    );
  }
}

/// Sends one V event the way the engine does, without yielding in between, so
/// nothing scheduled before it can run first.
bool? Function() _sendV(
  WidgetTester tester, {
  required int modifiers,
  bool down = true,
}) {
  bool? handled;
  // ignore: deprecated_member_use
  tester.binding.keyEventManager.handleKeyData(
    ui.KeyData(
      timeStamp: Duration.zero,
      type: down ? ui.KeyEventType.down : ui.KeyEventType.up,
      physical: PhysicalKeyboardKey.keyV.usbHidUsage,
      logical: LogicalKeyboardKey.keyV.keyId,
      character: down ? 'v' : null,
      synthesized: false,
    ),
  );
  tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.keyEvent.name,
    SystemChannels.keyEvent.codec.encodeMessage(<String, Object?>{
      'type': down ? 'keydown' : 'keyup',
      'keymap': 'macos',
      'keyCode': 9,
      'characters': 'v',
      'charactersIgnoringModifiers': 'v',
      'modifiers': modifiers,
    }),
    (reply) {
      final decoded = SystemChannels.keyEvent.codec.decodeMessage(reply);
      handled = (decoded as Map<Object?, Object?>?)?['handled'] as bool?;
    },
  );
  return () => handled;
}

void main() {
  testWidgets('⌘ that only the event carries still pastes into a field', (
    tester,
  ) async {
    final reads = _clipboard(tester);
    final controller = TextEditingController(text: 'ab');
    addTearDown(controller.dispose);
    await _pump(tester, TextField(controller: controller, autofocus: true));

    await _flagOnlyCommandV(tester);
    expect(HardwareKeyboard.instance.isMetaPressed, isFalse);
    await _settle(tester);

    expect(controller.text, 'ab$_emoji');
    expect(reads(), 1);
  }, variant: _macOS);

  testWidgets('a V that lands while focus is parked pastes into the field', (
    tester,
  ) async {
    // The launcher's panel made the app inactive; the framework parked focus
    // on the root scope and gives it back only at its next update. The posted
    // key-down arrives first.
    final reads = _clipboard(tester);
    final controller = TextEditingController(text: 'ab');
    final focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    await _pump(
      tester,
      TextField(controller: controller, focusNode: focus, autofocus: true),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    // Resume and key in the same turn, as they arrive from the engine: the
    // framework has asked for focus back but not applied it yet. The event
    // carries only the side-less command flag, as Raycast sends it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final manager = FocusManager.instance;
    expect(manager.primaryFocus, manager.rootScope, reason: 'still parked');
    _sendV(tester, modifiers: 0x100000);
    _sendV(tester, modifiers: 0x100000, down: false);
    await _settle(tester);

    expect(controller.text, 'ab$_emoji');
    expect(reads(), 1);
    expect(focus.hasPrimaryFocus, isTrue);
  }, variant: _macOS);

  testWidgets('a paste Flutter handles itself is not pasted twice', (
    tester,
  ) async {
    final reads = _clipboard(tester);
    final controller = TextEditingController(text: 'ab');
    addTearDown(controller.dispose);
    await _pump(tester, TextField(controller: controller, autofocus: true));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await _settle(tester);

    expect(controller.text, 'ab$_emoji');
    expect(reads(), 1);
  }, variant: _macOS);

  testWidgets('a field that lost focus to something else gets nothing', (
    tester,
  ) async {
    final reads = _clipboard(tester);
    final controller = TextEditingController(text: 'ab');
    final other = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(other.dispose);
    await _pump(
      tester,
      Column(
        children: [
          TextField(controller: controller, autofocus: true),
          Focus(focusNode: other, child: const SizedBox(height: 10)),
        ],
      ),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    other.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await _settle(tester);

    expect(controller.text, 'ab');
    expect(reads(), 0);
    expect(other.hasFocus, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  }, variant: _macOS);

  testWidgets('the rich-text editor is left to its own paste', (tester) async {
    // lexical_flutter handles both cases for its editor. The shim must not
    // paste a second time, parked or not.
    final reads = _clipboard(tester);
    final editor = createLexicalEditor();
    registerLexical(editor);
    editor.update(() {
      final paragraph = $createParagraphNode()..append($createTextNode('ab'));
      $getRoot()
        ..clear()
        ..append(paragraph);
      paragraph.selectEnd();
    }, discrete: true);
    await _pump(
      tester,
      SizedBox(
        height: 100,
        child: LexicalEditable(
          editor: editor,
          autofocus: true,
          scrollable: false,
          cursorBlinkInterval: Duration.zero,
          theme: const LexicalTheme(
            baseTextStyle: TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
      ),
    );
    String text() => editor.read(() => $getRoot().getTextContent());

    await _flagOnlyCommandV(tester);
    await _settle(tester);
    expect(text(), 'ab$_emoji');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await _settle(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(text(), 'ab$_emoji$_emoji');
    expect(reads(), 2);
  }, variant: _macOS);

  testWidgets('a read-only field is left alone', (tester) async {
    final reads = _clipboard(tester);
    final controller = TextEditingController(text: 'ab');
    addTearDown(controller.dispose);
    await _pump(
      tester,
      TextField(controller: controller, readOnly: true, autofocus: true),
    );

    final handled = _sendV(tester, modifiers: 0x100000);
    _sendV(tester, modifiers: 0x100000, down: false);
    await _settle(tester);

    expect(controller.text, 'ab');
    expect(reads(), 0);
    expect(handled(), isFalse, reason: 'left alone, not swallowed');
  }, variant: _macOS);

  testWidgets(
    'a field taken down while parked gets nothing and keeps nothing',
    (tester) async {
      final reads = _clipboard(tester);
      final controller = TextEditingController(text: 'ab');
      addTearDown(controller.dispose);
      await _pump(tester, TextField(controller: controller, autofocus: true));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await _pump(tester, const SizedBox());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      _sendV(tester, modifiers: 0x100000);
      _sendV(tester, modifiers: 0x100000, down: false);
      await _settle(tester);

      expect(controller.text, 'ab');
      expect(reads(), 0);
      expect(tester.takeException(), isNull);
    },
    variant: _macOS,
  );

  testWidgets('elsewhere than macOS the flag means nothing', (tester) async {
    final reads = _clipboard(tester);
    final controller = TextEditingController(text: 'ab');
    addTearDown(controller.dispose);
    await _pump(tester, TextField(controller: controller, autofocus: true));

    _sendV(tester, modifiers: 0x100000);
    _sendV(tester, modifiers: 0x100000, down: false);
    await _settle(tester);

    expect(controller.text, 'ab');
    expect(reads(), 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('⌘⇧V is not a paste', (tester) async {
    // SingleActivator(V, meta: true) matches exactly; with Shift held the
    // field's own shortcut does not fire, and neither may the shim.
    final reads = _clipboard(tester);
    final controller = TextEditingController(text: 'ab');
    addTearDown(controller.dispose);
    await _pump(tester, TextField(controller: controller, autofocus: true));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    _sendV(tester, modifiers: 0x100000 | 0x20002);
    _sendV(tester, modifiers: 0x100000 | 0x20002, down: false);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _settle(tester);

    expect(controller.text, 'ab');
    expect(reads(), 0);
  }, variant: _macOS);

  testWidgets(
    'an editor parked earlier does not take a text field\'s paste later',
    (tester) async {
      // The editor had focus when the app went inactive and armed itself for
      // parked keys; focus then moved to a text field before the app came
      // back. When the field is parked later and Raycast pastes, the paste
      // belongs to the field. lexical_flutter 1.11.2 drops the editor's stale
      // claim as soon as focus leaves the root scope.
      final reads = _clipboard(tester);
      final editor = createLexicalEditor();
      registerLexical(editor);
      editor.update(() {
        final paragraph = $createParagraphNode()..append($createTextNode('ab'));
        $getRoot()
          ..clear()
          ..append(paragraph);
        paragraph.selectEnd();
      }, discrete: true);
      final controller = TextEditingController(text: 'cd');
      final field = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(field.dispose);
      await _pump(
        tester,
        Column(
          children: [
            SizedBox(
              height: 100,
              child: LexicalEditable(
                editor: editor,
                autofocus: true,
                scrollable: false,
                cursorBlinkInterval: Duration.zero,
                theme: const LexicalTheme(
                  baseTextStyle: TextStyle(fontSize: 14, height: 1.4),
                ),
              ),
            ),
            TextField(controller: controller, focusNode: field),
          ],
        ),
      );
      String text() => editor.read(() => $getRoot().getTextContent());

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      field.requestFocus();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(field.hasPrimaryFocus, isTrue);
      // The caret at the end, where a click into the field would put it.
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      _sendV(tester, modifiers: 0x100000);
      _sendV(tester, modifiers: 0x100000, down: false);
      await _settle(tester);

      expect(controller.text, 'cd$_emoji');
      expect(text(), 'ab');
      expect(reads(), 1);
    },
    variant: _macOS,
  );
}
