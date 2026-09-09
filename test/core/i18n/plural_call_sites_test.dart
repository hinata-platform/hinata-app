import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A `_plural` wording is only ever chosen if the count arrives as a number.
///
/// i18next casts `variables['count']` to `int` to pick the plural form
/// (`translator.dart`, `_castAs<int>`), and a `String` casts to `null`. So a
/// call that interpolates the number itself — `variables: {'count': '$n'}` —
/// always resolves the singular, and the `_plural` sibling sitting next to the
/// key is wording nobody will ever see.
///
/// Nothing about that fails loudly. The screen still renders a sentence; it is
/// simply the wrong one — "1 entries", or, where the singular form has no
/// `{{count}}` of its own, a number that has quietly disappeared. It is caught
/// by reading the sentence, which is exactly what a test is for.
///
/// `t(key, count: n)` is the form that works. A raw `int` inside `variables`
/// works too, so only the string form is called out.
void main() {
  test('a pluralised key is asked for with a number, not a string', () {
    final english = _flatten(
      json.decode(File('assets/i18n/en/common.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final pluralised = english.keys
        .where((k) => k.endsWith('_plural'))
        .map((k) => k.substring(0, k.length - '_plural'.length))
        .toSet();

    final call = RegExp(r"""t\(\s*'([\w.]+)'(.{0,400}?)\)""", dotAll: true);
    final stringCount = RegExp(r"""'count':\s*['"]""");
    // A call may carry both -- `i18next.t` writes the `count:` argument over
    // whatever `variables['count']` held, so the named one wins and the string
    // beside it is merely redundant. Only a call with no `count:` at all is
    // actually resolving the singular.
    final namedCount = RegExp(r'\bcount:\s');

    final offenders = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in call.allMatches(source)) {
        if (!pluralised.contains(match[1])) continue;
        if (!stringCount.hasMatch(match[2]!)) continue;
        if (namedCount.hasMatch(match[2]!)) continue;
        offenders.add('${file.path}: ${match[1]}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these call sites pass count as a string, so the _plural wording '
          'beside the key can never be chosen — use t(key, count: n):\n'
          '${offenders.join('\n')}',
    );
  });
}

/// `{"a": {"b": "c"}}` -> `{"a.b": "c"}`.
Map<String, String> _flatten(Map<String, dynamic> node, [String prefix = '']) {
  final out = <String, String>{};
  node.forEach((key, value) {
    final path = prefix.isEmpty ? key : '$prefix.$key';
    if (value is Map<String, dynamic>) {
      out.addAll(_flatten(value, path));
    } else {
      out[path] = '$value';
    }
  });
  return out;
}
