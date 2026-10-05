import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/repositories/org_settings_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/core/widgets/hive_widgets.dart' show HiveSwitch;
import 'package:hinata/features/organization/time_tracking/time_tracking_section.dart';
import 'package:hinata/features/organization/org_deadline_basis_card.dart';
import 'package:hinata/features/organization/org_link_card.dart';
import 'package:hinata/features/organization/organization_cubit.dart';
import 'package:hinata/features/organization/organization_screen.dart';

import 'organization_test_support.dart';

/// The Organisation page (HIN-129): the time-tracking settings that left the
/// admin area, and the deadline basis while project templates are on.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  /// The window the page lays itself out for: a phone unless a test says
  /// otherwise, since the breakpoint reads the window, not the box.
  void window(WidgetTester tester, Size size) {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const phone = Size(400, 900);
  const desktop = Size(1440, 900);

  Widget host(
    FakeOrgSettingsRepository repository, {
    bool projectTemplates = true,
    String? initialSection,
  }) {
    final time = FakeTimeRepository();
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<OrgSettingsRepository>.value(value: repository),
        RepositoryProvider<TimeRepository>.value(value: time),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AppConfigBloc>.value(
            value: FakeOrgAppConfig(projectTemplates: projectTemplates),
          ),
          BlocProvider<TimePolicyCubit>(create: (_) => TimePolicyCubit(time)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OrganizationScreen(initialSection: initialSection),
          ),
        ),
      ),
    );
  }

  testWidgets('loads and shows the time-tracking settings', (tester) async {
    window(tester, phone);
    await tester.pumpWidget(host(FakeOrgSettingsRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(OrgTimeTrackingSection), findsOneWidget);
    expect(find.text('admin.timeTracking.moduleTitle'), findsOneWidget);
    // The page lays the section's cards out, its own above them; the
    // time-tracking note stands over the time-tracking cards only.
    expect(find.text('org.audit.title'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('org.audit.title')).dy,
      lessThan(tester.getTopLeft(find.text('admin.timeTracking.hint')).dy),
    );
    expect(find.byType(OrgLinkCard), findsNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the deadline card while project templates are on', (
    tester,
  ) async {
    window(tester, phone);
    await tester.pumpWidget(host(FakeOrgSettingsRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(OrgDeadlineBasisCard), findsOneWidget);
    // Nothing stored: the page says the platform's default applies.
    expect(find.text('org.deadlines.followsPlatform'), findsOneWidget);
    expect(find.text('org.deadlines.usePlatform'), findsNothing);
  });

  testWidgets('and not while they are off', (tester) async {
    window(tester, phone);
    await tester.pumpWidget(
      host(FakeOrgSettingsRepository(), projectTemplates: false),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OrgDeadlineBasisCard), findsNothing);
    expect(find.byType(OrgTimeTrackingSection), findsOneWidget);
  });

  testWidgets('choosing a basis makes it the organisation\'s own', (
    tester,
  ) async {
    window(tester, phone);
    await tester.pumpWidget(host(FakeOrgSettingsRepository()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('projects.deadlineBasis.working'));
    await tester.tap(find.text('projects.deadlineBasis.working'));
    await tester.pumpAndSettle();

    expect(find.text('org.deadlines.ownChoice'), findsOneWidget);
    // And the way back to the platform is offered.
    expect(find.text('org.deadlines.usePlatform'), findsOneWidget);
  });

  testWidgets('a stored basis can be handed back to the platform', (
    tester,
  ) async {
    window(tester, phone);
    await tester.pumpWidget(
      host(FakeOrgSettingsRepository(defaultDeadlineBasis: 'WORKING')),
    );
    await tester.pumpAndSettle();

    final usePlatform = find.byKey(const ValueKey('orgDeadlineUsePlatform'));
    await tester.ensureVisible(usePlatform);
    await tester.tap(usePlatform);
    await tester.pumpAndSettle();

    // The platform's value is not known while the organisation had its own.
    expect(find.text('org.deadlines.followsPlatformUnknown'), findsOneWidget);
  });

  testWidgets('a refused load says why and offers a retry', (tester) async {
    window(tester, phone);
    await tester.pumpWidget(
      host(FakeOrgSettingsRepository(failWith: 'error.org.adminOnly')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HiveEmptyState), findsOneWidget);
    expect(find.text('error.org.adminOnly'), findsOneWidget);
    expect(find.text('common.retry'), findsOneWidget);
  });

  for (final width in <double>[320, 900, 1440]) {
    testWidgets('renders without overflow at ${width}px', (tester) async {
      window(tester, Size(width, 900));
      await tester.pumpWidget(host(FakeOrgSettingsRepository()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  group('on a wide window', () {
    testWidgets('shows one section, the module first', (tester) async {
      window(tester, desktop);
      await tester.pumpWidget(host(FakeOrgSettingsRepository()));
      await tester.pumpAndSettle();

      // The module's switch is there; the cards of the other sections are not.
      expect(find.text('admin.timeTracking.advancedTitle'), findsOneWidget);
      expect(
        find.text('admin.timeTracking.requiredProjectTitle'),
        findsNothing,
      );
      expect(find.byType(OrgDeadlineBasisCard), findsNothing);
      expect(find.byType(OrgLinkCard), findsNothing);
      // The introduction stands once, in the rail's head.
      expect(find.text('org.subtitle'), findsOneWidget);
      expect(find.text('admin.timeTracking.hint'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rail entry opens its section instead', (tester) async {
      window(tester, desktop);
      await tester.pumpWidget(host(FakeOrgSettingsRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('admin.timeTracking.captureTitle'));
      await tester.pumpAndSettle();
      expect(
        find.text('admin.timeTracking.requiredProjectTitle'),
        findsOneWidget,
      );
      expect(find.text('admin.timeTracking.advancedTitle'), findsNothing);

      await tester.tap(find.text('org.nav.deadlines'));
      await tester.pumpAndSettle();
      expect(find.byType(OrgDeadlineBasisCard), findsOneWidget);
      expect(
        find.text('admin.timeTracking.requiredProjectTitle'),
        findsNothing,
      );
      // Not a time-tracking section: the note about policies stays away.
      expect(find.text('admin.timeTracking.hint'), findsNothing);
    });

    testWidgets('a change survives a trip to another section and is saved', (
      tester,
    ) async {
      window(tester, desktop);
      final repository = FakeOrgSettingsRepository();
      await tester.pumpWidget(host(repository));
      await tester.pumpAndSettle();

      // Nothing stored: the module offers its environment default; tapping it
      // makes the value the organisation's own.
      await tester.tap(find.textContaining('admin.timeTracking.envDefault'));
      await tester.pumpAndSettle();
      expect(find.byType(HiveSwitch), findsOneWidget);

      await tester.tap(find.text('admin.timeTracking.captureTitle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('admin.timeTracking.moduleTitle'));
      await tester.pumpAndSettle();
      expect(find.byType(HiveSwitch), findsOneWidget);

      // What the bar's Save does; the bar itself belongs to the shell.
      await tester
          .element(find.byType(OrganizationView))
          .read<OrganizationCubit>()
          .save(templates: true);
      await tester.pumpAndSettle();
      expect(repository.updates, hasLength(1));
      final sent = repository.updates.single.timeTracking!;
      expect(sent.containsKey('advancedEnabled'), isTrue);
      expect(sent['advancedEnabled'], isFalse);
    });

    testWidgets("the module's own sections are listed only while it is on", (
      tester,
    ) async {
      window(tester, desktop);
      await tester.pumpWidget(host(FakeOrgSettingsRepository()));
      await tester.pumpAndSettle();
      expect(find.text('org.nav.corrections'), findsNothing);
      expect(find.text('admin.timeTracking.tagsTitle'), findsNothing);
      expect(find.text('availability.admin.cardTitle'), findsNothing);

      // A fresh page, so the page loads again from a server where it is on.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(FakeOrgSettingsRepository(advancedEnabled: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('org.nav.corrections'), findsOneWidget);
      expect(find.text('admin.timeTracking.tagsTitle'), findsOneWidget);
      expect(find.text('availability.admin.cardTitle'), findsOneWidget);
    });

    testWidgets('?section= opens that section', (tester) async {
      window(tester, desktop);
      await tester.pumpWidget(
        host(FakeOrgSettingsRepository(), initialSection: 'capture'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('admin.timeTracking.requiredProjectTitle'),
        findsOneWidget,
      );
      expect(find.text('admin.timeTracking.advancedTitle'), findsNothing);
    });

    testWidgets('a section that went with the module gives way to the first', (
      tester,
    ) async {
      window(tester, desktop);
      await tester.pumpWidget(
        host(FakeOrgSettingsRepository(), initialSection: 'tags'),
      );
      await tester.pumpAndSettle();
      expect(find.text('admin.timeTracking.advancedTitle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('a phone still shows every card', (tester) async {
    window(tester, phone);
    await tester.pumpWidget(host(FakeOrgSettingsRepository()));
    await tester.pumpAndSettle();

    expect(find.text('admin.timeTracking.advancedTitle'), findsOneWidget);
    expect(
      find.text('admin.timeTracking.requiredProjectTitle'),
      findsOneWidget,
    );
    expect(find.byType(OrgDeadlineBasisCard), findsOneWidget);
    expect(find.byType(OrgLinkCard), findsOneWidget);
  });
}
