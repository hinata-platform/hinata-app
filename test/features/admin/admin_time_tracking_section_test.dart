import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/time_approval_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
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
    // The master switch first: turning it on is the introduction of the
    // facility itself — a running timer per person, a calendar view of their
    // day — which is what § 87 Abs. 1 Nr. 6 BetrVG co-determines *before* it
    // runs. Without it here the notes below would read as "and this one is
    // fine". ICS import belongs for a narrower reason: subscribed appointment
    // titles routinely carry other people's names.
    'admin.timeTracking.advancedTitle',
    'admin.timeTracking.icsImportTitle',
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
  }) => RepositoryProvider<TimeRepository>.value(
    // The tag catalogue card mounts itself as soon as the module is on, and it
    // reads the catalogue. An empty one is what a fresh instance has.
    value: _FakeTagRepository(),
    child: BlocProvider<TimePolicyCubit>(
      // So does the lock-exception card, and it reads the policy the way every
      // screen in the module does — the app provides this cubit once, globally.
      create: (context) => TimePolicyCubit(context.read<TimeRepository>()),
      child: MaterialApp(
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
      // Every switch given an explicit value must offer the way back to the
      // environment; the count is read off the tree below rather than asserted
      // here, because a policy added later must not need this comment edited.
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

  group('honesty about what is in force', () {
    testWidgets('every policy the server does not enforce yet says so', (
      tester,
    ) async {
      await tester.pumpWidget(host(<String, dynamic>{}));
      await tester.pumpAndSettle();

      // A screen that says "entries on this day can no longer be changed" while
      // nothing stops them is how an administrator freezes a payroll period,
      // sees a green toast, and finds out months later. So the note belongs on
      // exactly the policies that are still idle, and comes off the moment the
      // stage that enforces one lands.
      for (final title in const [
        // The request gate has read this since stage 2.
        'admin.timeTracking.advancedTitle',
        // Stage 6 (this one): the write gate refuses what these demand.
        'admin.timeTracking.limitTagAccessTitle',
        'admin.timeTracking.requiredProjectTitle',
      ]) {
        expect(
          find.descendant(
            of: policy(title),
            matching: find.byType(PendingNote),
          ),
          findsNothing,
          reason: title,
        );
      }
      for (final title in const [
        'admin.timeTracking.leadsSeeMemberEntriesTitle',
        'admin.timeTracking.arbzgHintsTitle',
      ]) {
        expect(
          find.descendant(
            of: policy(title),
            matching: find.byType(PendingNote),
          ),
          findsOneWidget,
          reason: title,
        );
      }
    });

    testWidgets('the badge names what the environment answers', (tester) async {
      // Without this the badge said only "Env-Default" — true, and useless: an
      // operator could not tell an instance that is on from one that is off
      // without reading the deployment's environment.
      await tester.pumpWidget(
        host(<String, dynamic>{
          'timeTracking': <String, dynamic>{
            'effective': <String, dynamic>{'advancedEnabled': true},
          },
        }),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: policy('admin.timeTracking.advancedTitle'),
          matching: find.textContaining('admin.stateOn'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('adopting the environment value does not change it', (
      tester,
    ) async {
      // The tap materialises the switch; it must not also flip the policy. On
      // a monitoring-capable switch, a tap that quietly turned something on
      // would be the worst possible reading of "make this visible".
      final settings = <String, dynamic>{
        'timeTracking': <String, dynamic>{
          'effective': <String, dynamic>{'advancedEnabled': true},
        },
      };
      await tester.pumpWidget(host(settings));
      await tester.pumpAndSettle();

      final badge = find.descendant(
        of: policy('admin.timeTracking.advancedTitle'),
        matching: find.textContaining('admin.timeTracking.envDefault'),
      );
      await tester.ensureVisible(badge);
      await tester.tap(badge);
      await tester.pumpAndSettle();

      expect(
        (settings['timeTracking'] as Map)['advancedEnabled'],
        isTrue,
        reason: 'the value in force was true, so adopting it must store true',
      );
    });

    testWidgets('rounding can be set back to none', (tester) async {
      // NONE is one of the four the server accepts and the one it starts on.
      // Leaving it out of the list meant an operator who once chose "round up"
      // could only go back to whatever the environment said — which on a fleet
      // configured for NEAREST is not "off".
      await tester.pumpWidget(
        host(<String, dynamic>{
          'timeTracking': <String, dynamic>{
            'rounding': <String, dynamic>{'mode': 'NONE'},
          },
        }),
      );
      await tester.pumpAndSettle();

      // Rendered as itself, not disguised as "the environment decides" — which
      // is what an unknown value used to look like, next to a reset button
      // offering to clear the value the field claimed was not there.
      expect(find.text('admin.timeTracking.roundingMode.none'), findsOneWidget);
    });
  });
}

class _FakeTagRepository implements TimeRepository {
  @override
  Future<PageResult<TimeTag>> tags({
    String? query,
    int page = 0,
    int size = 50,
    bool withUsage = false,
  }) async => (items: const <TimeTag>[], total: 0);

  /// The section now carries the lock-exception card and the period preview, and
  /// both read this repository. Answering empty rather than throwing, because
  /// what this file is about is the policy *controls* — a preview that refused to
  /// load would make every assertion below an assertion about an exception.
  @override
  Future<List<ApprovalPeriod>> approvalPeriods({
    required DateTime from,
    required DateTime to,
    String? projectId,
  }) async => const <ApprovalPeriod>[];

  @override
  Future<TimePolicySnapshot> policy() async => TimePolicySnapshot.none;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
