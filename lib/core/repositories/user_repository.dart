import '../api/api_client.dart';
import '../models/core_models.dart';

/// The organisation-wide user directory.
class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  Future<List<DirectoryUser>> users() async =>
      ((await _api.get('/api/v1/users')) as List<dynamic>)
          .map((u) => DirectoryUser.fromJson(u as Map<String, dynamic>))
          .toList();

  /// Server-side type-ahead over the directory, for assignee/member pickers in
  /// large orgs where loading every user is wasteful. Returns one page plus the
  /// backend total. An empty [query] returns the first page of all active users.
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) async {
    final data =
        await _api.get(
              '/api/v1/users/search',
              query: {'q': query, 'page': page, 'size': size},
            )
            as Map<String, dynamic>;
    return (
      items: ((data['content'] as List<dynamic>?) ?? [])
          .map((u) => DirectoryUser.fromJson(u as Map<String, dynamic>))
          .toList(),
      total: data['totalElements'] as int? ?? 0,
    );
  }
}
