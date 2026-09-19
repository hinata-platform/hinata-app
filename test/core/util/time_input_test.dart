import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/time_input.dart';

void main() {
  group('parseTimeInput', () {
    test('reads the ways a time is typed', () {
      expect(parseTimeInput('9'), (hour: 9, minute: 0));
      expect(parseTimeInput('21'), (hour: 21, minute: 0));
      expect(parseTimeInput('930'), (hour: 9, minute: 30));
      expect(parseTimeInput('0930'), (hour: 9, minute: 30));
      expect(parseTimeInput('21:45'), (hour: 21, minute: 45));
      expect(parseTimeInput('9.30'), (hour: 9, minute: 30));
      expect(parseTimeInput('9h30'), (hour: 9, minute: 30));
    });

    test('reads a meridiem, and only with a twelve-hour hour', () {
      expect(parseTimeInput('9:30 pm'), (hour: 21, minute: 30));
      expect(parseTimeInput('12am'), (hour: 0, minute: 0));
      expect(parseTimeInput('12 pm'), (hour: 12, minute: 0));
      expect(parseTimeInput('13 pm'), isNull);
      expect(
        parseTimeInput('7 nachm.', meridiems: (am: 'vorm.', pm: 'nachm.')),
        (hour: 19, minute: 0),
      );
    });

    test('refuses what is no time', () {
      expect(parseTimeInput(''), isNull);
      expect(parseTimeInput('24'), isNull);
      expect(parseTimeInput('9:60'), isNull);
      expect(parseTimeInput('12345'), isNull);
      expect(parseTimeInput('noon'), isNull);
    });
  });

  group('TimeInputFormatter', () {
    const formatter = TimeInputFormatter();

    /// Types [keys] one at a time into an empty field, as a person would.
    String type(String keys) {
      var value = TextEditingValue.empty;
      for (final key in keys.split('')) {
        final next = value.text + key;
        value = formatter.formatEditUpdate(
          value,
          TextEditingValue(
            text: next,
            selection: TextSelection.collapsed(offset: next.length),
          ),
        );
      }
      return value.text;
    }

    test('puts the colon in as the hour is whole', () {
      expect(type('0930'), '09:30');
      expect(type('2145'), '21:45');
      expect(type('21'), '21:');
      expect(type('2'), '2');
    });

    test('a digit no hour continues is the hour on its own', () {
      expect(type('9'), '09:');
      expect(type('930'), '09:30');
    });

    test('a typed separator ends the hour and is not doubled', () {
      expect(type('1:5'), '01:5');
      expect(type('21:30'), '21:30');
    });

    test('keys that would make an impossible time are not taken', () {
      expect(type('25'), '2');
      expect(type('097'), '09:');
      expect(type('0970'), '09:0');
      expect(type('09301'), '09:30');
      expect(type('9a'), '09:');
    });

    test('backspace on a bare colon removes it for good', () {
      final shaped = formatter.formatEditUpdate(
        const TextEditingValue(text: '09:'),
        const TextEditingValue(
          text: '09',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(shaped.text, '09');
    });
  });
}
