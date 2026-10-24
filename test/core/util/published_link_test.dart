import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/util/published_link.dart';

/// What the app opens of an address a server published in its `/meta` (HIN-26):
/// an honest server only takes https addresses there, so the app is the only
/// barrier against a hostile one.
void main() {
  test('an https address with a host opens', () {
    expect(
      publishedLink(' https://werkhaus.example/impressum '),
      Uri.parse('https://werkhaus.example/impressum'),
    );
  });

  test('a file, a bare path, user info or nothing open nothing', () {
    for (final value in [
      'file://attacker.example/share/x.exe',
      '/Windows/System32/calc.exe',
      r'\\attacker.example\share',
      'https://user:secret@werkhaus.example/',
      'javascript:alert(1)',
      'http://werkhaus.example/impressum',
      '   ',
      null,
    ]) {
      expect(publishedLink(value), isNull, reason: value);
    }
  });

  test('the server itself may be plain http on a local network', () {
    expect(
      publishedLink(
        'http://192.168.1.5:8080/api/v1/public/rules',
        server: 'http://192.168.1.5:8080',
      ),
      Uri.parse('http://192.168.1.5:8080/api/v1/public/rules'),
    );
    expect(
      publishedLink(
        'http://other.example/api/v1/public/rules',
        server: 'http://192.168.1.5:8080',
      ),
      isNull,
    );
  });
}
