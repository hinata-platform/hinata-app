import '../api/api_client.dart';
import '../models/content_models.dart';

/// In-app notifications: paging, unread badge count, and read receipts.
class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  Future<List<AppNotification>> notifications({int page = 0}) async {
    final data =
        await _api.get('/api/v1/notifications', query: {'page': page})
            as Map<String, dynamic>;
    return ((data['content'] as List<dynamic>?) ?? [])
        .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
        .toList();
  }

  /// One page of notifications plus the backend total, for infinite scroll.
  Future<({List<AppNotification> items, int total})> notificationsPage({
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/notifications',
              query: {'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }

  Future<int> unreadNotifications() async =>
      ((await _api.get('/api/v1/notifications/unread-count'))
              as Map<String, dynamic>)['count']
          as int? ??
      0;

  Future<void> markNotificationRead(String id) =>
      _api.post('/api/v1/notifications/$id/read');

  /// Marks every supplied notification id as read. The backend exposes no bulk
  /// endpoint, so we fan the per-id calls out concurrently.
  Future<void> markNotificationsRead(Iterable<String> ids) =>
      Future.wait(ids.map(markNotificationRead));
}
