import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/knowledge/knowledge_debouncer.dart';

void main() {
  // The widget tester's clock is a fake one, so a pump moves the timers on.
  group('KbDebouncer', () {
    testWidgets('runs the last call once typing pauses', (tester) async {
      final debouncer = KbDebouncer();
      addTearDown(debouncer.dispose);
      final runs = <String>[];
      debouncer.run(() => runs.add('s'));
      await tester.pump(const Duration(milliseconds: 100));
      debouncer.run(() => runs.add('se'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(runs, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(runs, ['se']);
    });

    testWidgets('a call to run now drops the waiting one', (tester) async {
      final debouncer = KbDebouncer();
      addTearDown(debouncer.dispose);
      final runs = <String>[];
      debouncer.run(() => runs.add('typed'));
      debouncer.run(() => runs.add('cleared'), immediately: true);
      await tester.pump(const Duration(seconds: 1));
      expect(runs, ['cleared']);
    });

    testWidgets('nothing runs after dispose', (tester) async {
      final debouncer = KbDebouncer();
      var ran = false;
      debouncer.run(() => ran = true);
      debouncer.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(ran, isFalse);
    });
  });
}
