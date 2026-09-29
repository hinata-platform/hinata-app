import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/repositories/org_settings_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/organization/time_tracking/time_tracking_section.dart';
import 'package:hinata/features/organization/org_deadline_basis_card.dart';
import 'package:hinata/features/organization/org_link_card.dart';
import 'package:hinata/features/organization/organization_screen.dart';

import 'organization_test_support.dart';

/// The Organisation page (HIN-129): the time-tracking settings that left the
/// admin area, and the deadline basis while project templates are on.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  Widget host(
    FakeOrgSettingsRepository repository, {
    bool projectTemplates = true,
    double width = 1100,
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
            body: Center(
              child: SizedBox(width: width, child: const OrganizationScreen()),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('loads and shows the time-tracking settings', (tester) async {
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
    await tester.pumpWidget(host(FakeOrgSettingsRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(OrgDeadlineBasisCard), findsOneWidget);
    // Nothing stored: the page says the platform's default applies.
    expect(find.text('org.deadlines.followsPlatform'), findsOneWidget);
    expect(find.text('org.deadlines.usePlatform'), findsNothing);
  });

  testWidgets('and not while they are off', (tester) async {
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
    await tester.pumpWidget(
      host(FakeOrgSettingsRepository(failWith: 'error.org.adminOnly')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HiveEmptyState), findsOneWidget);
    expect(find.text('error.org.adminOnly'), findsOneWidget);
    expect(find.text('common.retry'), findsOneWidget);
  });

  for (final width in <double>[320, 900]) {
    testWidgets('renders without overflow at ${width}px', (tester) async {
      await tester.pumpWidget(host(FakeOrgSettingsRepository(), width: width));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
