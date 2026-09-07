import '../api/api_client.dart';
import '../models/core_models.dart';

/// The organisation-wide user directory.
class UserRepository {
  UserRepository(this._api);

  /// How many ids travel in one `by-ids` request.
  ///
  /// The ids go on the query string, one parameter each, and an id is 24
  /// characters — so a few hundred of them overrun the container's
  /// request-header limit and the call is refused before it reaches a
  /// controller, which reads to a caller as "the directory does not know
  /// anybody". A week's timesheet in a large instance is exactly that many.
  static const byIdsChunk = 100;

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

  /// Resolves a bounded, specific set of directory users by id (the endpoint is
  /// capped server-side). Lets a screen render names/avatars for exactly the
  /// people it references — e.g. the assignees/reporters on a board — without
  /// draining the whole directory. Returns only the users that still exist.
  Future<List<DirectoryUser>> usersByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final users = <DirectoryUser>[];
    for (var start = 0; start < ids.length; start += byIdsChunk) {
      final chunk = ids.sublist(
        start,
        start + byIdsChunk > ids.length ? ids.length : start + byIdsChunk,
      );
      users.addAll(
        ((await _api.get('/api/v1/users/by-ids', query: {'ids': chunk}))
                as List<dynamic>)
            .map((u) => DirectoryUser.fromJson(u as Map<String, dynamic>)),
      );
    }
    return users;
  }
}
