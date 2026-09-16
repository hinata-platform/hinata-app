import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/time_privacy_cubit.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/time_privacy_sheet.dart';

import 'fake_time_privacy_cubit.dart';

/// "Who sees my time data?" (HIN-89): the panel is computed from the policies,
/// never a fixed text, and the first-use notice opens once.
///
/// The rows render as i18n keys, which is the contract worth asserting: a panel
/// that picked the wrong sentence for a policy is exactly the failure that would
/// tell somebody something false about who reads their hours.
void main() {
  Future<void> showPanel(WidgetTester tester, TimeVisibility visibility) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TimeVisibilityPanel(visibility: visibility),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the panel follows the policies', () {
    testWidgets(
      'nothing switched on: totals only, nothing recorded, nothing deleted',
      (tester) async {
        await showPanel(
          tester,
          const TimeVisibility(foreignChangesRecorded: false),
        );

        // The two lines that are true on every instance.
        expect(find.text('time.privacy.row.self'), findsOneWidget);
        expect(find.text('time.privacy.row.admins'), findsOneWidget);
        expect(find.text('time.privacy.row.leadsTotals'), findsOneWidget);
        expect(find.text('time.privacy.row.leadsSee'), findsNothing);
        expect(find.text('time.privacy.row.approvals'), findsNothing);
        expect(find.text('time.privacy.row.arbzgHints'), findsNothing);
        expect(find.textContaining('time.privacy.row.lateEntry'), findsNothing);
        expect(find.text('time.privacy.row.timerNotRecorded'), findsOneWidget);
        expect(find.text('time.privacy.row.entryKept'), findsOneWidget);
      },
    );

    testWidgets('leads see entries and the Working Hours Act hints are on', (
      tester,
    ) async {
      await showPanel(
        tester,
        const TimeVisibility(leadsSeeEntries: true, arbzgHints: true),
      );

      expect(find.text('time.privacy.row.leadsSee'), findsOneWidget);
      expect(find.text('time.privacy.row.leadsTotals'), findsNothing);
      expect(find.text('time.privacy.row.arbzgHints'), findsOneWidget);
      expect(find.text('time.privacy.row.approvals'), findsNothing);
    });

    testWidgets('approvals, a late-entry hint and a retention period', (
      tester,
    ) async {
      await showPanel(
        tester,
        const TimeVisibility(
          approvalsEnabled: true,
          lateEntryHintDays: 7,
          entryRetentionMonths: 24,
          descriptionRetentionMonths: 6,
        ),
      );

      expect(find.text('time.privacy.row.approvals'), findsOneWidget);
      expect(find.textContaining('time.privacy.row.lateEntry'), findsOneWidget);
      expect(
        find.textContaining('time.privacy.row.entryRetention'),
        findsOneWidget,
      );
      expect(find.text('time.privacy.row.entryKept'), findsNothing);
      expect(
        find.textContaining('time.privacy.row.descriptionRetention'),
        findsOneWidget,
      );
    });

    testWidgets('an audit log that records the timer says so', (tester) async {
      await showPanel(
        tester,
        const TimeVisibility(
          leadsSeeEntries: true,
          approvalsEnabled: true,
          timerEventsRecorded: true,
          entryCreationRecorded: true,
          workloadReports: true,
          alerts: true,
          targetReminders: true,
        ),
      );

      expect(find.text('time.privacy.row.timerRecorded'), findsOneWidget);
      expect(find.text('time.privacy.row.timerNotRecorded'), findsNothing);
      expect(find.text('time.privacy.row.entryCreation'), findsOneWidget);
      expect(find.text('time.privacy.row.workloadReports'), findsOneWidget);
      expect(find.text('time.privacy.row.alerts'), findsOneWidget);
      expect(find.text('time.privacy.row.targetReminders'), findsOneWidget);
    });
  });

  group('the first-use notice', () {
    const unconfirmed = TimePrivacy(notice: '## Deine Arbeitszeit');

    Widget host(FakeTimePrivacyCubit cubit) =>
        BlocProvider<TimePrivacyCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    // Two views of the module opening one after the other.
                    TextButton(
                      onPressed: () => offerTimePrivacyNotice(context),
                      child: const Text('open list'),
                    ),
                    TextButton(
                      onPressed: () => offerTimePrivacyNotice(context),
                      child: const Text('open calendar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    testWidgets('opens once, and "Understood" records it', (tester) async {
      final cubit = FakeTimePrivacyCubit(
        _NoTimeRepository(),
        onLoad: unconfirmed,
      );
      await tester.pumpWidget(host(cubit));

      await tester.tap(find.text('open list'));
      await tester.pumpAndSettle();

      expect(find.text('time.privacy.understood'), findsOneWidget);
      expect(find.text('time.privacy.firstUseSubtitle'), findsOneWidget);
      expect(find.text('time.privacy.row.self'), findsOneWidget);

      await tester.tap(find.text('time.privacy.understood'));
      await tester.pumpAndSettle();

      expect(cubit.acknowledgements, 1);
      expect(find.text('time.privacy.understood'), findsNothing);
      expect(cubit.state!.acknowledged, isTrue);
    });

    testWidgets('closed without confirming, it does not follow the next view', (
      tester,
    ) async {
      final cubit = FakeTimePrivacyCubit(
        _NoTimeRepository(),
        onLoad: unconfirmed,
      );
      await tester.pumpWidget(host(cubit));

      await tester.tap(find.text('open list'));
      await tester.pumpAndSettle();
      expect(find.text('time.privacy.understood'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open calendar'));
      await tester.pumpAndSettle();

      expect(find.text('time.privacy.understood'), findsNothing);
      expect(cubit.acknowledgements, 0);
    });

    testWidgets('somebody who already confirmed is not asked again', (
      tester,
    ) async {
      final cubit = FakeTimePrivacyCubit(
        _NoTimeRepository(),
        privacy: TimePrivacy(
          notice: 'x',
          acknowledgedAt: DateTime.utc(2026, 9, 1),
        ),
      );
      await tester.pumpWidget(host(cubit));

      await tester.tap(find.text('open list'));
      await tester.pumpAndSettle();

      expect(find.text('time.privacy.understood'), findsNothing);
    });

    testWidgets('opened from the settings it has a close button instead', (
      tester,
    ) async {
      final cubit = FakeTimePrivacyCubit(
        _NoTimeRepository(),
        privacy: TimePrivacy(
          notice: 'x',
          acknowledgedAt: DateTime.utc(2026, 9, 1),
        ),
      );
      await tester.pumpWidget(
        BlocProvider<TimePrivacyCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showTimePrivacySheet(context),
                  child: const Text('settings'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('settings'));
      await tester.pumpAndSettle();

      expect(find.text('time.privacy.subtitle'), findsOneWidget);
      expect(find.text('time.privacy.understood'), findsNothing);
      expect(find.text('common.close'), findsOneWidget);
    });
  });

  group('a notice that cannot be read', () {
    testWidgets('says so and reads again on request instead of spinning', (
      tester,
    ) async {
      final repository = _FlakyPrivacyRepository();
      final cubit = TimePrivacyCubit(repository);
      addTearDown(cubit.close);
      await tester.pumpWidget(
        BlocProvider<TimePrivacyCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showTimePrivacySheet(context),
                  child: const Text('settings'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('settings'));
      await tester.pumpAndSettle();

      expect(find.text('time.privacy.loadFailed'), findsOneWidget);
      expect(find.text('time.privacy.row.self'), findsNothing);

      await tester.tap(find.text('common.retry'));
      await tester.pumpAndSettle();

      expect(find.text('time.privacy.loadFailed'), findsNothing);
      expect(find.text('time.privacy.row.self'), findsOneWidget);
      expect(repository.reads, 2);
    });
  });

  group('what the panel says about colleagues', () {
    testWidgets('other members of a project are named on every instance', (
      tester,
    ) async {
      await showPanel(tester, const TimeVisibility());

      // The hours on an issue are visible to its project, the person behind
      // them is not, and the panel says both on every instance.
      expect(find.text('time.privacy.row.members'), findsOneWidget);
    });
  });
}

class _NoTimeRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Fails the first read, as a connection that drops for a moment would.
class _FlakyPrivacyRepository implements TimeRepository {
  int reads = 0;

  @override
  Future<TimePrivacy> privacy() async {
    reads++;
    if (reads == 1) throw Exception('offline');
    return TimePrivacy(notice: 'x', acknowledgedAt: DateTime.utc(2026, 9, 1));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
