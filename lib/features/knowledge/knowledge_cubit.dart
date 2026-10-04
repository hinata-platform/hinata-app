import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/user_repository.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';

/// The Knowledge Base screen's intents: every write to a page or a space, and
/// the backend issues and names its smart links resolve against.
///
/// Holds no state of its own. The pages and spaces live in the shared
/// [KnowledgeRepository] cache, which the tree, the reader and the editor read
/// synchronously while they build; [store] hands it to them as before.
class KnowledgeCubit extends Cubit<void> {
  KnowledgeCubit(this._knowledge, this._issues, this._users) : super(null);

  final KnowledgeRepository _knowledge;
  final IssueRepository _issues;
  final UserRepository _users;

  /// The shared page and space cache the screen renders from.
  KnowledgeRepository get store => _knowledge;

  /// Overlays the persisted edits on the app-wide cache; idempotent.
  Future<void> init() => _knowledge.init();

  /// Every issue the reader can see and the member directory, read one after
  /// the other, so `{{issue:…}}` tokens and the `@` menu resolve.
  Future<({List<Issue> issues, List<DirectoryUser> users})>
  linkTargets() async {
    final issues = await _issues.allIssues();
    final users = await _users.users();
    return (issues: issues, users: users);
  }

  /// The issue whose readable id is exactly [readableId], if one exists.
  Future<Issue?> findIssue(String readableId) async {
    final res = await _issues.issues(query: readableId, size: 20);
    return res.issues.where((i) => i.readableId == readableId).firstOrNull;
  }

  Future<KbArticle> moveArticle(
    String id, {
    String? parentId,
    String? spaceId,
  }) => _knowledge.moveArticle(id, parentId: parentId, spaceId: spaceId);

  Future<KbArticle> placeArticle(
    String id, {
    String? projectId,
    String? teamId,
  }) => _knowledge.placeArticle(id, projectId: projectId, teamId: teamId);

  Future<void> deleteArticle(String id) => _knowledge.deleteArticle(id);

  Future<KbSpace> createSpace({
    required String name,
    required String icon,
    required int hue,
    String? description,
  }) => _knowledge.createSpace(
    name: name,
    icon: icon,
    hue: hue,
    description: description,
  );

  Future<void> deleteSpace(String spaceId) => _knowledge.deleteSpace(spaceId);

  Future<KbArticle> createArticle({
    required String title,
    required String doc,
    required String spaceId,
    String? parentId,
    String? projectId,
    String? teamId,
  }) => _knowledge.createArticle(
    title: title,
    doc: doc,
    spaceId: spaceId,
    parentId: parentId,
    projectId: projectId,
    teamId: teamId,
  );

  Future<KbArticle> saveEdit(
    String id, {
    required String title,
    required String doc,
    required String spaceId,
  }) => _knowledge.saveEdit(id, title: title, doc: doc, spaceId: spaceId);
}
