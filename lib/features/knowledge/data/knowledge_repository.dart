import '../../../core/access/project_permissions.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/content_models.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/team_models.dart';
import '../../../core/models/work_models.dart' show Project;
import '../../../core/repositories/article_repository.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/project_repository.dart';
import '../../../core/repositories/team_repository.dart';
import '../../../core/repositories/user_repository.dart';
import 'knowledge_models.dart';

/// Backend-backed Knowledge Base store. Articles, spaces and people all come
/// from the real API (`/api/v1/articles`, `/users`) — there is **no** frontend
/// seed data. The bidirectional issue⇄article relationship is derived live by
/// scanning article bodies for `{{issue:KEY-N}}` tokens.
///
/// View models ([KbArticle] / [KbUser] / [KbSpace]) are kept so the KB UI is
/// unchanged; they are populated from the backend [Article] / [DirectoryUser].
/// "Spaces" are not a backend entity: they are the distinct `space` values on
/// articles, dressed with presentational metadata from [_spaceCatalog].
class KnowledgeRepository {
  KnowledgeRepository({
    required ArticleRepository articles,
    required UserRepository users,
    required AuthRepository auth,
    ProjectRepository? projects,
    TeamRepository? teams,
  }) : _articleApi = articles,
       _userApi = users,
       _authApi = auth,
       _projectApi = projects,
       _teamApi = teams;

  final ArticleRepository _articleApi;
  final UserRepository _userApi;
  final AuthRepository _authApi;

  /// For the names of the places pages live in, and the teams a page can be
  /// moved to. Optional: without them a place shows its generic label.
  final ProjectRepository? _projectApi;
  final TeamRepository? _teamApi;

  /// Names of the projects and teams pages live in, by id. Filled once per
  /// load by [loadPlaces], not once per opened page.
  final Map<String, String> _placeNames = {};
  final Map<String, Project> _placeProjects = {};
  List<Team> _myTeams = const [];

  /// The signed-in person as the server knows them, for who may move a page.
  AuthUser? _authUser;
  Future<void>? _placesLoad;

  /// Whether the server cut the page list at its cap. Then a page whose
  /// parent is missing may just be past the cut, and the tree says so.
  bool _truncated = false;
  bool get listTruncated => _truncated;

  final Map<String, KbArticle> _articles = {};
  final Map<String, KbUser> _users = {};
  final List<KbSpace> _spaces = [];

  /// Persisted backend spaces, keyed by name (insertion-ordered by sortOrder).
  /// Source of truth for a space's icon/hue/description, and the reason an empty
  /// space (no articles yet) still shows on the home grid.
  final Map<String, Space> _backendSpaces = {};
  KbUser? _me;
  bool _loaded = false;

  /// Presentational metadata for known spaces (icon · hue · description). The
  /// space *names* are real (they live on the articles); only the chrome is
  /// configured here.
  KbUser get me =>
      _me ?? (_users.values.isNotEmpty ? _users.values.first : _fallbackUser);
  static const _fallbackUser = KbUser(id: '', name: 'You', title: '', hue: 248);

  // ── lifecycle ───────────────────────────────────────────────────────────

  /// Loads articles + people from the backend once. Safe to call repeatedly —
  /// subsequent calls are no-ops until [reload] forces a refresh.
  Future<void> init() async {
    if (_loaded) return;
    await reload();
  }

  Future<void> reload() async {
    final results = await Future.wait([
      _articleApi.readableArticles(all: true),
      _userApi.users(),
    ]);
    final readable = results[0] as CappedList<Article>;
    final articles = readable.items;
    _truncated = readable.truncated;
    final dirUsers = results[1] as List<DirectoryUser>;

    _users
      ..clear()
      ..addEntries(dirUsers.map((u) => MapEntry(u.id, _toKbUser(u))));
    try {
      final me = await _authApi.me();
      _authUser = me;
      _me = KbUser(
        id: me.id,
        name: me.displayName,
        title: me.title ?? '',
        hue: _hueFor(me.id),
        pronouns: me.pronouns,
      );
    } catch (_) {
      // Non-critical — `me` falls back to the first directory user.
    }

    _backendSpaces.clear();
    try {
      for (final s in await _articleApi.spaces()) {
        _backendSpaces[s.name] = s;
      }
    } catch (_) {
      // Older backend without /spaces — fall back to derived spaces only.
    }

    _articles
      ..clear()
      ..addEntries(articles.map((a) => MapEntry(a.id, _toKbArticle(a))));
    _rebuildSpaces();
    // Names follow the new list: a page may have moved to a place not known yet.
    _placesLoad = null;
    _loaded = true;
  }

