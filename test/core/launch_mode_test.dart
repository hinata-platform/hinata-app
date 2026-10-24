import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every link leaves the app for the system's own browser or app (HIN-178):
/// a browser embedded in the app would make the stores rate it as
/// "Unrestricted Web Access", and a link opened there could reach anything.
/// Read from the sources, so a new `launchUrl` without its mode fails here.
void main() {
  /// Calls that may choose otherwise, each with its reason.
  const exceptions = {
    // After an OAuth consent on the web the page hands itself back to the
    // client in the same tab; on a device it already leaves the app.
    'lib/features/oauth/oauth_consent_screen.dart',
    // A sign-in with SSO on the web goes to the provider in the same tab,
    // which brings the reader back; on a device it leaves the app.
    'lib/features/auth/sso_launch.dart',
  };

  test('every launchUrl opens outside the app', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      if (exceptions.contains(path)) continue;
      // Comments may name the call; only code counts.
      final source = file
          .readAsLinesSync()
          .map((line) => line.trimLeft().startsWith('//') ? '' : line)
          .join('\n');
      var at = source.indexOf('launchUrl(');
      while (at >= 0) {
        final call = _call(source, at + 'launchUrl'.length);
        if (!call.contains('LaunchMode.externalApplication')) {
          final line = '\n'.allMatches(source.substring(0, at)).length + 1;
          offenders.add('$path:$line');
        }
        at = source.indexOf('launchUrl(', at + 1);
      }
    }
    expect(offenders, isEmpty);
  });

  test('the exceptions still exist, so the list cannot rot', () {
    for (final path in exceptions) {
      expect(
        File(path).readAsStringSync(),
        contains('launchUrl('),
        reason: path,
      );
    }
  });
}

/// The argument list that opens at [open], up to its closing parenthesis.
String _call(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return source.substring(open);
}
