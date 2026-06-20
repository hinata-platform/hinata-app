import 'package:flutter/widgets.dart';

import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../knowledge/data/knowledge_models.dart' show typeMeta;
import '../knowledge/data/knowledge_repository.dart';
import '../knowledge/knowledge_link_resolver.dart'
    show smartDocFromArticle, smartIssueFromReal;
import '../knowledge/knowledge_tokens.dart';
import '../knowledge/markdown/smart_link_resolver.dart';

/// [SmartLinkResolver] for the real issue detail. Issues and people resolve
/// against the backend (pre-loaded project issues + directory users); articles
/// (`{{doc:…}}`) still resolve against the shared [KnowledgeRepository] since
/// they live only in the KB. Clicks delegate to the host (which owns the
/// `BuildContext`) to open the real issue sheet or navigate to the article.
class IssueLinkResolver implements SmartLinkResolver {
  IssueLinkResolver({
    required this.issuesByReadable,
    required this.users,
    required this.knowledgeRepo,
    required this.stateColorFor,
    required this.onOpenIssue,
    required this.onOpenDoc,
    this.onOpenUser,
  });

  /// Project issues keyed by readable id (e.g. `HIV-208`).
  final Map<String, Issue> issuesByReadable;
  final List<DirectoryUser> users;
  final KnowledgeRepository knowledgeRepo;
  final Color Function(String state) stateColorFor;
  final void Function(String readableId) onOpenIssue;
  final void Function(String articleId) onOpenDoc;
  final void Function(String userId)? onOpenUser;

  @override
  SmartIssue? issue(String id) {
    final it = issuesByReadable[id];
    if (it == null) return null;
    return smartIssueFromReal(it, stateColorFor, _nameFor);
  }

  String? _nameFor(String? userId) => userId == null
      ? null
      : users.where((u) => u.id == userId).firstOrNull?.displayName;

  @override
  SmartDoc? doc(String id) {
    final a = knowledgeRepo.articleById(id);
    if (a == null) return null;
    return smartDocFromArticle(knowledgeRepo, a);
  }

  @override
  SmartPerson? person(String id) {
    final u = users.where((u) => u.id == id).firstOrNull;
    if (u == null) return null;
    return SmartPerson(
      id: u.id,
      name: u.displayName,
      subtitle: '@${u.username}',
    );
  }

  @override
  void openIssue(String id) => onOpenIssue(id);

  @override
  void openDoc(String id) => onOpenDoc(id);

  @override
  void openPerson(String id) => onOpenUser?.call(id);

  @override
  List<MentionCandidate> mentions(String query, {required bool commentMode}) {
    final q = query.toLowerCase();
    final res = <MentionCandidate>[];

    for (final it in issuesByReadable.values) {
      final hay = '${it.readableId} ${it.title}'.toLowerCase();
      if (q.isEmpty || hay.contains(q)) {
        final tm = typeMeta(it.type);
        res.add(
          MentionCandidate(
            kind: 'issue',
            id: it.readableId,
            title: it.title,
            sub: it.readableId,
            issueType: tm.icon,
            issueColor: KbTokens.issueChipColor(tm.hue),
          ),
        );
      }
    }
    for (final a in knowledgeRepo.articles) {
      final sp = knowledgeRepo.spaceById(a.spaceId);
      final hay = '${a.title} ${sp?.name ?? ''}'.toLowerCase();
      if (q.isEmpty || hay.contains(q)) {
        res.add(
          MentionCandidate(
            kind: 'doc',
            id: a.id,
            title: a.title,
            sub: sp?.name ?? '',
            icon: a.icon,
          ),
        );
      }
    }
    for (final u in users) {
      final hay = '${u.displayName} ${u.username}'.toLowerCase();
      if (q.isEmpty || hay.contains(q)) {
        res.add(
          MentionCandidate(
            kind: 'user',
            id: u.id,
            title: u.displayName,
            sub: '@${u.username}',
          ),
        );
      }
    }
    return res;
  }
}
