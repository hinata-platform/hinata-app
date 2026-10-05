import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/audit_labels.dart';

void main() {
  test('an untranslated action reads as words, not as its key', () {
    expect(humanizeAuditAction('TIME_OFF_YEAR_RUN'), 'Time off year run');
    expect(humanizeAuditAction('LOGIN'), 'Login');
    expect(humanizeAuditAction(''), '');
  });
}
