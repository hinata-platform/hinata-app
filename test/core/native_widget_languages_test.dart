/// The timer widgets' own strings (HIN-102), checked against the app's list
/// of languages.
///
/// Everything a widget or the Live Activity shows comes from the app, in the
/// reader's language, and the translation parity test guards that. The one
/// thing the system reads before the app ever ran is the gallery: the name and
/// the description in the widget picker. Those live natively, once per
/// language, and this is what notices a tenth language that only Dart got.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';

void main() {
  final languages = I18n.supportedLocales
      .map((l) => l.languageCode)
      .toList(growable: false);

  Map<String, String> appleStrings(String path) => {
    for (final m in RegExp(
      r'^"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)";',
      multiLine: true,
    ).allMatches(File(path).readAsStringSync()))
      m.group(1)!: m.group(2)!,
  };

  Map<String, String> androidStrings(String path) => {
    for (final m in RegExp(
      r'<string name="([^"]+)">([^<]*)</string>',
    ).allMatches(File(path).readAsStringSync()))
      m.group(1)!: m.group(2)!,
  };

  test('iOS: name and description of the widget in every language', () {
    for (final language in languages) {
      final strings = appleStrings(
        'ios/HinataWidgets/$language.lproj/Localizable.strings',
      );
      expect(strings.keys.toSet(), {
        'widget.name',
        'widget.description',
      }, reason: language);
      expect(strings.values.every((v) => v.trim().isNotEmpty), isTrue);
    }
  });

  test('iOS: every .lproj of the extension is in the Xcode project', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    for (final language in languages) {
      expect(
        project,
        contains('path = $language.lproj/Localizable.strings'),
        reason: language,
      );
    }
  });

  test('iOS: the extension declares every language', () {
    final plist = File('ios/HinataWidgets/Info.plist').readAsStringSync();
    for (final language in languages) {
      expect(plist, contains('<string>$language</string>'), reason: language);
    }
  });

  test('Android: name and description of the widget in every language', () {
    for (final language in languages) {
      final folder = language == 'en' ? 'values' : 'values-$language';
      final strings = androidStrings(
        'android/app/src/main/res/$folder/widget_strings.xml',
      );
      expect(strings.keys.toSet(), {
        'timer_widget_name',
        'timer_widget_description',
      }, reason: language);
      expect(strings.values.every((v) => v.trim().isNotEmpty), isTrue);
    }
  });

  test('no other language than the app speaks', () {
    final apple = Directory('ios/HinataWidgets')
        .listSync()
        .whereType<Directory>()
        .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
        .where((name) => name.endsWith('.lproj'))
        .map((name) => name.replaceAll('.lproj', ''))
        .toSet();
    expect(apple, languages.toSet());
  });
}
