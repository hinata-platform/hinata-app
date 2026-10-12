import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;

import '../../../core/access/project_permissions.dart';
import '../../../core/api/api_client.dart';
import '../../../core/blocs/paged_cubit.dart' show PageResult;
import '../../../core/models/content_models.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/team_models.dart';
import '../../../core/models/work_models.dart' show Issue, Project;
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
    final epoch = _epoch;
    // One round trip's worth of waiting: none of these needs another's answer.
    final results = await Future.wait<Object?>([
      _articleApi.readableArticles(all: true),
      _userApi.users(),
      _signedIn(),
      _persistedSpaces(),
      loadMarks(),
    ]);
    if (epoch != _epoch) return;
    final readable = results[0] as CappedList<Article>;
    final articles = readable.items;
    // The documents and texts are read off the UI thread; a thousand pages
    // would otherwise stall a frame for their JSON and their lowering.
    final prepared = await _prepare(articles);
    if (epoch != _epoch) return;
    _truncated = readable.truncated;
    final dirUsers = results[1] as List<DirectoryUser>;

    _users
      ..clear()
      ..addEntries(dirUsers.map((u) => MapEntry(u.id, _toKbUser(u))));
    if (results[2] case final AuthUser me) {
      _authUser = me;
      _me = KbUser(
        id: me.id,
        name: me.displayName,
        title: me.title ?? '',
        hue: _hueFor(me.id),
        pronouns: me.pronouns,
      );
    }

    _backendSpaces.clear();
    for (final s in results[3] as List<Space>) {
      _backendSpaces[s.name] = s;
    }

    _articles.clear();
    _linksTo.clear();
    _linksFrom.clear();
    _childIds.clear();
    _hay.clear();
    for (final a in articles) {
      _put(_toKbArticle(a), links: prepared.links[a.id] ?? const []);
    }
    _hay.addAll(prepared.hay);
    _rebuildSpaces();
    // Names follow the new list: a page may have moved to a place not known yet.
    _placesLoad = null;
    // A refresh is asked for: issues created since then become link targets.
    _issueTargets = null;
    _loaded = true;
  }

  /// Forgets everything of the account that signed out, so the next one on
  /// this device never sees its pages, people, favourites or link targets.
  /// The next [init] loads afresh.
  void reset() {
    // A load still on its way belongs to the account that left: it drops
    // what it brings instead of writing it here.
    _epoch++;
    _loaded = false;
    _truncated = false;
    _authUser = null;
    _me = null;
    _placesLoad = null;
    _issueTargets = null;
    _myTeams = const [];
    _placeNames.clear();
    _placeProjects.clear();
    _articles.clear();
    _users.clear();
    _spaces.clear();
    _backendSpaces.clear();
    _linksTo.clear();
    _linksFrom.clear();
    _childIds.clear();
    _hay.clear();
    _starred.clear();
    _recent.clear();
    _revision++;
  }

  /// Moves on with every [reset]. A load notes it before it waits and keeps
  /// its answer only when it has not moved since.
  int _epoch = 0;

  /// Below this much text, reading it here is cheaper than starting an
  /// isolate for it.
  static const _inlineScan = 64 * 1024;

  /// What [reload] reads of [articles] beyond mapping them: the pages each
  /// one links to and, for a large knowledge base, the search text of every
  /// page. Only documents with a smart link are parsed at all. Past
  /// [_inlineScan] both are worked out in one isolate; below it the links
  /// are read here and the search text waits for the first search.
  static Future<_Prepared> _prepare(List<Article> articles) async {
    final pages = <_PageText>[];
    var size = 0;
    for (final a in articles) {
      final doc = a.contentDoc;
      final linking = doc != null && doc.contains('"smartlink"') ? doc : null;
      final body = a.content ?? '';
      pages.add((
        id: a.id,
        doc: linking,
        space: a.space ?? '',
        labels: a.tags,
        body: body,
      ));
      size += body.length + (linking?.length ?? 0);
    }
    if (size < _inlineScan) {
      return (links: _linksOfAll(pages), hay: const <String, String>{});
    }
    return compute(_prepareAll, pages);
  }

  static _Prepared _prepareAll(List<_PageText> pages) => (
    links: _linksOfAll(pages),
    hay: {for (final p in pages) p.id: _hayFrom(p.space, p.labels, p.body)},
  );

  static Map<String, List<String>> _linksOfAll(List<_PageText> pages) => {
    for (final p in pages)
      if (p.doc != null)
        if (linkedDocIds(p.doc) case final ids when ids.isNotEmpty) p.id: ids,
  };

  /// The signed-in person, or null. Non-critical: `me` then falls back to the
  /// first directory user.
  Future<AuthUser?> _signedIn() async {
    try {
      return await _authApi.me();
    } catch (_) {
      return null;
    }
  }

  /// The persisted spaces. An older backend without /spaces leaves only the
  /// spaces derived from the pages.
  Future<List<Space>> _persistedSpaces() async {
    try {
      return await _articleApi.spaces();
    } catch (_) {
      return const [];
    }
  }

  // ── link targets ────────────────────────────────────────────────────────

  Future<List<Issue>>? _issueTargets;

  /// Every issue the reader sees, for `{{issue:…}}` links and the `@` menu.
  /// Fetched with [fetch] once for as long as this cache lives, not on every
  /// visit to the knowledge base; [reload] lets the next caller fetch again,
  /// and so does a failure.
  ///
  /// A fetch the account that signed out started answers nothing.
  Future<List<Issue>> linkIssues(Future<List<Issue>> Function() fetch) async {
    final epoch = _epoch;
    final pending = _issueTargets ??= fetch();
    final List<Issue> issues;
    try {
      issues = await pending;
    } catch (_) {
      if (identical(_issueTargets, pending)) _issueTargets = null;
      rethrow;
    }
    return epoch == _epoch ? issues : const [];
  }

  // ── indexes ─────────────────────────────────────────────────────────────

  /// Moves on with every change to the cached pages, so a view can keep what
  /// it derived from them until the next change.
  int get revision => _revision;
  int _revision = 0;

  /// The pages linking to a page, by the linked page's id.
  final Map<String, Set<String>> _linksTo = {};

  /// The pages a page links to, in document order, by the linking page's id.
  final Map<String, List<String>> _linksFrom = {};

  /// The direct subpages of a page, by the parent's id.
  final Map<String, Set<String>> _childIds = {};

  /// What the search reads of each page, by its id: space, labels and text,
  /// whitespace collapsed and in lower case. Made on the first search that
  /// needs it and dropped when the page changes.
  final Map<String, String> _hay = {};

  /// The last search and what it found, kept until the query or the cache
  /// changes, so a rebuild of the results does not search again.
  (String, int)? _searchKey;
  List<KbArticle> _searchHits = const [];

  /// Puts [kb] into the cache and the indexes. A page's document is only
  /// read again when it changed, so a reorder or a place change costs no
  /// parsing; [links] are its links when they were read already.
  void _put(KbArticle kb, {List<String>? links}) {
    final old = _articles[kb.id];
    _articles[kb.id] = kb;
    _revision++;
    if (old == null || old.parentId != kb.parentId) {
      if (old?.parentId case final parent?) _childIds[parent]?.remove(kb.id);
      if (kb.parentId case final parent?) {
        (_childIds[parent] ??= <String>{}).add(kb.id);
      }
    }
    if (old == null || old.doc != kb.doc) {
      for (final target in _linksFrom.remove(kb.id) ?? const <String>[]) {
        _linksTo[target]?.remove(kb.id);
      }
      final targets = links ?? linkedDocIds(kb.doc);
      if (targets.isNotEmpty) {
        _linksFrom[kb.id] = targets;
        for (final target in targets) {
          (_linksTo[target] ??= <String>{}).add(kb.id);
        }
      }
    }
    if (old == null ||
        old.body != kb.body ||
        old.spaceId != kb.spaceId ||
        !_sameLabels(old.labels, kb.labels)) {
      _hay.remove(kb.id);
    }
  }

  /// Takes [id] out of the cache and the indexes. Pages linking to it keep
  /// their entry; a lookup only ever returns pages still here.
  void _drop(String id) {
    final old = _articles.remove(id);
    if (old == null) return;
    _revision++;
    if (old.parentId case final parent?) _childIds[parent]?.remove(id);
    for (final target in _linksFrom.remove(id) ?? const <String>[]) {
      _linksTo[target]?.remove(id);
    }
    _hay.remove(id);
  }

  static bool _sameLabels(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── places ──────────────────────────────────────────────────────────────

  /// Loads the names of the places the loaded pages live in and the signed-in
  /// person's teams: one list of teams and one lookup of the projects named,
  /// however many pages there are. Shared by every caller until the next
  /// [reload]; a failure lets the next caller try again.
  Future<void> loadPlaces() => _placesLoad ??= _fetchPlaces();

  Future<void> _fetchPlaces() async {
    final epoch = _epoch;
    try {
      final teamApi = _teamApi;
      if (teamApi != null) {
        final all = await teamApi.teams();
        if (epoch != _epoch) return;
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
        final projects = await projectApi.resolveProjects(missing.toList());
        if (epoch != _epoch) return;
        projects.forEach(rememberProject);
      }
    } on ApiFailure {
      if (epoch == _epoch) _placesLoad = null;
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

  KbArticle _toKbArticle(Article a) => KbArticle(
    id: a.id,
    spaceId: a.space ?? '',
    parentId: a.parentId,
    title: a.title,
    icon: a.icon ?? 'file-text',
    authorId: a.authorId ?? '',
    labels: a.tags,
    body: a.content ?? '',
    doc: a.contentDoc,
    projectId: a.projectId,
    teamId: a.teamId,
    sortOrder: a.sortOrder,
    createdAt: a.createdAt,
    updatedAt: a.updatedAt,
    lastEditorId: a.lastEditorId,
  );

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

  /// The pages of [spaceId] in their sibling order.
  List<KbArticle> articlesInSpace(String spaceId) =>
      articles.where((a) => a.spaceId == spaceId).toList()
        ..sort(bySiblingOrder);

  /// Sibling order: the stored position, then the title, so pages nobody has
  /// arranged still come out the same way every time.
  static int bySiblingOrder(KbArticle a, KbArticle b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0
        ? byOrder
        : a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  /// The direct subpages of [id] the reader can see, in sibling order.
  List<KbArticle> childrenOf(String id) =>
      [for (final child in _childIds[id] ?? const <String>{}) ?_articles[child]]
        ..sort(bySiblingOrder);

  /// The pages above [id], from the top of its tree down to its parent. Stops
  /// at the first parent the reader cannot see.
  List<KbArticle> ancestorsOf(String id) {
    final chain = <KbArticle>[];
    final seen = <String>{id};
    var parentId = _articles[id]?.parentId;
    while (parentId != null && seen.add(parentId)) {
      final parent = _articles[parentId];
      if (parent == null) break;
      chain.insert(0, parent);
      parentId = parent.parentId;
    }
    return chain;
  }

  /// Every label on a page the reader sees, with how many pages carry it,
  /// most used first. Taken from the readable pages only, never org-wide.
  List<({String label, int count})> labels({String? spaceId}) {
    final counts = <String, int>{};
    for (final a in _articles.values) {
      if (spaceId != null && a.spaceId != spaceId) continue;
      for (final l in a.labels) {
        counts[l] = (counts[l] ?? 0) + 1;
      }
    }
    final out = [
      for (final e in counts.entries) (label: e.key, count: e.value),
    ];
    out.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.label.compareTo(b.label);
    });
    return out;
  }

  /// Pages most recently changed, newest first.
  List<KbArticle> recentlyUpdated({String? spaceId, int limit = 6}) {
    final list = [
      for (final a in _articles.values)
        if (spaceId == null || a.spaceId == spaceId) a,
    ];
    list.sort(
      (a, b) =>
          (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)),
    );
    return list.take(limit).toList();
  }

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

  /// Pages [article] links to and pages that link to it, each once, as far
  /// as the reader can see them. A link is a `smartlink` node of kind `doc`
  /// in the stored document; the plain text the server derives drops its
  /// target, so the document is what is read here.
  ///
  /// Read from the link index, so it costs the links of this one page, not
  /// a pass over every document.
  List<KbArticle> relatedArticles(KbArticle article) {
    final out = <String, KbArticle>{};
    // A page that is not the cached one (a version, a draft) is read itself.
    final outgoing = identical(_articles[article.id], article)
        ? _linksFrom[article.id] ?? const <String>[]
        : linkedDocIds(article.doc);
    for (final id in [...outgoing, ...?_linksTo[article.id]]) {
      final linked = _articles[id];
      if (linked != null && linked.id != article.id) out[id] = linked;
    }
    return out.values.toList();
  }

  // ── search ──────────────────────────────────────────────────────────────

  /// Pages whose title, space, labels or text contain [query], titles first.
  /// [query] is trimmed and in lower case. A page's text is prepared for
  /// this once, on the first search after it was loaded or changed, so
  /// typing costs no lowering of whole pages; the same query on an unchanged
  /// cache answers from the last search.
  List<KbArticle> search(String query) {
    if (query.isEmpty) return const [];
    final key = (query, _revision);
    if (key == _searchKey) return _searchHits;
    final byTitle = <KbArticle>[];
    final byRest = <KbArticle>[];
    for (final a in _articles.values) {
      if (a.title.toLowerCase().contains(query)) {
        byTitle.add(a);
      } else if ((_hay[a.id] ??= _hayOf(a)).contains(query)) {
        byRest.add(a);
      }
    }
    _searchKey = key;
    return _searchHits = List.unmodifiable([...byTitle, ...byRest]);
  }

  static String _hayOf(KbArticle a) => _hayFrom(a.spaceId, a.labels, a.body);

  static String _hayFrom(String space, List<String> labels, String body) =>
      '$space ${labels.join(' ')} ${_collapsed(body)}'.toLowerCase();

  static String _collapsed(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// The words around the first match of [query] in [id]'s text, or the
  /// start of the text when it does not contain [query]. Made from the page
  /// itself, for the few results on screen, and kept per page until the
  /// query or the cache changes, so a rebuild of the results makes none anew.
  String searchExcerpt(String id, String query) {
    final key = (query, _revision);
    if (key != _excerptKey) {
      _excerptKey = key;
      _excerpts.clear();
    }
    return _excerpts[id] ??= _excerptOf(id, query);
  }

  (String, int)? _excerptKey;
  final Map<String, String> _excerpts = {};

  String _excerptOf(String id, String query) {
    final text = _collapsed(_articles[id]?.body ?? '');
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();
    // Lowering can change a string's length; then the offsets do not carry
    // over and the start of the text is the honest answer.
    final at = query.isEmpty || lower.length != text.length
        ? -1
        : lower.indexOf(query);
    if (at < 0) return text.length > 140 ? '${text.substring(0, 140)}…' : text;
    final start = (at - 50).clamp(0, text.length);
    final end = (at + query.length + 90).clamp(0, text.length);
    return '${start > 0 ? '…' : ''}${text.substring(start, end)}'
        '${end < text.length ? '…' : ''}';
  }

  /// The article ids the document [doc] links to, in document order.
  static List<String> linkedDocIds(String? doc) {
    if (doc == null || !doc.contains('"smartlink"')) return const [];
    final Object? root;
    try {
      root = jsonDecode(doc);
    } on FormatException {
      return const [];
    }
    final ids = <String>[];
    void walk(Object? node) {
      if (node is Map) {
        if (node['type'] == 'smartlink' && node['kind'] == 'doc') {
          final target = node['targetId'];
          if (target is String && target.isNotEmpty && !ids.contains(target)) {
            ids.add(target);
          }
        }
        for (final value in node.values) {
          if (value is Map || value is List) walk(value);
        }
      } else if (node is List) {
        for (final child in node) {
          walk(child);
        }
      }
    }

    walk(root);
    return ids;
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
    List<String>? labels,
  }) async {
    final existing = _articles[id];
    final saved = await _articleApi.saveArticle(
      id: id,
      title: title,
      contentDoc: doc,
      space: spaceId,
      icon: existing?.icon,
      tags: labels ?? existing?.labels,
    );
    final kb = _toKbArticle(saved);
    _put(kb);
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
    List<String> labels = const [],
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
      tags: labels,
    );
    final kb = _toKbArticle(saved);
    _put(kb);
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
    _put(kb);
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
        _put(a.copyWith(projectId: saved.projectId, teamId: saved.teamId));
      }
    }
    final kb = _toKbArticle(saved);
    _put(kb);
    return kb;
  }

  Future<void> deleteArticle(String id) async {
    await _articleApi.deleteArticle(id);
    _drop(id);
    _starred.remove(id);
    _recent.remove(id);
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

  /// Renames or redresses the persisted space [spaceId]. A rename is carried
  /// onto the cached pages too, as the server does with the stored ones.
  Future<KbSpace> updateSpace(
    String spaceId, {
    required String name,
    required String icon,
    required int hue,
    required String description,
  }) async {
    final backend = _backendSpaces[spaceId];
    if (backend == null) return Future.error('unknown space');
    final s = await _articleApi.updateSpace(
      backend.id,
      name: name,
      icon: icon,
      hue: hue,
      description: description,
    );
    _backendSpaces.remove(spaceId);
    _backendSpaces[s.name] = s;
    if (s.name != spaceId) {
      for (final a in _articles.values.toList()) {
        if (a.spaceId == spaceId) _put(a.copyWith(spaceId: s.name));
      }
    }
    _rebuildSpaces();
    return _spaceFor(s.name);
  }

  // ── order ───────────────────────────────────────────────────────────────

  /// Puts the sibling pages [ids] in this order, on the server and here.
  Future<void> reorder(List<String> ids) async {
    final before = {for (final id in ids) id: _articles[id]?.sortOrder};
    for (var i = 0; i < ids.length; i++) {
      final a = _articles[ids[i]];
      if (a != null) _put(a.copyWith(sortOrder: i));
    }
    try {
      await _articleApi.orderArticles(ids);
    } catch (_) {
      for (final e in before.entries) {
        final a = _articles[e.key];
        if (a != null && e.value != null) {
          _put(a.copyWith(sortOrder: e.value));
        }
      }
      rethrow;
    }
  }

  // ── history ─────────────────────────────────────────────────────────────

  Future<PageResult<ArticleVersion>> versions(
    String id, {
    int page = 0,
    int size = 20,
  }) => _articleApi.versions(id, page: page, size: size);

  Future<ArticleVersion> version(String id, int number) =>
      _articleApi.version(id, number);

  Future<List<String>> contributors(String id) => _articleApi.contributors(id);

  /// Brings back version [number] of [id] as its newest state.
  Future<KbArticle> restoreVersion(String id, int number) async {
    final kb = _toKbArticle(await _articleApi.restoreVersion(id, number));
    _put(kb);
    return kb;
  }

  // ── favourites and recently opened ──────────────────────────────────────

  final List<String> _starred = [];
  final List<String> _recent = [];

  /// Favourite pages the reader still sees, newest first.
  List<KbArticle> get starred => [for (final id in _starred) ?_articles[id]];

  /// Recently opened pages the reader still sees, newest first.
  List<KbArticle> get recent => [for (final id in _recent) ?_articles[id]];

  bool isStarred(String id) => _starred.contains(id);

  /// Loads the reader's favourites and recently opened pages. Best effort:
  /// an older server without the endpoint leaves both lists empty.
  Future<void> loadMarks() async {
    final epoch = _epoch;
    try {
      final marks = await _articleApi.marks();
      if (epoch != _epoch) return;
      _starred
        ..clear()
        ..addAll(marks.starred.map((m) => m.id));
      _recent
        ..clear()
        ..addAll(marks.recent.map((m) => m.id));
    } on ApiFailure {
      // Keep what is there.
    }
  }

  /// Stars or unstars [id]; the list changes at once and goes back when the
  /// server refuses.
  Future<void> setStarred(String id, {required bool starred}) async {
    final was = _starred.contains(id);
    if (was == starred) return;
    starred ? _starred.insert(0, id) : _starred.remove(id);
    try {
      await _articleApi.star(id, starred: starred);
    } catch (_) {
      starred ? _starred.remove(id) : _starred.insert(0, id);
      rethrow;
    }
  }

  /// Notes that the reader opened [id]. Nothing breaks when the server does
  /// not hear of it.
  Future<void> recordView(String id) async {
    _recent
      ..remove(id)
      ..insert(0, id);
    try {
      await _articleApi.viewed(id);
    } on ApiFailure {
      // The recent list is a convenience.
    }
  }

  /// Whether the reader may delete [spaceId]: a persisted backend space (not one
  /// merely derived from an article's `space` value) that the server says is
  /// theirs to manage.
  bool canManageSpace(String spaceId) =>
      _backendSpaces[spaceId]?.canManage ?? false;

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

/// What [KnowledgeRepository.reload] hands to an isolate of one page: its
/// document only when it has a smart link, and what the search reads.
typedef _PageText = ({
  String id,
  String? doc,
  String space,
  List<String> labels,
  String body,
});

/// Links by page id, and the search text by page id (empty: made lazily).
typedef _Prepared = ({
  Map<String, List<String>> links,
  Map<String, String> hay,
});
