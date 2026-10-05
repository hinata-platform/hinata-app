import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Widget code names its font size from the type scale (AppType, HIN-110);
/// a literal is how the app ended up with twenty sizes, a hundred of them
/// below the reading floor.
///
/// Print layouts and the onboarding's scaled miniatures are drawn at their
/// own sizes on purpose and are let through.
void main() {
  test('no literal font sizes in widget code', () {
    const allowed = {
      'lib/features/issues/issue_export.dart', // PDF, print points
      'lib/features/reports/report_pdf.dart', // PDF, print points
      'lib/features/onboarding/onboarding_screen.cards.dart', // miniatures
      'lib/features/onboarding/onboarding_screen.chrome.dart', // miniatures
    };
    final literal = RegExp(r'fontSize:\s*\d');
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (allowed.contains(entity.path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (literal.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'Use AppType instead of a literal.');
  });
}
