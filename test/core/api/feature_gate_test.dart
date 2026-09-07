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
          message: () => 'Diese Funktion ist nicht aktiviert.',
        ),
        isTrue,
        reason: path,
      );
    }
  });

  test('the bare collection paths count too — they are what a list calls', () {
    // The server gates `/api/v1/time` as well as everything under it, because
    // `GET /api/v1/time?from=…` is the entry list and dio keeps the query out
    // of the path. Recognising only `/api/v1/time/` would miss the one request
    // most likely to be the first thing a screen makes.
    for (final path in kFlagGatedRoutePrefixes) {
      expect(
        isFeatureDisabledResponse(path: path, status: 404),
        isTrue,
        reason: path,
      );
    }
  });

  test('a query string does not hide the route', () {
    expect(
      isFeatureDisabledResponse(
        path: '/api/v1/time?from=2026-09-01&to=2026-09-07',
        status: 404,
      ),
      isTrue,
    );
  });

  test('the prefixes are the ones the server gates, spelled its way', () {
    // Mirrors AdvancedTimeTrackingGate.GATED_PATTERNS in hinata-server. If that
    // list gains a prefix, this test is the one that should be failing here.
    expect(kFlagGatedRoutePrefixes, const [
      '/api/v1/time',
      '/api/v1/me/timer',
      '/api/v1/availability',
      '/api/v1/billing',
      '/api/v1/me/calendar-subscriptions',
    ]);
    // Written without a trailing slash, so the boundary is a decision this file
    // makes rather than an accident of how the strings were typed.
    for (final prefix in kFlagGatedRoutePrefixes) {
      expect(prefix.endsWith('/'), isFalse, reason: prefix);
    }
  });

  test('an ordinary dead link stays an ordinary dead link', () {
    expect(
      isFeatureDisabledResponse(
        path: '/api/v1/issues/NOPE-1',
        status: 404,
        message: () => 'Issue not found',
      ),
      isFalse,
    );
  });

  test('the timesheet is not part of the module — it is always there', () {
    expect(
      isFeatureDisabledResponse(path: '/api/v1/timesheet', status: 404),
      isFalse,
    );
    // The same trap one level down: a path that merely starts with the letters.
    expect(
      isFeatureDisabledResponse(path: '/api/v1/timesheets/2026', status: 404),
      isFalse,
    );
  });

  test('a prefix buried inside a value is not a route', () {
    // A filter or a search term serialised into the path must not turn an
    // unrelated 404 into "the module is off" and send us re-reading /meta.
    expect(
      isFeatureDisabledResponse(
        path: '/api/v1/search/%2Fapi%2Fv1%2Fbilling',
        status: 404,
      ),
      isFalse,
    );
    expect(
      isFeatureDisabledResponse(
        path: '/api/v1/issues/api/v1/time',
        status: 404,
      ),
      isFalse,
    );
  });

  test('only 404 counts — 403 is a permission problem, not a flag', () {
    expect(
      isFeatureDisabledResponse(path: '/api/v1/time/entries', status: 403),
      isFalse,
    );
  });

  test('the body is not read unless the status could mean it', () {
    // Reading it can mean decoding a byte body, and for a timeout or a 500 the
    // answer is already no.
    var read = 0;
    isFeatureDisabledResponse(
      path: '/api/v1/issues/1',
      status: 500,
      message: () {
        read++;
        return null;
      },
    );
    expect(read, 0);
  });

  test('the raw code is honoured wherever it turns up', () {
    expect(
      isFeatureDisabledResponse(
        path: '/api/v1/somewhere/else',
        status: 404,
        message: () => kFeatureDisabledCode,
      ),
      isTrue,
    );
  });
}
