import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/api/api_client.dart';
import '../../core/models/core_models.dart';
import '../../core/models/issue_detail.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/comment_repository.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/media_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';
import '../knowledge/data/knowledge_models.dart' show KbArticle;
import '../knowledge/data/knowledge_repository.dart';
import 'comments/comment_copy.dart' as comment_copy;

/// Where the issue detail sends every request it makes: the issue itself, its
/// comments, work log, hierarchy and activity, and the directory, project and
/// knowledge-base lookups around them.
///
/// Holds no state of its own. The detail body already keeps a large, carefully
/// sequenced state — optimistic edits, paging windows, live re-syncs — and
/// awaits each of these calls where it awaited the repository before, so
/// every answer and every [ApiFailure] reaches it unchanged. The ids stay
/// arguments rather than fields: the body acts on its children and on other
/// issues too, not only on the one it shows.
class IssueDetailCubit extends Cubit<void> {
  IssueDetailCubit({
    required IssueRepository issues,
    required CommentRepository comments,
    required ProjectRepository projects,
    required UserRepository users,
    required MediaRepository media,
    required this.knowledge,
  }) : _issues = issues,
       _comments = comments,
       _projects = projects,
       _users = users,
       _media = media,
       super(null);

  final IssueRepository _issues;
  final CommentRepository _comments;
  final ProjectRepository _projects;
  final UserRepository _users;
  final MediaRepository _media;

  /// The shared article cache. Smart-link chips and the "Documented in" list
  /// look articles and spaces up in it synchronously while they build, so it
  /// is handed to them as it is; the reads that go to the server go through
  /// [documentedIn].
  final KnowledgeRepository knowledge;

  /// The server the issue lives on, for the links it hands out.
  String get apiBaseUrl => _issues.apiBaseUrl;

  // ── The issue ────────────────────────────────────────────────────────────

  Future<IssueDetail> issueDetail(
    String id, {
    int commentSize = 30,
    String commentSort = 'newest',
  }) => _issues.issueDetail(
    id,
    commentSize: commentSize,
    commentSort: commentSort,
  );

  Future<Issue> issue(String id) => _issues.issue(id);

  Future<Issue> updateIssue(String id, Map<String, dynamic> patch) =>
      _issues.updateIssue(id, patch);

  Future<Issue> createIssue(Map<String, dynamic> body) =>
      _issues.createIssue(body);

  Future<Issue> archiveIssue(String id) => _issues.archiveIssue(id);

  Future<Issue> unarchiveIssue(String id) => _issues.unarchiveIssue(id);

  Future<void> deleteIssue(String id) => _issues.deleteIssue(id);

  Future<({List<IssueActivity> items, int total})> issueActivity(
    String issueId, {
    int page = 0,
  }) => _issues.issueActivity(issueId, page: page);

  Future<IssueHierarchy> issueHierarchy(String id) =>
      _issues.issueHierarchy(id);

  /// The server-rendered export of [issueId] in [extension]'s format.
  Future<Uint8List> export(String issueId, String extension) =>
      _issues.export(issueId, extension);

  /// Uploads [file] onto [issueId] as an attachment.
  Future<Issue> uploadAttachment(String issueId, MultipartFile file) =>
      _issues.uploadAttachment(issueId, file);

  // ── Other issues ─────────────────────────────────────────────────────────

  Future<List<Issue>> resolveIssues(List<String> keys) =>
      _issues.resolveIssues(keys);

  Future<List<IssueRef>> mentionSearch({
    String? projectId,
    required String query,
  }) => _issues.mentionSearch(projectId: projectId, query: query);

  /// The first [size] issues anywhere matching [query].
  Future<({List<Issue> issues, int total})> searchIssues(
    String query, {
    required int size,
  }) => _issues.issues(query: query, size: size);

  // ── Work log ─────────────────────────────────────────────────────────────

  Future<({List<WorkItem> items, int total})> workItemsPage(
    String issueId, {
    int page = 0,
    int size = 50,
  }) => _issues.workItemsPage(issueId, page: page, size: size);

  Future<void> deleteWorkItem(String id) => _issues.deleteWorkItem(id);

  // ── Comments ─────────────────────────────────────────────────────────────

  /// The live `changed` pings for [issueId]'s comments.
  Future<Stream<List<int>>> commentEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => _comments.commentEventStream(issueId, cancelToken: cancelToken);

  Future<({List<IssueComment> items, int total})> comments(
    String issueId, {
    int page = 0,
    int size = 30,
    String sort = 'newest',
  }) => _comments.comments(issueId, page: page, size: size, sort: sort);

  Future<List<IssueComment>> pinnedComments(String issueId) =>
      _comments.pinnedComments(issueId);

  Future<({List<IssueComment> items, int total})> commentReplies(
    String issueId,
    String rootId, {
    int page = 0,
    int size = 10,
  }) => _comments.commentReplies(issueId, rootId, page: page, size: size);

  Future<IssueComment> addComment(
    String issueId,
    String text, {
    String? replyToId,
    String? doc,
  }) => _comments.addComment(issueId, text, replyToId: replyToId, doc: doc);

  Future<IssueComment> addVoiceComment(
    String issueId, {
    required List<int> bytes,
    required String mime,
    required int durationMs,
    required List<int> peaks,
    String? replyToId,
  }) => _comments.addVoiceComment(
    issueId,
    bytes: bytes,
    mime: mime,
    durationMs: durationMs,
    peaks: peaks,
    replyToId: replyToId,
  );

  Future<({List<int> bytes, String contentType})?> voiceCommentAudio(
    String issueId,
    String commentId,
  ) => _comments.voiceCommentAudio(issueId, commentId);

  Future<IssueComment> editComment(
    String issueId,
    String commentId,
    String text,
  ) => _comments.editComment(issueId, commentId, text);

  Future<void> deleteComment(String issueId, String commentId) =>
      _comments.deleteComment(issueId, commentId);

  Future<IssueComment> reactToComment(
    String issueId,
    String commentId,
    String emoji,
  ) => _comments.reactToComment(issueId, commentId, emoji);

  Future<IssueComment> pinComment(
    String issueId,
    String commentId,
    bool pinned,
  ) => _comments.pinComment(issueId, commentId, pinned);

  /// Copies [comment] to the clipboard — as the picture itself when it is
  /// nothing but one.
  Future<comment_copy.CommentCopyKind> copyComment(IssueComment comment) =>
      comment_copy.copyComment(_media, comment);

  /// Uploads [file] as inline media for a comment.
  Future<({String url, String? blurHash})> uploadMedia(MultipartFile file) =>
      _media.uploadMedia(file);

  // ── Around the issue ─────────────────────────────────────────────────────

  Future<List<DirectoryUser>> users() => _users.users();

  Future<void> deleteProjectLabel(String projectId, String label) =>
      _projects.deleteProjectLabel(projectId, label);

  Future<DateTime?> resolveOffset(
    String projectId, {
    required RelativeDate offset,
  }) => _projects.resolveOffset(projectId, offset: offset);

  /// The knowledge-base articles that mention [issueReadableId], once the
  /// article cache is seeded.
  Future<List<KbArticle>> documentedIn(String issueReadableId) async {
    await knowledge.init();
    return knowledge.articlesReferencingIssue(issueReadableId);
  }
}
