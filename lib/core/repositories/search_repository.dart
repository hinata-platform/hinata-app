import '../api/api_client.dart';
import '../models/search_api.dart';

/// The unified global search endpoint.
class SearchRepository {
  SearchRepository(this._api);

  final ApiClient _api;

  /// The revision of the hit contract this app reads. With it people link to
  /// their profile (`/people/{id}`) instead of the admin area, which the
  /// published app without it still gets.
  static const contractRevision = 2;

  /// Unified search across every area the reader may see. [scope] is `all`
  /// (default) or a single category name (`issues`, `comments`, `shifts`, …).
  /// A blank [query] returns just category counts.
  /// [archived] searches the archive instead (archived issues + projects) —
  /// triggered by the palette's locale-aware "archived" keyword.
  Future<SearchApiResponse> search({
    String query = '',
    String? scope,
    bool archived = false,
  }) async => SearchApiResponse.fromJson(
    await _api.get(
          '/api/v1/search',
          query: {
            'q': ?(query.trim().isEmpty ? null : query.trim()),
            'scope': ?scope,
            if (archived) 'archived': true,
            'v': contractRevision,
          },
        )
        as Map<String, dynamic>,
  );
}
