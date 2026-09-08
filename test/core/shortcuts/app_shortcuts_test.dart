import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/shortcuts/app_shortcuts.dart';

/// What the registry answers, and what it refuses to answer.
///
/// Dispatch is asked of [AppShortcutRegistry.resolve] rather than of a pumped
/// widget tree, because the two questions worth pinning — which combination is
/// this, and is somebody typing — are decided there, and a test that had to
/// focus a real text field to ask the second would be testing Flutter's focus
/// tree instead of ours.
void main() {
  KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  // Not `const`: LogicalKeyboardKey has no primitive equality, so a constant
  // set of them is a compile error rather than a set.
  final meta = {LogicalKeyboardKey.metaLeft};
  final ctrl = {LogicalKeyboardKey.controlLeft};
  final metaShift = {LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft};

  AppShortcut shortcut({
    String id = 's',
    LogicalKeyboardKey key = LogicalKeyboardKey.keyK,
    bool shift = false,
    ShortcutModifier modifier = ShortcutModifier.command,
    bool allowInTextField = false,
    bool listed = true,
    VoidCallback? onInvoke,
  }) => AppShortcut(
    id: id,
    key: key,
    shift: shift,
    modifier: modifier,
    allowInTextField: allowInTextField,
    listed: listed,
    labelKey: 'shortcuts.app.search',
    onInvoke: (_) => onInvoke?.call(),
  );

  group('what fires', () {
    test('the command key is ⌘ or Ctrl, whichever the keyboard has', () {
      final registry = AppShortcutRegistry()..register(shortcut());

      for (final held in [meta, ctrl]) {
        expect(
          registry.resolve(
            down(LogicalKeyboardKey.keyK),
            held: held,
            inTextField: false,
          ),
          isNotNull,
          reason: 'both modifiers are accepted; only one of them is *shown*',
        );
      }
    });

    test('a bare key is not the same shortcut as a modified one', () {
      final registry = AppShortcutRegistry()..register(shortcut());

      expect(
        registry.resolve(
          down(LogicalKeyboardKey.keyK),
          held: <LogicalKeyboardKey>{},
          inTextField: false,
        ),
        isNull,
      );
    });

    test(
      'shift is part of the combination, not an extra somebody may hold',
      () {
        final registry = AppShortcutRegistry()
          ..register(shortcut(id: 'plain'))
          ..register(
            shortcut(id: 'shifted', key: LogicalKeyboardKey.keyS, shift: true),
          );

        // ⌘⇧K is not ⌘K: a shortcut that fired with an unasked-for shift held
        // would steal the combination a *different* shortcut is spelled with.
        expect(
          registry.resolve(
            down(LogicalKeyboardKey.keyK),
            held: metaShift,
            inTextField: false,
          ),
          isNull,
        );
        expect(
          registry
              .resolve(
                down(LogicalKeyboardKey.keyS),
                held: metaShift,
                inTextField: false,
              )
              ?.id,
          'shifted',
        );
      },
    );

    test('a key-up is not a keystroke', () {
      final registry = AppShortcutRegistry()..register(shortcut());

      expect(
        registry.resolve(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyK,
            timeStamp: Duration.zero,
          ),
          held: meta,
          inTextField: false,
        ),
        isNull,
      );
    });

    test('Escape is a shortcut with no modifier at all', () {
      final registry = AppShortcutRegistry()
        ..register(
          shortcut(
            id: 'leave',
            key: LogicalKeyboardKey.escape,
            modifier: ShortcutModifier.none,
          ),
        );

      expect(
        registry
            .resolve(
              down(LogicalKeyboardKey.escape),
              held: <LogicalKeyboardKey>{},
              inTextField: false,
            )
            ?.id,
        'leave',
      );
      // Not while ⌘ is held: that is a different keystroke, and claiming it
      // would take ⌘Esc away from whatever the platform does with it.
      expect(
        registry.resolve(
          down(LogicalKeyboardKey.escape),
          held: meta,
          inTextField: false,
        ),
        isNull,
      );
    });
  });

  group('while somebody is typing', () {
    test('a shortcut the editor might claim stands down', () {
      final registry = AppShortcutRegistry()..register(shortcut());

      // ⌘K is "insert link" in a rich-text editor. A global handler that ran
      // first would take it away from the editor that was focused.
      expect(
        registry.resolve(
          down(LogicalKeyboardKey.keyK),
          held: meta,
          inTextField: true,
        ),
        isNull,
      );
    });

    test('a ⇧ combination keeps working', () {
      final registry = AppShortcutRegistry()
        ..register(
          shortcut(
            id: 'stop',
            key: LogicalKeyboardKey.keyS,
            shift: true,
            allowInTextField: true,
          ),
        );

      // Nothing types ⌘⇧S and no editor claims it — and writing a description
      // is exactly when "stop the timer" is most likely to be wanted.
      expect(
        registry
            .resolve(
              down(LogicalKeyboardKey.keyS),
              held: metaShift,
              inTextField: true,
            )
            ?.id,
        'stop',
      );
    });
  });

  group('the list', () {
    test('registering the same id twice replaces rather than duplicates', () {
      var first = 0;
      var second = 0;
      final registry = AppShortcutRegistry()
        ..register(shortcut(onInvoke: () => first++))
        ..register(shortcut(onInvoke: () => second++));

      expect(registry.all, hasLength(1));
      registry.all.single.onInvoke(_context);
      expect(first, 0);
      expect(second, 1);
    });

    test('a screen takes its shortcut back with it', () {
      final registry = AppShortcutRegistry()
        ..registerAll([
          shortcut(id: 'a'),
          shortcut(id: 'b', key: LogicalKeyboardKey.keyB),
        ]);

      registry.unregisterAll(['a', 'b']);

      expect(registry.all, isEmpty);
    });

    test('an unlisted shortcut works but is not shown', () {
      final registry = AppShortcutRegistry()
        ..register(shortcut(id: 'hidden', listed: false));

      expect(registry.all, hasLength(1));
      expect(registry.listed, isEmpty);
    });
  });

  group('how it is written', () {
    test(
      'a label names the key the reader has, and the shift if there is one',
      () {
        // The harness runs as Android, so the command key is Ctrl.
        expect(shortcut(key: LogicalKeyboardKey.keyK).label, 'Ctrl K');
        expect(
          shortcut(key: LogicalKeyboardKey.keyS, shift: true).label,
          'Ctrl ⇧S',
        );
        expect(
          shortcut(
            key: LogicalKeyboardKey.escape,
            modifier: ShortcutModifier.none,
          ).label,
          'Esc',
        );
        expect(shortcut(key: LogicalKeyboardKey.slash).label, 'Ctrl /');
      },
    );
  });
}

/// A context the invoke callbacks above never look at.
final BuildContext _context = _NullContext();

class _NullContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('the fixture never uses its context');
}
