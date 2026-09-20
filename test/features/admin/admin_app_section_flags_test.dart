import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart' show PlatformFlags;
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/admin/sections/admin_app_section.dart';

/// The Platform section speaks about a module it does not own.
///
/// `advanced_time_tracking` is derived from the time-tracking module's own
/// settings, so this section may only point at the place that owns it and never
/// offer a switch of its own — two switches for one setting is a race whose
/// loser is whichever screen was saved last. Project templates are the other
/// way round: this section *does* own them, and writes a stored override rather
/// than a raw flag.
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

      // The section's own switches are here — the platform toggles it owns and
      // the auth ones — but nothing beside the time-tracking row: that row
      // reports a state the server derives elsewhere, and a switch next to it
      // would write where nothing reads.
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

      expect(find.text('admin.stateOn'), findsOneWidget);
      expect(find.text('admin.stateOff'), findsNothing);
    });

    testWidgets('falls back to what the environment resolves to', (
      tester,
    ) async {
      // The stored field is empty on every instance that has never saved the
      // section — including one an operator switched on through
      // HINATA_TIME_TRACKING_ADVANCED_ENABLED. Reading only the stored value
      // showed "off" there, next to a module that was running.
      await tester.pumpWidget(
        host(<String, dynamic>{
          'timeTracking': <String, dynamic>{
            'effective': <String, dynamic>{'advancedEnabled': true},
          },
        }, onOpenTimeTracking: () {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('admin.stateOn'), findsOneWidget);
    });

    testWidgets('says so when nothing anywhere has decided', (tester) async {
      // Neither on nor off: an older server sends no effective block, and
      // guessing "off" would be a claim this screen cannot support.
      await tester.pumpWidget(
        host(<String, dynamic>{}, onOpenTimeTracking: () {}),
      );
      await tester.pumpAndSettle();

      expect(find.text('admin.envDefault'), findsOneWidget);
      expect(find.text('admin.stateOff'), findsNothing);
    });
  });

  group('the project-template switch', () {
    testWidgets('writes the stored override, not a raw flag', (tester) async {
      // Seeded with an explicit false, because absent renders the env badge
      // rather than a switch — see the case below, which is the point of it.
      final settings = <String, dynamic>{
        'projectTemplates': <String, dynamic>{'enabled': false},
      };
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final toggle = find.descendant(
        of: find.byKey(const ValueKey('projectTemplatesSwitch')),
        matching: find.byType(HiveSwitch),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        (settings['projectTemplates'] as Map<String, dynamic>)['enabled'],
        isTrue,
      );
      // And never as a free-form flag: the server derives the published flag
      // from the block above, so a row of that name would flip nothing.
      final flags = (settings['app'] as Map<String, dynamic>?)?['featureFlags'];
      expect(
        (flags as Map<String, dynamic>?)?.containsKey(
              PlatformFlags.projectTemplates,
            ) ??
            false,
        isFalse,
      );
    });

    testWidgets('absent means the environment decides', (tester) async {
      // Not "off": an operator can run a whole fleet from
      // HINATA_PROJECT_TEMPLATES_ENABLED, and a screen claiming "off" there
      // would be wrong about a module that is running.
      await tester.pumpWidget(host(<String, dynamic>{}));
      await tester.pumpAndSettle();

      expect(find.text('admin.envDefault'), findsWidgets);
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
