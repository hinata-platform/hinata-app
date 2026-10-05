import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/features/account/calendar_subscriptions_cubit.dart';

import '../../support/recording_fake.dart';

/// The calendar subscriptions cubit (HIN-94): it shows what the server
/// answered, and while a read runs it asks again until the read is over.
void main() {
  const running = CalendarSubscription(
    id: 's1',
    name: 'Work',
    color: '#4F7DD9',
    status: CalendarSubscriptionStatus.running,
  );
  const done = CalendarSubscription(
    id: 's1',
    name: 'Work',
    color: '#4F7DD9',
    status: CalendarSubscriptionStatus.ok,
    eventCount: 3,
  );

  blocTest<CalendarSubscriptionsCubit, CalendarSubscriptionsState>(
    'a running read is asked about again until it settles',
    build: () {
      final time = FakeTimeRepository();
      var reads = 0;
      time.answerWith(
        #calendarSubscriptions,
        (_) => Future.value(reads++ == 0 ? [running] : [done]),
      );
      return CalendarSubscriptionsCubit(
        time,
        pollEvery: const Duration(milliseconds: 10),
      );
    },
    act: (cubit) async {
      await cubit.load();
      await Future<void>.delayed(const Duration(milliseconds: 40));
    },
    verify: (cubit) {
      expect(cubit.state.items, [done]);
      expect(cubit.state.loading, isFalse);
    },
  );

  blocTest<CalendarSubscriptionsCubit, CalendarSubscriptionsState>(
    'a removed subscription leaves the list',
    build: () {
      final time = FakeTimeRepository()
        ..answer<List<CalendarSubscription>>(#calendarSubscriptions, [done])
        ..answer<void>(#deleteCalendarSubscription, null);
      return CalendarSubscriptionsCubit(time);
    },
    act: (cubit) async {
      await cubit.load();
      await cubit.delete('s1');
    },
    verify: (cubit) {
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.busy, isEmpty);
    },
  );
}
