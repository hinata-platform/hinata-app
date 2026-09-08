import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/search/command_registry.dart';

/// What the ⌘K palette offers, and to whom.
///
/// The list used to be a literal inside the palette's own controller, private
/// and unreachable — which is how the timesheet came to be missing from it. The
/// two things worth pinning are that a feature's commands are listed only where
/// that feature exists, and that every command can actually be run.
void main() {
  test('the module is listed only where the module exists', () {
    final without = paletteCommands(advancedTime: false).map((c) => c.id);
    final with_ = paletteCommands(advancedTime: true).map((c) => c.id);

    expect(without, isNot(contains('time.focus')));
    expect(without, isNot(contains('time.timesheet')));
    // Five rows leading to a not-found page is worse than five rows fewer.
    expect(with_.length - without.length, 5);
    expect(
      with_,
      containsAll([
        'time.toggle',
        'time.newEntry',
        'time.focus',
        'time.list',
        'time.timesheet',
      ]),
    );
  });

  test('every command either goes somewhere or does something', () {
    for (final command in paletteCommands(advancedTime: true)) {
      expect(
        command.route != null || command.onSelect != null,
        isTrue,
        reason: '${command.id} does nothing at all',
      );
      expect(command.labelKey, startsWith('search.cmd.'));
    }
  });

  test('no two commands share an id', () {
    final ids = paletteCommands(advancedTime: true).map((c) => c.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  test('a command that toggles something does not close the palette', () {
    final commands = {
      for (final command in paletteCommands(advancedTime: true))
        command.id: command,
    };

    // Both are switches: somebody comparing light against dark, or starting a
    // timer and then wanting the next command, should not have to reopen it.
    expect(commands['app.theme']!.closesOnSelect, isFalse);
    expect(commands['time.toggle']!.closesOnSelect, isFalse);
    // Navigating away obviously does.
    expect(commands['nav.board']!.closesOnSelect, isTrue);
  });
}
