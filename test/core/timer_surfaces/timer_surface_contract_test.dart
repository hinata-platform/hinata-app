import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Two promises of the surfaces that no runtime test can see.
void main() {
  test('a surface can only be handed a state, never free text', () {
    final source = File(
      'lib/core/timer_surfaces/timer_surface.dart',
    ).readAsStringSync();
    final surface = source.substring(
      source.indexOf('abstract class TimerSurface {'),
    );

    // Every method of the interface takes the state, a duration or the host.
    expect(RegExp(r'\(\s*String\b').hasMatch(surface), isFalse);
    expect(RegExp(r',\s*String\b').hasMatch(surface), isFalse);
  });

  test('nothing in the surfaces talks to the server or reports anywhere', () {
    final files = Directory('lib/core/timer_surfaces')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    const forbidden = [
      'api_client',
      'repositories/',
      'package:dio',
      'package:http',
      'firebase',
      'analytics',
      'crashlytics',
      'sentry',
    ];
    for (final file in files) {
      final imports = file.readAsLinesSync().where(
        (line) => line.startsWith('import '),
      );
      for (final line in imports) {
        for (final word in forbidden) {
          expect(line.contains(word), isFalse, reason: '${file.path}: $line');
        }
      }
    }
  });

  test('the shortcuts never listen to the keyboard', () {
    // System-wide shortcuts go through the OS registration API
    // (system_hotkeys) and hear their two combinations only. Nothing in the
    // surfaces may watch the keyboard itself.
    final files = Directory('lib/core/timer_surfaces')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    const forbidden = [
      'HardwareKeyboard',
      'RawKeyboard',
      'KeyboardMonitor',
      'keyboard_monitor',
      'hotkey_manager',
    ];
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final word in forbidden) {
        expect(source.contains(word), isFalse, reason: '${file.path}: $word');
      }
    }
  });
}