  // ── places ──────────────────────────────────────────────────────────────

  /// Loads the names of the places the loaded pages live in and the signed-in
  /// person's teams: one list of teams and one lookup of the projects named,
  /// however many pages there are. Shared by every caller until the next
  /// [reload]; a failure lets the next caller try again.
  Future<void> loadPlaces() => _placesLoad ??= _fetchPlaces();

  Future<void> _fetchPlaces() async {
    try {
      final teamApi = _teamApi;
      if (teamApi != null) {
        final all = await teamApi.teams();
        final me = _me?.id;
        _myTeams = me == null || me.isEmpty
            ? all
            : all.where((t) => t.membershipOf(me) != null).toList();
        for (final t in all) {
          _placeNames[t.id] = t.name;
        }
      }
      final projectApi = _projectApi;
      if (projectApi != null) {
        final missing = {
          for (final a in _articles.values)
            if (a.projectId case final id? when !_placeNames.containsKey(id))
              id,
        };
        for (final p in await projectApi.resolveProjects(missing.toList())) {
          rememberProject(p);
        }
      }
    } on ApiFailure {
      _placesLoad = null;
    }
  }

  /// The name of the project or team [id], once [loadPlaces] knows it.
  String? placeName(String? id) => id == null ? null : _placeNames[id];

  /// Notes a project learnt elsewhere (one just picked in the picker).
  void rememberProject(Project project) {
    _placeNames[project.id] = project.name;
    _placeProjects[project.id] = project;
  }

  /// Whether the signed-in person may move [article] to another place, as the
  /// server decides it: a private page only its author; a project page its
  /// leads and the Team-Admins of a team that owns the project; a team page
  /// that team's admins. False until [loadPlaces] has what it takes to know.
  bool mayChangePlace(KbArticle article) {
    final me = _authUser;
    if (me == null) return false;
    return switch (article.place) {
      KbPlace.private => article.authorId == me.id,
      KbPlace.team => _myTeams.any(
        (t) => t.id == article.teamId && t.membershipOf(me.id)?.isAdmin == true,
      ),
      KbPlace.project => switch (_placeProjects[article.projectId]) {
        final project? => canManageProject(project, me, _myTeams),
        null => false,
      },
    };
  }

  /// The teams the signed-in person belongs to, as of [loadPlaces]: where a
  /// page can be moved. The server lists only those; the filter keeps the
  /// menu honest should an older server not.
  List<Team> get myTeams => _myTeams;

  void _rebuildSpaces() {
    final articleNames = <String>{for (final a in _articles.values) a.spaceId}
      ..removeWhere((n) => n.isEmpty);
    // Persisted backend spaces first (already in sortOrder), then any space that
    // only exists as an article's `space` value (alphabetically). No hardcoded
    // placeholder spaces — an empty knowledge base shows the create-space action,
    // and every listed space is a real, deletable backend entity.
    final ordered = <String>[
      ..._backendSpaces.keys,
      ...(articleNames.where((n) => !_backendSpaces.containsKey(n)).toList()
        ..sort()),
    ];
    _spaces
      ..clear()
      ..addAll(ordered.map(_spaceFor));
  }

  // ── mappers ───────────────────────────────────────────────────────────────

  KbUser _toKbUser(DirectoryUser u) => KbUser(
    id: u.id,
    pronouns: u.pronouns,
    name: u.displayName,
    title: u.title ?? '',
    hue: _hueFor(u.id),
  );

  KbArticle _toKbArticle(Article a) {
    final author = a.authorId ?? '';
    return KbArticle(
      id: a.id,
      spaceId: a.space ?? 'Engineering',
      parentId: a.parentId,
      title: a.title,
      icon: a.icon ?? 'file-text',
      authorId: author,
      contributorIds: author.isEmpty ? const [] : [author],
      updated: _ago(a.updatedAt),
      created: _dateLabel(a.createdAt),
      reads: 0,
      labels: a.tags,
      status: 'published',
      body: a.content ?? '',
      doc: a.contentDoc,
      projectId: a.projectId,
      teamId: a.teamId,
    );
  }

