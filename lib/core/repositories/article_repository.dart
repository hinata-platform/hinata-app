import '../api/api_client.dart';
import '../models/content_models.dart';

/// Knowledge-base articles and spaces (the raw REST surface; the feature-level
/// cache in `features/knowledge/data` builds on top of this).
class ArticleRepository {
  ArticleRepository(this._api);

  final ApiClient _api;

  /// Lists articles. [all] fetches every page the caller may read (project
  /// pages of visible projects, team pages per membership, their own private
  /// pages); otherwise scoped by [projectId].
  Future<List<Article>> articles({String? projectId, bool all = false}) async =>
      (await readableArticles(projectId: projectId, all: all)).items;

  /// [articles], saying whether the server cut the list at its cap. The tree
  /// needs to know: a page whose parent is missing may then simply be past the
  /// cut rather than unreadable.
  Future<CappedList<Article>> readableArticles({
    String? projectId,
    bool all = false,
  }) async {
    final response = await _api.getWithHeaders(
      '/api/v1/articles',
      query: {'projectId': ?projectId, if (all) 'all': true},
    );
    return (
      items: (response.data as List<dynamic>)
          .map((a) => Article.fromJson(a as Map<String, dynamic>))
          .toList(),
      truncated: _truncated(response.header),
    );
  }

  static bool _truncated(String? Function(String name) header) =>
      header('x-truncated')?.toLowerCase() == 'true';

  Future<Article> article(String id) async => Article.fromJson(
    await _api.get('/api/v1/articles/$id') as Map<String, dynamic>,
  );

  /// Articles that reference [issueReadableId] via a `{{issue:KEY}}` token,
  /// resolved server-side (ACL-scoped, capped) so the issue-detail "Documented
  /// in" panel never has to drain and regex-scan the whole KB corpus client-side.
  Future<List<Article>> articlesReferencingIssue(
    String issueReadableId,
  ) async =>
      ((await _api.get(
                '/api/v1/articles',
                query: {'referencesIssue': issueReadableId},
              ))
              as List<dynamic>)
          .map((a) => Article.fromJson(a as Map<String, dynamic>))
          .toList();

  /// Creates ([id] null) or edits an article.
  ///
  /// [projectId]/[teamId] only count on create, and only without a
  /// [parentId] (a subpage takes its parent's place). An edit never changes
  /// where a page lives: that is [placeArticle]'s job, and a new [parentId]
  /// moves the page into the parent's place.
  Future<Article> saveArticle({
    String? id,
    required String title,

    /// Markdown. Accepted and converted server-side; [contentDoc] wins.
    String? content,

    /// The Lexical document — what the editor produces.
    String? contentDoc,
    String? projectId,
    String? teamId,
    String? parentId,
    String? space,
    String? icon,
    List<String>? tags,
  }) async {
    final body = {
      'title': title,
      'content': ?content,
      'contentDoc': ?contentDoc,
      'projectId': ?projectId,
      'teamId': ?teamId,
      'parentId': ?parentId,
      'space': ?space,
      'icon': ?icon,
      'tags': ?tags,
    };
    final data = id == null
        ? await _api.post('/api/v1/articles', body: body)
        : await _api.patch('/api/v1/articles/$id', body: body);
    return Article.fromJson(data as Map<String, dynamic>);
  }

  /// Moves an article under a new parent (or to the space root when [parentId]
  /// is null — sent explicitly, unlike [saveArticle] which omits nulls) and/or
  /// into a different [space]. Content/tags/icon are left untouched.
  Future<Article> moveArticle(
    String id, {
    required String title,
    String? parentId,
    String? space,
  }) async {
    final data = await _api.patch(
      '/api/v1/articles/$id',
      body: {'title': title, 'parentId': parentId, 'space': ?space},
    );
    return Article.fromJson(data as Map<String, dynamic>);
  }

  /// Moves a top-level page, with everything below it, into a project, a team,
  /// or (both null) back to its author alone. Only the author may make a page
  /// private; a subpage refuses with `error.article.placeFollowsParent`.
  Future<Article> placeArticle(
    String id, {
    String? projectId,
    String? teamId,
  }) async => Article.fromJson(
    await _api.put(
          '/api/v1/articles/$id/place',
          body: {'projectId': projectId, 'teamId': teamId},
        )
        as Map<String, dynamic>,
  );

  /// The pages of [teamId] the caller reads (a Team-Admin: all of them), in
  /// the slim shape of [TeamPageRef]. For the knowledge-access picker in the
  /// team modals. [query] narrows by title on the server; the server stops at
  /// its cap and says so ([CappedList.truncated]).
  Future<CappedList<TeamPageRef>> teamPages(
    String teamId, {
    String? query,
  }) async {
    final q = query?.trim();
    final response = await _api.getWithHeaders(
      '/api/v1/teams/${Uri.encodeComponent(teamId)}/pages',
      query: {if (q != null && q.isNotEmpty) 'q': q},
    );
    return (
      items: (response.data as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(TeamPageRef.fromJson)
          .toList(),
      truncated: _truncated(response.header),
    );
  }

  Future<void> deleteArticle(String id) async =>
      _api.delete('/api/v1/articles/$id');

  /// Lists every knowledge-base space (organisation-wide, sorted).
  Future<List<Space>> spaces() async =>
      ((await _api.get('/api/v1/spaces')) as List<dynamic>)
          .map((s) => Space.fromJson(s as Map<String, dynamic>))
          .toList();

  Future<Space> createSpace({
    required String name,
    String? icon,
    int? hue,
    String? description,
  }) async {
    final data = await _api.post(
      '/api/v1/spaces',
      body: {
        'name': name,
        'icon': ?icon,
        'hue': ?hue,
        'description': ?description,
      },
    );
    return Space.fromJson(data as Map<String, dynamic>);
  }

  Future<void> deleteSpace(String id) async =>
      _api.delete('/api/v1/spaces/$id');
}
