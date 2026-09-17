import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every translation key the code asks for by name exists in the bundle.
///
/// `context.t` returns the key itself when it finds nothing, and nothing about
/// that fails: the screen renders, the toast appears, the layout is fine. The
/// only thing wrong is that it says `error.timeOff.reasonRequired` to somebody
/// who forgot to type a reason. That is how it shipped — a client-side check
/// written against a key the *server's* message bundle has and the app's does
/// not, which no test and no reviewer caught, and which the person who owns the
/// product found by using it.
///
/// Only literal keys are checked, because only they can be checked: a key built
/// from a variable (`'absence.kind.${kind.name}'`) or handed in as one
/// (`context.t(failure.message)`, where the value is already a sentence from the
/// server) is not knowable here. Those are exactly the call sites that cannot
/// go wrong this way, so the loss is nothing.
void main() {
  test('every literal key a widget asks for is in the bundle', () {
    final known = _flatten(
      json.decode(File('assets/i18n/en/common.json').readAsStringSync())
          as Map<String, dynamic>,
    );

    // `.t('some.key'` — the extension on BuildContext, however the receiver is
    // spelled: `context.t(`, `ctx.t(`, `sheetContext.t(`.
    final call = RegExp(r"""\.t\(\s*'([A-Za-z][\w.]*)'""");

    final missing = <String>[];
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final match in call.allMatches(source)) {
        final key = match[1]!;
        if (!known.contains(key)) missing.add('${file.path}: $key');
      }
    }

    expect(
      missing,
      isEmpty,
      reason:
          'these keys are asked for by name and are not in '
          'assets/i18n/en/common.json, so the raw key is what people read:\n'
          '${missing.join('\n')}',
    );
  });
}

Set<String> _flatten(Map<String, dynamic> node, [String prefix = '']) {
  final keys = <String>{};
  node.forEach((key, value) {
    final full = '$prefix$key';
    keys.add(full);
    if (value is Map<String, dynamic>) keys.addAll(_flatten(value, '$full.'));
  });
  return keys;
}
