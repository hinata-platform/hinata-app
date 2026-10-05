import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/account/calendar_subscriptions_cubit.dart';
import 'package:hinata/features/account/calendar_subscriptions_section.dart';

import '../../support/recording_fake.dart';
import '../time/fake_time_policy_cubit.dart';

/// Settings → Calendar subscriptions (HIN-94): what the list says empty,
/// filled and failing, and that it is not there at all while the organisation
/// has the import switched off.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  CalendarSubscription subscription({
    String id = 's1',
    CalendarSubscriptionStatus status = CalendarSubscriptionStatus.ok,
    String? lastErrorMessage,
    List<CalendarTakeoverSkip> skips = const [],
  }) => CalendarSubscription(
    id: id,
    name: 'Work $id',
    color: '#4F7DD9',
    hostMasked: 'calendar.google.com/…',
    status: status,
    lastErrorMessage: lastErrorMessage,
    lastFetchedAt: DateTime(2026, 10, 5, 9, 30),
    eventCount: 12,
    skips: skips,
  );

  Future<FakeTimeRepository> pump(
    WidgetTester tester, {
    bool importEnabled = true,
    List<CalendarSubscription>? items,
    Object? failure,
  }) async {
    final time = FakeTimeRepository();
    if (failure != null) {
      time.fail(#calendarSubscriptions, failure);
    } else {
      time.answer<List<CalendarSubscription>>(
        #calendarSubscriptions,
        items ?? const [],
      );
    }
    final policy = FakeTimePolicyCubit(
      TimePolicySnapshot(icsImportEnabled: importEnabled),
      time,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepositoryProvider<TimeRepository>.value(
              value: time,
              child: BlocProvider<TimePolicyCubit>.value(
                value: policy,
                child: const CalendarSubscriptionsSlot(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return time;
  }

  testWidgets('with the import off the section is not there and nothing is '
      'asked', (tester) async {
    final time = await pump(tester, importEnabled: false);

    expect(find.text('calendarSubscriptions.title'), findsNothing);
    expect(time.calls, isEmpty);
  });

  testWidgets('empty: a sentence about what to add, and the add button', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('calendarSubscriptions.title'), findsOneWidget);
    expect(find.text('calendarSubscriptions.empty.title'), findsOneWidget);
    expect(find.text('calendarSubscriptions.add'), findsOneWidget);
  });

  testWidgets('filled: name, masked host and how the last read went', (
    tester,
  ) async {
    await pump(tester, items: [subscription()]);

    expect(find.text('Work s1'), findsOneWidget);
    expect(find.text('calendar.google.com/…'), findsOneWidget);
    expect(
      find.textContaining('calendarSubscriptions.status.ok'),
      findsOneWidget,
    );
    expect(find.text('calendarSubscriptions.empty.title'), findsNothing);
  });

  testWidgets('a failed read shows the server\'s sentence, and skipped '
      'takeovers say why', (tester) async {
    await pump(
      tester,
      items: [
        subscription(
          status: CalendarSubscriptionStatus.failed,
          lastErrorMessage: 'Redirects are not followed.',
          skips: const [
            CalendarTakeoverSkip(
              startsAt: null,
              messageKey: 'error.time.required.tag',
              message: 'A tag is required.',
            ),
          ],
        ),
      ],
    );

    expect(find.text('Redirects are not followed.'), findsOneWidget);
    expect(
      find.textContaining('calendarSubscriptions.skipped'),
      findsOneWidget,
    );
  });

  testWidgets('a list that could not be read offers to try again', (
    tester,
  ) async {
    await pump(tester, failure: ApiFailure('error.feature.disabled'));

    expect(find.text('error.feature.disabled'), findsOneWidget);
    expect(find.text('common.retry'), findsOneWidget);
  });

  testWidgets('at ten calendars the add button is off and says why', (
    tester,
  ) async {
    await pump(
      tester,
      items: [
        for (var i = 0; i < CalendarSubscriptionsCubit.limit; i++)
          subscription(id: 's$i'),
      ],
    );

    expect(find.text('calendarSubscriptions.limit'), findsOneWidget);
  });
}
