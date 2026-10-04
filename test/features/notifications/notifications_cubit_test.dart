import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/content_models.dart';
import 'package:hinata/core/repositories/notification_repository.dart';
import 'package:hinata/features/notifications/notifications_cubit.dart';

import '../recording_fake.dart';

class _FakeNotifications with RecordingFake implements NotificationRepository {}

typedef _Page = ({List<AppNotification> items, int total});

/// The notifications page and the bell's popover read their lists and act on
/// a notification through these cubits.
void main() {
  late _FakeNotifications notifications;

  setUp(() {
    notifications = _FakeNotifications();
    notifications.answers[#notificationsPage] = () =>
        Future<_Page>.value((items: <AppNotification>[], total: 0));
  });

  test('the page reads twenty-five at a time', () async {
    final cubit = NotificationsCubit(notifications);
    addTearDown(cubit.close);

    await cubit.load();

    expect(notifications.only.namedArguments, {#page: 0, #size: 25});
    expect(cubit.state.items, isEmpty);
  });

  test('the bell reads only its preview', () async {
    final cubit = NotificationPreviewCubit(notifications, size: 5);
    addTearDown(cubit.close);

    await cubit.load();

    expect(notifications.only.namedArguments, {#page: 0, #size: 5});
    expect(cubit.state.data, isEmpty);
  });

  test('each action is one call for the notification it names', () async {
    final cubit = NotificationsCubit(notifications);
    addTearDown(cubit.close);
    for (final member in [
      #markAllNotificationsRead,
      #markNotificationRead,
      #markNotificationUnread,
      #deleteNotification,
    ]) {
      notifications.answers[member] = () => Future<void>.value();
    }

    await cubit.markAllRead();
    await cubit.markRead('n1');
    await cubit.markUnread('n2');
    await cubit.delete('n3');

    expect(notifications.calls.map((c) => c.memberName), [
      #markAllNotificationsRead,
      #markNotificationRead,
      #markNotificationUnread,
      #deleteNotification,
    ]);
    expect(notifications.calls.map((c) => c.positionalArguments), [
      [],
      ['n1'],
      ['n2'],
      ['n3'],
    ]);
  });

  test('a failed action comes back as the same failure', () async {
    final cubit = NotificationPreviewCubit(notifications);
    addTearDown(cubit.close);
    notifications.answers[#deleteNotification] = () =>
        Future<void>.error(failure);

    await expectLater(cubit.delete('n1'), throwsA(same(failure)));
  });
}
