/// Durations used to be the other place the app always spoke English — `2h
/// 30m` on every board card, timeline row and timesheet cell, in every
/// language. This pumps the *real* message bundle, so it fails if a `time.fmt`
/// key goes missing or a form stops interpolating.
///
/// Everything lives in one `testWidgets` on purpose: the asset-backed i18next
/// delegate only resolves in the first widget test of a file, so a second one
/// would render an empty tree and assert nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/i18n/i18n.dart';
import 'package:hinata/core/widgets/hive_widgets.dart';

void main() {
  testWidgets('durations speak the app language', (tester) async {
    Future<String?> label(int? minutes, {required String locale}) async {
      String? text;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('$locale-$minutes'),
          locale: Locale(locale),
          supportedLocales: I18n.supportedLocales,
          localizationsDelegates: I18n.delegates(),
          home: Builder(
            builder: (context) {
              text = fmtDuration(context, minutes);
              return const SizedBox();
            },
          ),
        ),
      );
      // The bundle comes from a real asset: let the I/O run, then give the
      // delegate the timed frame on which it hands its translations down.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      return text;
    }

    // ── German ──
    expect(await label(150, locale: 'de'), '2 h 30 min');
    expect(await label(120, locale: 'de'), '2 h');
    expect(await label(45, locale: 'de'), '45 min');
    expect(await label(0, locale: 'de'), '0 min');
    expect(
      await label(null, locale: 'de'),
      '—',
      reason: 'no value is a dash, never a zero',
    );

    // ── English ──
    expect(await label(150, locale: 'en'), '2h 30m');
    expect(await label(60, locale: 'en'), '1h');
    expect(await label(5, locale: 'en'), '5m');

    // ── A language with its own units, not a Latin abbreviation ──
    expect(await label(150, locale: 'ja'), '2 時間 30 分');
    expect(await label(150, locale: 'ru'), '2 ч 30 мин');
  });
}
