// Signs the app in on a device, for the performance runs.
//
// A fresh install boots into the connect screen, so this walks the full flow
// (server URL, onboarding, login) and is skipped step by step when the app
// restores a persisted session. The connection comes in through
// --dart-define (HINATA_SERVER_URL, HINATA_USER, HINATA_PASSWORD) and is only
// needed when the device has no session yet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

const _serverUrl = String.fromEnvironment('HINATA_SERVER_URL');
const _user = String.fromEnvironment('HINATA_USER');
const _password = String.fromEnvironment('HINATA_PASSWORD');

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final steps = duration.inMilliseconds ~/ 100;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] matches or [timeout] elapses. Returns whether found.
Future<bool> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final steps = timeout.inMilliseconds ~/ 250;
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (tester.any(finder)) return true;
  }
  return false;
}

/// Replaces the complete value of a [TextFormField], including any prefill.
///
/// On a device the platform IME can retain ownership of the input connection,
/// which makes `enterText`/`TestTextInput` unreliable for this prefilled URL
/// field. Updating the controller is deterministic; the `TextFormField`
/// observes the controller value before the form is submitted.
Future<void> _replaceFieldText(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await tester.tap(field, warnIfMissed: true);
  await tester.pump(const Duration(milliseconds: 300));
  final controller = tester.widget<TextFormField>(field).controller;
  if (controller == null) {
    throw StateError('Expected the test field to have a TextEditingController');
  }
  controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

/// Walks the app from launch to the shell, with the bell in the top bar.
Future<void> ensureSignedIn(WidgetTester tester) async {
  await _pumpFor(tester, const Duration(seconds: 3));

  final bell = find.byIcon(LucideIcons.bell);
  final connectField = find.byIcon(LucideIcons.server);
  final loginUserField = find.byIcon(LucideIcons.user);

  // ── Step 1: connect screen (fresh install only) ───────────────────────
  if (!tester.any(bell) && !tester.any(loginUserField)) {
    if (await _waitFor(
      tester,
      connectField,
      timeout: const Duration(seconds: 10),
    )) {
      debugPrint('PERF-TEST step: connect screen');
      expect(
        _serverUrl,
        isNotEmpty,
        reason:
            'No session on device and HINATA_SERVER_URL not set — '
            'pass the connection via --dart-define.',
      );
      // The connect field is prefilled with `https://`; replace its value
      // directly because the device IME may keep the test channel detached.
      await _replaceFieldText(
        tester,
        find.byType(TextFormField).first,
        _serverUrl,
      );
      await tester.tap(find.byType(FilledButton).first);
      await _pumpFor(tester, const Duration(seconds: 3));
    }
  }

  // ── Step 2: onboarding — keep tapping the CTA until it's gone ────────
  final cta = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_CtaButton',
  );
  for (var i = 0; i < 6 && tester.any(cta); i++) {
    debugPrint('PERF-TEST step: onboarding cta tap ${i + 1}');
    await tester.tap(cta, warnIfMissed: true);
    await _pumpFor(tester, const Duration(seconds: 1));
  }

  // ── Step 3: login (skipped when a session was restored) ──────────────
  if (!tester.any(bell) &&
      await _waitFor(
        tester,
        loginUserField,
        timeout: const Duration(seconds: 10),
      )) {
    debugPrint('PERF-TEST step: login screen');
    final fields = find.byType(TextFormField);
    await _replaceFieldText(tester, fields.at(0), _user);
    await _replaceFieldText(tester, fields.at(1), _password);
    await tester.tap(find.byType(FilledButton).first);
    await _pumpFor(tester, const Duration(seconds: 4));
  }

  // ── Step 4: wait for the shell (bell in the top bar) ─────────────────
  final reachedShell = await _waitFor(
    tester,
    bell,
    timeout: const Duration(seconds: 10),
  );
  if (!reachedShell) {
    // Diagnostic: dump visible texts so the failing screen is identifiable.
    final texts = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .take(25)
        .toList();
    debugPrint('PERF-TEST visible texts: $texts');
  }
  expect(
    reachedShell,
    isTrue,
    reason: 'bell trigger not found — login flow did not reach the shell',
  );
}
