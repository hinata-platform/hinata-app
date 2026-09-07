import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/feature_gate.dart';

/// "Switched off" and "not found" arrive as the same status code, and only one
/// of them is worth reacting to. The server localizes its error messages, so the
/// route is the signal that actually survives the wire; the code is matched as
/// well because a server whose message bundle is missing the key falls back to
/// emitting the key itself.
void main() {
  test('a 404 on an extended route means the module is switched off', () {
    for (final path in const [
      '/api/v1/time/entries',
      '/api/v1/me/timer',
      '/api/v1/availability/2026-09',
      '/api/v1/billing/invoices',
      '/api/v1/me/calendar-subscriptions',
    ]) {
      expect(
        isFeatureDisabledResponse(
          path: path,
          status: 404,
          // What a live server actually sends: a localized sentence.
          message: 'Diese Funktion ist nicht aktiviert.',
        ),
        isTrue,
        reason: path,
      );
    }
  });

  test('an ordinary dead link stays an ordinary dead link', () {
    expect(
      isFeatureDisabledResponse(
        path: '/api/v1/issues/NOPE-1',
        status: 404,
        message: 'Issue not found',
      ),
      isFalse,
    );
  });

  test('the timesheet is not part of the module — it is always there', () {
    expect(
      isFeatureDisabledResponse(path: '/api/v1/timesheet', status: 404),
      isFalse,
    );
  });

  test('only 404 counts — 403 is a permission problem, not a flag', () {
    expect(
      isFeatureDisabledResponse(path: '/api/v1/time/entries', status: 403),
      isFalse,
    );
  });

  test('the raw code is honoured wherever it turns up', () {
    expect(
      isFeatureDisabledResponse(
        path: '/api/v1/somewhere/else',
        status: 404,
        message: kFeatureDisabledCode,
      ),
      isTrue,
    );
  });
}