  KbSpace _spaceFor(String name) {
    final backend = _backendSpaces[name];
    final key = name.length >= 3
        ? name.substring(0, 3).toUpperCase()
        : name.toUpperCase();
    return KbSpace(
      id: name,
      key: key,
      name: name,
      hue: backend?.hue ?? 250,
      icon: backend?.icon ?? 'file-text',
      desc: backend?.description ?? '',
    );
  }

  static int _hueFor(String id) => id.isEmpty ? 248 : (id.hashCode.abs() % 360);

  static String _ago(DateTime? t) {
    if (t == null) return 'just now';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 30) return '${d.inDays}d';
    if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
    return '${(d.inDays / 365).floor()}y';
  }

  static String _dateLabel(DateTime? t) {
    if (t == null) return 'Today';
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Today';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, ${t.year}';
  }

  // ── lookups ─────────────────────────────────────────────────────────────

  KbUser? userById(String id) => _users[id];
  KbSpace? spaceById(String id) => _spaces.cast<KbSpace?>().firstWhere(
    (s) => s?.id == id,
    orElse: () => null,
  );
  KbArticle? articleById(String id) => _articles[id];

  List<KbUser> get users => _users.values.toList(growable: false);
  List<KbSpace> get spaces => List.unmodifiable(_spaces);
  List<KbArticle> get articles => _articles.values.toList(growable: false);

  List<KbArticle> articlesInSpace(String spaceId) =>
      articles.where((a) => a.spaceId == spaceId).toList();

  /// The pages [spaceId]'s tree starts from: top-level pages, plus every page
  /// whose parent is not in this space's list.
  ///
  /// The second kind is not an edge case. Access can be granted on a subpage
  /// alone, and the server then returns the page without its parent; a tree
  /// that only started from `parentId == null` dropped such a page without a
  /// trace, although the person had just been given it.
  List<KbArticle> rootsInSpace(String spaceId) {
    final inSpace = articlesInSpace(spaceId);
    final ids = {for (final a in inSpace) a.id};
    return inSpace
        .where((a) => a.parentId == null || !ids.contains(a.parentId))
        .toList();
  }

  /// Whether [article] sits at the top of its place, so its place can be
  /// changed. A subpage lives wherever its parent lives.
  bool isTopLevel(KbArticle article) => article.parentId == null;

  int articleCountInSpace(String spaceId) =>
      articles.where((a) => a.spaceId == spaceId).length;

  // ── derived bidirectional links ───────────────────────────────────────────

  /// Server-resolved backlinks: fetches the articles referencing
  /// [issueReadableId] via the dedicated endpoint, so the issue-detail
  /// "Documented in" panel never has to drain and regex-scan the whole KB corpus
  /// client-side (the old path called [init] + [articlesForIssue]).
  Future<List<KbArticle>> articlesReferencingIssue(
    String issueReadableId,
  ) async {
    final refs = await _articleApi.articlesReferencingIssue(issueReadableId);
    return refs.map(_toKbArticle).toList();
  }

  /// Related articles referenced via `{{doc:…}}` tokens in [body].
  List<KbArticle> relatedArticles(String body) {
    final re = RegExp(r'\{\{doc:(\w+)\}\}');
    final seen = <String>{};
    final out = <KbArticle>[];
    for (final m in re.allMatches(body)) {
      final id = m.group(1)!;
      if (seen.add(id)) {
        final a = _articles[id];
        if (a != null) out.add(a);
      }
    }
    return out;
  }

  // ── mutations (write through to the backend) ──────────────────────────────

  /// Saves title, body and space. Never sends a project or team: an edit does
  /// not move a page between places (the server ignores both on PATCH), that
  /// is [placeArticle]'s job.
  Future<KbArticle> saveEdit(
    String id, {
    required String title,
    required String doc,
    required String spaceId,
  }) async {
    final existing = _articles[id];
    final saved = await _articleApi.saveArticle(
      id: id,
      title: title,
      contentDoc: doc,
      space: spaceId,
      icon: existing?.icon,
      tags: existing?.labels,
    );
    final kb = _toKbArticle(saved);
    _articles[id] = kb;
    _rebuildSpaces();
    return kb;
  }

  /// Creates a page. Under a [parentId] it takes the parent's place and
  /// [projectId]/[teamId] are not sent; at the top level they choose where it
  /// lives, and with neither it is private to its author.
  Future<KbArticle> createArticle({
    required String title,
    required String doc,
    required String spaceId,
    String? parentId,
    String? projectId,
    String? teamId,
  }) async {
    final topLevel = parentId == null;
    final saved = await _articleApi.saveArticle(
      title: title,
      contentDoc: doc,
      space: spaceId,
      parentId: parentId,
      projectId: topLevel ? projectId : null,
      teamId: topLevel ? teamId : null,
      icon: 'file-text',
    );
    final kb = _toKbArticle(saved);
    _articles[kb.id] = kb;
    _rebuildSpaces();
    return kb;
  }

  /// Re-parents [id] under [parentId] (null = space root) and/or moves it into
  /// [spaceId]. Children keep their own parent links, so the subtree moves with
  /// it. Returns the moved article.
  Future<KbArticle> moveArticle(
    String id, {
    String? parentId,
    String? spaceId,
  }) async {
    final existing = _articles[id];
    if (existing == null) return Future.error('unknown article');
    final saved = await _articleApi.moveArticle(
      id,
      title: existing.title,
      parentId: parentId,
      space: spaceId ?? existing.spaceId,
    );
    final kb = _toKbArticle(saved);
    _articles[id] = kb;
    _rebuildSpaces();
    return kb;
  }

  /// Moves the top-level page [id] with everything below it into a project,
  /// a team, or (both null) back to its author alone. The server moves the
  /// subtree; the cache follows so the tree glyphs are right without a reload.
  Future<KbArticle> placeArticle(
    String id, {
    String? projectId,
    String? teamId,
  }) async {
    final saved = await _articleApi.placeArticle(
      id,
      projectId: projectId,
      teamId: teamId,
    );
    for (final a in _articles.values.toList()) {
      if (a.id != id && isSelfOrAncestor(id, a.id)) {
        _articles[a.id] = a.copyWith(
          projectId: saved.projectId,
          teamId: saved.teamId,
        );
      }
    }
    final kb = _toKbArticle(saved);
    _articles[id] = kb;
    return kb;
  }

  Future<void> deleteArticle(String id) async {
    await _articleApi.deleteArticle(id);
    _articles.remove(id);
    _rebuildSpaces();
  }

  /// Creates a persisted space and returns its view model. The space shows up on
  /// the home grid immediately, even before it has any articles.
  Future<KbSpace> createSpace({
    required String name,
    required String icon,
    required int hue,
    String? description,
  }) async {
    final s = await _articleApi.createSpace(
      name: name,
      icon: icon,
      hue: hue,
      description: description,
    );
    _backendSpaces[s.name] = s;
    _rebuildSpaces();
    return _spaceFor(s.name);
  }

  /// Deletes the persisted space named [spaceId]. The backend rejects this while
  /// the space still has articles (surfaced as an [ApiFailure]).
  Future<void> deleteSpace(String spaceId) async {
    final backend = _backendSpaces[spaceId];
    if (backend == null) return Future.error('unknown space');
    await _articleApi.deleteSpace(backend.id);
    _backendSpaces.remove(spaceId);
    _rebuildSpaces();
  }

  /// Whether [spaceId] is a persisted backend space (vs. one merely derived from
  /// an article's `space` value) — only persisted spaces can be deleted.
  bool isPersistedSpace(String spaceId) => _backendSpaces.containsKey(spaceId);

  /// Whether [maybeAncestorId] is [id] itself or one of its ancestors — used to
  /// reject moves that would create a cycle.
  bool isSelfOrAncestor(String maybeAncestorId, String id) {
    var cursor = _articles[id];
    while (cursor != null) {
      if (cursor.id == maybeAncestorId) return true;
      final parent = cursor.parentId;
      cursor = parent == null ? null : _articles[parent];
    }
    return false;
  }
}
