import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/ingest_models.dart';

/// A mail connection as Admin → E-mail shows it: what the text check refused
/// is read, kept through an edit, and never sent back (HIN-176).
void main() {
  test('the refused mails are read, kept through an edit and never sent', () {
    final connection = IngestConnection.fromJson(const {
      'id': 'c1',
      'host': 'imap.example.org',
      'username': 'support@example.org',
      'textRefusals': 3,
      'lastTextRefusalAt': '2026-10-23T08:15:00Z',
    });

    expect(connection.textRefusals, 3);
    expect(
      connection.lastTextRefusalAt?.toUtc(),
      DateTime.utc(2026, 10, 23, 8, 15),
    );

    final edited = connection.copyWith(folder: 'Support');
    expect(edited.textRefusals, 3);
    expect(edited.lastTextRefusalAt, connection.lastTextRefusalAt);
    expect(edited.toJson().keys, isNot(contains('textRefusals')));
    expect(edited.toJson().keys, isNot(contains('lastTextRefusalAt')));
  });

  test('an older server sends no count, which reads as none', () {
    final connection = IngestConnection.fromJson(const {'id': 'c1'});

    expect(connection.textRefusals, 0);
    expect(connection.lastTextRefusalAt, isNull);
  });
}
