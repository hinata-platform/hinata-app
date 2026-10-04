import 'package:flutter/foundation.dart' show protected;

import '../../core/blocs/fetch_cubit.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/models/content_models.dart';
import '../../core/repositories/notification_repository.dart';

/// What the reader does to a notification, wherever it is listed. The list
/// re-reads itself afterwards, so each call only has to reach the server.
mixin NotificationActions {
  @protected
  NotificationRepository get notifications;

  Future<void> markAllRead() => notifications.markAllNotificationsRead();

  Future<void> markRead(String id) => notifications.markNotificationRead(id);

  Future<void> markUnread(String id) =>
      notifications.markNotificationUnread(id);

  Future<void> delete(String id) => notifications.deleteNotification(id);
}

/// The notifications page: every notification, a page at a time.
class NotificationsCubit extends PagedCubit<AppNotification>
    with NotificationActions {
  NotificationsCubit(NotificationRepository repository)
    : notifications = repository,
      super(
        (page, size) => repository.notificationsPage(page: page, size: size),
        pageSize: 25,
        keyOf: (n) => n.id,
      );

  @override
  @protected
  final NotificationRepository notifications;
}

/// The bell's popover: the few most recent notifications, read whenever it
/// opens.
class NotificationPreviewCubit extends FetchCubit<List<AppNotification>>
    with NotificationActions {
  NotificationPreviewCubit(NotificationRepository repository, {int size = 5})
    : notifications = repository,
      super(() async => (await repository.notificationsPage(size: size)).items);

  @override
  @protected
  final NotificationRepository notifications;
}
