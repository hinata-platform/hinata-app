import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/docs/docs_links.dart';

void main() {
  group('docsUrl', () {
    test('links a page in a language the docs are written in', () {
      expect(
        docsUrl('de', DocsPage.timeTrackingAdmin).toString(),
        'https://hinata.ahmadre.com/de/admin-time-tracking.html',
      );
    });

    test('sends every other language to the English page', () {
      expect(
        docsUrl('ja', DocsPage.absences).toString(),
        'https://hinata.ahmadre.com/en/absences.html',
      );
    });
  });
}
