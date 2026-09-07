import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart' show PlatformFlags;
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/admin/sections/admin_app_section.dart';

/// The App section's raw flag editor writes whatever name is typed into it, and
/// a flag the server *derives* would sit there looking authoritative while
/// changing nothing. `advanced_time_tracking` is derived from the time-tracking
/// module's own settings, so this section may only point at the place that owns
/// it — and must refuse to create it by hand.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  Widget host(
    Map<String, dynamic> settings, {
    VoidCallback? onOpenTimeTracking,
    double width = 900,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: AdminAppSection(
              settings: settings,
              onOpenTimeTracking: onOpenTimeTracking,
            ),
          ),
        ),
      ),
    ),
  );

  Map<String, dynamic> flagsOf(Map<String, dynamic> settings) =>
      (settings['app'] as Map<String, dynamic>)['featureFlags']
          as Map<String, dynamic>;

  testWidgets('the derived flag cannot be typed in by hand', (tester) async {
    final settings = <String, dynamic>{};
    await tester.pumpWidget(host(settings));
    await tester.pumpAndSettle();

    final field = find.byType(TextField).last;
    await tester.ensureVisible(field);
    await tester.enterText(field, PlatformFlags.advancedTimeTracking);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      flagsOf(settings).containsKey(PlatformFlags.advancedTimeTracking),
      isFalse,
    );
  });

  testWidgets('and it never shows up twice in the raw editor', (tester) async {
    // Even when the server already reports it, the raw list leaves it out — the
    // described row above is the one place it is spoken about.
    final settings = <String, dynamic>{
      'app': <String, dynamic>{
        'featureFlags': <String, dynamic>{
          PlatformFlags.advancedTimeTracking: true,
          'something_else': true,
        },
      },
    };
    await tester.pumpWidget(host(settings));
    await tester.pumpAndSettle();

    expect(find.text('something_else'), findsOneWidget);
    expect(find.text(PlatformFlags.advancedTimeTracking), findsNothing);
  });

  group('the pointer row', () {
    testWidgets('opens the section that owns the setting', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        host(<String, dynamic>{}, onOpenTimeTracking: () => opened++),
      );
      await tester.pumpAndSettle();

      final row = find.text('admin.timeTracking.advancedTitle');
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(opened, 1);
    });

    testWidgets('and offers no switch of its own', (tester) async {
      await tester.pumpWidget(
        host(<String, dynamic>{}, onOpenTimeTracking: () {}),
      );
      await tester.pumpAndSettle();

      // Three real platform toggles (multi-assignee, e-mail reply) plus the
      // three auth switches — but nothing beside the time-tracking row, which
      // would write somewhere the server does not read.
      final switches = find.byType(HiveSwitch);
      expect(switches, findsWidgets);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('admin.timeTracking.advancedTitle'),
            matching: find.byType(Row),
          ),
          matching: find.byType(HiveSwitch),
        ),
        findsNothing,
      );
    });

    testWidgets('it shows the state the module section holds', (tester) async {
      await tester.pumpWidget(
        host(<String, dynamic>{
          'timeTracking': <String, dynamic>{'advancedEnabled': true},
        }, onOpenTimeTracking: () {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('admin.timeTracking.stateOn'), findsOneWidget);
      expect(find.text('admin.timeTracking.stateOff'), findsNothing);
    });

    testWidgets('and reads "off" when nothing is set', (tester) async {
      await tester.pumpWidget(
        host(<String, dynamic>{}, onOpenTimeTracking: () {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('admin.timeTracking.stateOff'), findsOneWidget);
    });
  });

  for (final width in <double>[320, 420, 900]) {
    testWidgets('lays out without overflow at ${width}px', (tester) async {
      await tester.pumpWidget(
        host(<String, dynamic>{}, onOpenTimeTracking: () {}, width: width),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
