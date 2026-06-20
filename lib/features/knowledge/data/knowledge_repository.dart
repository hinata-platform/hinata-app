import '../../../core/api/hinata_repository.dart';
import '../../../core/models/content_models.dart';
import '../../../core/models/core_models.dart';
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
  KnowledgeRepository(this._backend);

  final HinataRepository _backend;

  final Map<String, KbArticle> _articles = {};
  final Map<String, KbUser> _users = {};
  final List<KbSpace> _spaces = [];
  KbUser? _me;
  bool _loaded = false;

  /// Presentational metadata for known spaces (icon · hue · description). The
  /// space *names* are real (they live on the articles); only the chrome is
  /// configured here.
  static const Map<String, ({String icon, int hue, String desc})> _spaceCatalog =
      {
    'Engineering': (
      icon: 'code-xml',
      hue: 250,
      desc: 'Architecture, services, release & on-call runbooks.'
    ),
    'Product': (
      icon: 'compass',
      hue: 155,
      desc: 'Specs, workflow rules and decision records.'
    ),
    'Design': (
      icon: 'palette',
      hue: 300,
      desc: 'Brand, motion and the Hive design system.'
    ),
    'Operations': (
      icon: 'server-cog',
      hue: 200,
      desc: 'Infra, deploy and observability.'
    ),
  };

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
      _backend.articles(all: true),
      _backend.users(),
    ]);
    final articles = results[0] as List<Article>;
    final dirUsers = results[1] as List<DirectoryUser>;

    _users
      ..clear()
      ..addEntries(dirUsers.map((u) => MapEntry(u.id, _toKbUser(u))));
    try {
      final me = await _backend.me();
      _me = KbUser(
        id: me.id,
        name: me.displayName,
        title: me.title ?? '',
        hue: _hueFor(me.id),
      );
    } catch (_) {
      // Non-critical — `me` falls back to the first directory user.
    }

    _articles
      ..clear()
      ..addEntries(articles.map((a) => MapEntry(a.id, _toKbArticle(a))));
    _rebuildSpaces();
    _loaded = true;
  }

  void _rebuildSpaces() {
    final names = <String>{for (final a in _articles.values) a.spaceId}
      ..removeWhere((n) => n.isEmpty);
    // Stable order: catalog order first, then any extra spaces alphabetically.
    final ordered = <String>[
      ..._spaceCatalog.keys.where(names.contains),
      ...(names.where((n) => !_spaceCatalog.containsKey(n)).toList()..sort()),
    ];
    _spaces
      ..clear()
      ..addAll(ordered.map(_spaceFor));
    if (_spaces.isEmpty) {
      // Never leave the home/tree without a space to land on.
      _spaces.addAll(_spaceCatalog.keys.map(_spaceFor));
    }
  }

  // ── mappers ───────────────────────────────────────────────────────────────

  KbUser _toKbUser(DirectoryUser u) => KbUser(
        id: u.id,
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
    );
  }

  KbSpace _spaceFor(String name) {
    final meta = _spaceCatalog[name] ??
        (icon: 'file-text', hue: 250, desc: '');
    final key = name.length >= 3
        ? name.substring(0, 3).toUpperCase()
        : name.toUpperCase();
    return KbSpace(
      id: name,
      key: key,
      name: name,
      hue: meta.hue,
      icon: meta.icon,
      desc: meta.desc,
    );
  }

  static int _hueFor(String id) =>
      id.isEmpty ? 248 : (id.hashCode.abs() % 360);

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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[t.month - 1]} ${t.day}, ${t.year}';
  }

  // ── lookups ─────────────────────────────────────────────────────────────

  KbUser? userById(String id) => _users[id];
  KbSpace? spaceById(String id) =>
      _spaces.cast<KbSpace?>().firstWhere((s) => s?.id == id, orElse: () => null);
  KbArticle? articleById(String id) => _articles[id];

  List<KbUser> get users => _users.values.toList(growable: false);
  List<KbSpace> get spaces => List.unmodifiable(_spaces);
  List<KbArticle> get articles => _articles.values.toList(growable: false);

  List<KbArticle> articlesInSpace(String spaceId) =>
      articles.where((a) => a.spaceId == spaceId).toList();

  int articleCountInSpace(String spaceId) =>
      articles.where((a) => a.spaceId == spaceId).length;

  // ── derived bidirectional links ───────────────────────────────────────────

  static final _issueTokenRe = RegExp(r'\{\{issue:([A-Z]+-\d+)\}\}');

  /// Readable issue ids referenced by [body] (`{{issue:KEY-N}}`), first-seen
  /// order. The issues themselves are resolved against the real backend.
  List<String> issueIdsIn(String body) {
    final seen = <String>{};
    final out = <String>[];
    for (final m in _issueTokenRe.allMatches(body)) {
      final id = m.group(1)!;
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  /// All articles that mention [issueReadableId] — the issue's "Documented in".
  List<KbArticle> articlesForIssue(String issueReadableId) {
    final out = <KbArticle>[];
    for (final a in articles) {
      for (final m in _issueTokenRe.allMatches(a.body)) {
        if (m.group(1) == issueReadableId) {
          out.add(a);
          break;
        }
      }
    }
    return out;
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

  Future<KbArticle> saveEdit(
    String id, {
    required String title,
    required String body,
    required String spaceId,
  }) async {
    final existing = _articles[id];
    final saved = await _backend.saveArticle(
      id: id,
      title: title,
      content: body,
      space: spaceId,
      icon: existing?.icon,
      tags: existing?.labels,
    );
    final kb = _toKbArticle(saved);
    _articles[id] = kb;
    _rebuildSpaces();
    return kb;
  }

  Future<KbArticle> createArticle({
    required String title,
    required String body,
    required String spaceId,
    String? parentId,
  }) async {
    final saved = await _backend.saveArticle(
      title: title,
      content: body,
      space: spaceId,
      parentId: parentId,
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
    final saved = await _backend.moveArticle(
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

  Future<void> deleteArticle(String id) async {
    await _backend.deleteArticle(id);
    _articles.remove(id);
    _rebuildSpaces();
  }

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
