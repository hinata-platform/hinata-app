import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/admin/policy_controls.dart';
import 'package:hinata/features/admin/sections/admin_time_tracking_section.dart';

/// Two things in this section are not decoration.
///
/// Every policy that makes one person's working time legible to another carries
/// the co-determination note (§ 87 Abs. 1 Nr. 6 BetrVG / LPVG) at the switch
/// itself — that is a legal requirement of the epic, not a nicety, and it is
/// the kind of thing that quietly disappears when somebody reorganises a card.
///
/// And every policy can be handed back to the operator's environment. Absent is
/// a real state, distinct from off: it is how a fleet of servers keeps one
/// answer in `HINATA_*` instead of copying it into every database. If that is
/// not reachable from this screen, the only way back is editing Mongo by hand.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  /// The policies whose default must be off and which must carry the note.
  /// Named by their title key, which is what a widget test can see.
  const monitoring = {
    'admin.timeTracking.leadsSeeMemberEntriesTitle',
    'admin.timeTracking.approvalsTitle',
    'admin.timeTracking.workloadReportsTitle',
    'admin.timeTracking.alertsTitle',
    'admin.timeTracking.targetRemindersTitle',
    'admin.timeTracking.arbzgHintsTitle',
    'admin.timeTracking.billingEnabledTitle',
  };

  Widget host(
    Map<String, dynamic> settings, {
    double width = 900,
    ThemeData? theme,
  }) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: AdminTimeTrackingSection(settings: settings),
          ),
        ),
      ),
    ),
  );

  Finder policy(String titleKey) => find.ancestor(
    of: find.text(titleKey),
    matching: find.byType(PolicySwitch),
  );

  group('co-determination', () {
    testWidgets('the note sits at every monitoring-capable policy', (
      tester,
    ) async {
      await tester.pumpWidget(host(<String, dynamic>{}));
      await tester.pumpAndSettle();

      final flagged = tester
          .widgetList<PolicySwitch>(find.byType(PolicySwitch))
          .where((p) => p.monitoring)
          .map((p) => p.title)
          .toSet();
      expect(flagged, monitoring);
      expect(
        find.byType(CodeterminationNote),
        findsNWidgets(monitoring.length),
      );
    });

    testWidgets('and nowhere it would be noise', (tester) async {
      await tester.pumpWidget(host(<String, dynamic>{}));
      await tester.pumpAndSettle();

      // A required field or a rounding rule says nothing about a person.
      for (final title in const [
        'admin.timeTracking.requiredProjectTitle',
        'admin.timeTracking.defaultBillableTitle',
        'admin.timeTracking.limitTagAccessTitle',
        'admin.timeTracking.advancedTitle',
      ]) {
        expect(
          find.descendant(
            of: policy(title),
            matching: find.byType(CodeterminationNote),
          ),
          findsNothing,
          reason: title,
        );
      }
    });
  });

  group('the environment default', () {
    testWidgets('an unset policy shows no switch — we do not know the value', (
      tester,
    ) async {
      await tester.pumpWidget(host(<String, dynamic>{}));
      await tester.pumpAndSettle();

      final unset = policy('admin.timeTracking.advancedTitle');
      expect(
        find.descendant(of: unset, matching: find.byType(HiveSwitch)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: unset,
          matching: find.text('admin.timeTracking.envDefault'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping the badge commits an explicit value', (tester) async {
      final settings = <String, dynamic>{};
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final badge = find.descendant(
        of: policy('admin.timeTracking.advancedTitle'),
        matching: find.text('admin.timeTracking.envDefault'),
      );
      await tester.ensureVisible(badge);
      await tester.tap(badge);
      await tester.pumpAndSettle();

      final tt = settings['timeTracking'] as Map<String, dynamic>;
      expect(tt.containsKey('advancedEnabled'), isTrue);
      expect(tt['advancedEnabled'], isFalse);
      // Now that there is a value, the switch is honest and appears.
      expect(
        find.descendant(
          of: policy('admin.timeTracking.advancedTitle'),
          matching: find.byType(HiveSwitch),
        ),
        findsOneWidget,
      );
    });

    testWidgets('"use env default" writes null, not false', (tester) async {
      final settings = <String, dynamic>{
        'timeTracking': <String, dynamic>{'advancedEnabled': true},
      };
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final reset = find.descendant(
        of: policy('admin.timeTracking.advancedTitle'),
        matching: find.byType(EnvDefaultAction),
      );
      await tester.ensureVisible(reset);
      await tester.tap(
        find.descendant(of: reset, matching: find.byType(TextButton)),
      );
      await tester.pumpAndSettle();

      final tt = settings['timeTracking'] as Map<String, dynamic>;
      // The key stays, carrying null: the server tells "inherit" from "off" by
      // the value, and a dropped key would be a third, unintended meaning.
      expect(tt.containsKey('advancedEnabled'), isTrue);
      expect(tt['advancedEnabled'], isNull);
    });

    testWidgets('and it is offered on every policy switch that has a value', (
      tester,
    ) async {
      // Nine of them, all set: every one must offer the way back.
      final settings = <String, dynamic>{
        'timeTracking': <String, dynamic>{
          'advancedEnabled': true,
          'limitTagAccess': false,
          'defaultBillable': true,
          'icsImportEnabled': false,
          'leadsSeeMemberEntries': false,
          'approvalsEnabled': false,
          'workloadReportsEnabled': false,
          'alertsEnabled': false,
          'targetRemindersEnabled': false,
          'arbzgHintsEnabled': false,
          'billingEnabled': false,
          'requiredFields': <String, dynamic>{
            'project': true,
            'issue': false,
            'description': true,
            'tag': false,
          },
        },
      };
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final switches = find.byType(PolicySwitch);
      expect(
        find.descendant(of: switches, matching: find.byType(EnvDefaultAction)),
        findsNWidgets(tester.widgetList(switches).length),
      );
    });
  });

  group('the draft', () {
    testWidgets('toggling writes an explicit boolean', (tester) async {
      final settings = <String, dynamic>{
        'timeTracking': <String, dynamic>{'leadsSeeMemberEntries': false},
      };
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final toggle = find.descendant(
        of: policy('admin.timeTracking.leadsSeeMemberEntriesTitle'),
        matching: find.byType(HiveSwitch),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(
        (settings['timeTracking'] as Map)['leadsSeeMemberEntries'],
        isTrue,
      );
    });

    testWidgets('a nested group is not invented before it is touched', (
      tester,
    ) async {
      // An empty `requiredFields: {}` is not the same message as an absent one,
      // so simply opening the section must not send it.
      final settings = <String, dynamic>{};
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final tt = settings['timeTracking'] as Map<String, dynamic>;
      expect(tt.containsKey('requiredFields'), isFalse);
      expect(tt.containsKey('rounding'), isFalse);
      expect(tt.containsKey('approvalPeriod'), isFalse);
      expect(tt.containsKey('retention'), isFalse);
    });

    testWidgets('and is created on the first edit inside it', (tester) async {
      final settings = <String, dynamic>{};
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final badge = find.descendant(
        of: policy('admin.timeTracking.requiredProjectTitle'),
        matching: find.text('admin.timeTracking.envDefault'),
      );
      await tester.ensureVisible(badge);
      await tester.tap(badge);
      await tester.pumpAndSettle();

      final tt = settings['timeTracking'] as Map<String, dynamic>;
      expect(tt['requiredFields'], isA<Map<String, dynamic>>());
      expect((tt['requiredFields'] as Map)['project'], isFalse);
    });

    testWidgets('a value the server sent survives an untouched visit', (
      tester,
    ) async {
      final settings = <String, dynamic>{
        'timeTracking': <String, dynamic>{
          'currency': 'CHF',
          'rounding': <String, dynamic>{'mode': 'NEAREST', 'increment': 15},
        },
      };
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final tt = settings['timeTracking'] as Map<String, dynamic>;
      expect(tt['currency'], 'CHF');
      expect((tt['rounding'] as Map)['increment'], 15);
    });
  });

  group('layout', () {
    for (final width in <double>[320, 420, 900, 1200]) {
      testWidgets('renders without overflow at ${width}px', (tester) async {
        await tester.pumpWidget(host(<String, dynamic>{}, width: width));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reads on a dark page too', (tester) async {
      // A mutable draft, like every other test here: the section writes the
      // operator's edits straight into the map it was handed.
      await tester.pumpWidget(
        host(<String, dynamic>{}, theme: ThemeData.dark()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
