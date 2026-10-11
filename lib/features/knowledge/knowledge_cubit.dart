import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/paged_cubit.dart' show PageResult;
import '../../core/models/content_models.dart' show ArticleVersion;
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/user_repository.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_state.dart';

/// The knowledge base's intents: loading, every write to a page or a space,
/// favourites and the history.
///
/// A write goes to the shared [KnowledgeRepository] and then moves
/// [KnowledgeState.revision] on, which is what the views rebuild on. Failures
/// come back to the caller as the repository threw them, so the view can
/// say what went wrong where it happened.
class KnowledgeCubit extends Cubit<KnowledgeState> {
  KnowledgeCubit(this._knowledge, this._issues, this._users)
    : super(const KnowledgeState());

  final KnowledgeRepository _knowledge;
  final IssueRepository _issues;
  final UserRepository _users;

  /// The shared page and space cache the views render from.
  KnowledgeRepository get store => _knowledge;

  /// Loads the pages once (idempotent) and then what smart links resolve
  /// against. The views can show the pages before the issues are in.
  Future<void> load() async {
    try {
      await _knowledge.init();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: KnowledgeStatus.ready,
          revision: state.revision + 1,
        ),
      );
    } catch (_) {
      if (!isClosed) emit(state.copyWith(status: KnowledgeStatus.failure));
      return;
    }
    await _loadLinkTargets();
  }

  /// Reads everything again, after a failure or on pull-to-refresh.
  Future<void> reload() async {
    emit(state.copyWith(status: KnowledgeStatus.loading));
    try {
      await _knowledge.reload();
      if (!isClosed) {
        emit(
          state.copyWith(
            status: KnowledgeStatus.ready,
            revision: state.revision + 1,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) emit(state.copyWith(status: KnowledgeStatus.failure));
    }
  }

  /// Every issue the reader can see and the member directory, so `{{issue:…}}`
  /// links and the `@` menu resolve. Best effort: links show their stored
  /// label until this arrives.
  Future<void> _loadLinkTargets() async {
    try {
      final issues = await _issues.allIssues();
      final users = await _users.users();
      if (isClosed) return;
      emit(
        state.copyWith(
          issuesByReadable: {
            for (final i in issues)
              for (final key in i.allReadableIds) key: i,
          },
          userNames: {for (final u in users) u.id: u.displayName},
        ),
      );
    } catch (_) {
      // The menu simply shows no issues until the next visit.
    }
  }

  /// The issue whose readable id is exactly [readableId], if one exists.
  Future<Issue?> findIssue(String readableId) async {
    final res = await _issues.issues(query: readableId, size: 20);
    return res.issues.where((i) => i.readableId == readableId).firstOrNull;
  }

  Future<T> _changed<T>(Future<T> write) async {
    final result = await write;
    if (!isClosed) emit(state.copyWith(revision: state.revision + 1));
    return result;
  }

  // ── pages ──

  Future<KbArticle> createArticle({
    required String title,
    required String doc,
    required String spaceId,
    String? parentId,
    String? projectId,
    String? teamId,
    List<String> labels = const [],
  }) => _changed(
    _knowledge.createArticle(
      title: title,
      doc: doc,
      spaceId: spaceId,
      parentId: parentId,
      projectId: projectId,
      teamId: teamId,
      labels: labels,
    ),
  );

  Future<KbArticle> saveEdit(
    String id, {
    required String title,
    required String doc,
    required String spaceId,
    List<String>? labels,
  }) => _changed(
    _knowledge.saveEdit(
      id,
      title: title,
      doc: doc,
      spaceId: spaceId,
      labels: labels,
    ),
  );

  Future<KbArticle> moveArticle(
    String id, {
    String? parentId,
    String? spaceId,
  }) => _changed(
    _knowledge.moveArticle(id, parentId: parentId, spaceId: spaceId),
  );

  Future<KbArticle> placeArticle(
    String id, {
    String? projectId,
    String? teamId,
  }) => _changed(
    _knowledge.placeArticle(id, projectId: projectId, teamId: teamId),
  );

  Future<void> deleteArticle(String id) =>
      _changed(_knowledge.deleteArticle(id));

  /// Moves [id] one place up ([delta] −1) or down (+1) among its siblings.
  Future<void> shift(String id, int delta) async {
    final page = _knowledge.articleById(id);
    if (page == null) return;
    final siblings = page.parentId == null
        ? _knowledge.rootsInSpace(page.spaceId)
        : _knowledge.childrenOf(page.parentId!);
    final from = siblings.indexWhere((a) => a.id == id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= siblings.length) return;
    final ids = [for (final a in siblings) a.id]
      ..removeAt(from)
      ..insert(to, id);
    await reorder(ids);
  }

  /// Puts the sibling pages [ids] in this order.
  Future<void> reorder(List<String> ids) async {
    // Shown at once; a refusal puts the old order back and says so.
    final pending = _knowledge.reorder(ids);
    emit(state.copyWith(revision: state.revision + 1));
    try {
      await pending;
    } finally {
      if (!isClosed) emit(state.copyWith(revision: state.revision + 1));
    }
  }

  // ── favourites ──

  Future<void> setStarred(String id, {required bool starred}) async {
    final pending = _knowledge.setStarred(id, starred: starred);
    emit(state.copyWith(revision: state.revision + 1));
    try {
      await pending;
    } finally {
      if (!isClosed) emit(state.copyWith(revision: state.revision + 1));
    }
  }

  /// Notes that the reader opened [id]. The recent list on the start page
  /// follows; the page itself does not need to rebuild for it.
  Future<void> recordView(String id) => _knowledge.recordView(id);

  // ── history ──

  Future<PageResult<ArticleVersion>> versions(
    String id, {
    int page = 0,
    int size = 20,
  }) => _knowledge.versions(id, page: page, size: size);

  Future<ArticleVersion> version(String id, int number) =>
      _knowledge.version(id, number);

  Future<List<String>> contributors(String id) => _knowledge.contributors(id);

  Future<KbArticle> restoreVersion(String id, int number) =>
      _changed(_knowledge.restoreVersion(id, number));

  // ── spaces ──

  Future<KbSpace> createSpace({
    required String name,
    required String icon,
    required int hue,
    String? description,
  }) => _changed(
    _knowledge.createSpace(
      name: name,
      icon: icon,
      hue: hue,
      description: description,
    ),
  );

  Future<KbSpace> updateSpace(
    String spaceId, {
    required String name,
    required String icon,
    required int hue,
    required String description,
  }) => _changed(
    _knowledge.updateSpace(
      spaceId,
      name: name,
      icon: icon,
      hue: hue,
      description: description,
    ),
  );

  Future<void> deleteSpace(String spaceId) =>
      _changed(_knowledge.deleteSpace(spaceId));
}
