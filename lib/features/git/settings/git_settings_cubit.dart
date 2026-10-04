import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/git_connection.dart';
import '../../../core/models/git_dev_info.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/git_repository.dart';

/// A project's repository connection: the connect wizard, the settings
/// section and the issue rail's branch template.
///
/// Holds no state of its own. Each screen keeps its optimistic overrides and
/// busy flags where they were, and every write answers with the updated
/// [Project], which the screen hands to its parent.
class GitSettingsCubit extends Cubit<void> {
  GitSettingsCubit(this._git) : super(null);

  final GitRepository _git;

  Future<GitOAuthStart> oauthStart(String projectId, String provider) =>
      _git.gitOAuthStart(projectId, provider);

  Future<GitOAuthSessionStatus> oauthSession(String state) =>
      _git.gitOAuthSession(state);

  Future<List<GitOwner>> owners(
    String projectId,
    String provider, {
    String? state,
  }) => _git.gitOwners(projectId, provider, state: state);

  Future<List<GitRepo>> repos(
    String projectId,
    String provider,
    String owner, {
    String? state,
  }) => _git.gitRepos(projectId, provider, owner, state: state);

  Future<Project> connect(
    String projectId, {
    required String provider,
    required String owner,
    required String repo,
    String? state,
  }) => _git.gitConnect(
    projectId,
    provider: provider,
    owner: owner,
    repo: repo,
    state: state,
  );

  Future<Project> connectToken(
    String projectId, {
    required String repoUrl,
    required String token,
  }) => _git.gitConnectToken(projectId, repoUrl: repoUrl, token: token);

  Future<Project> disconnect(String projectId, {String? repoId}) =>
      _git.gitDisconnect(projectId, repoId: repoId);

  Future<Project> resync(String projectId, {String? repoId}) =>
      _git.gitResync(projectId, repoId: repoId);

  Future<Project> setAutomation(String projectId, GitAutomation automation) =>
      _git.gitSetAutomation(projectId, automation);

  Future<Project> setBranchTemplate(String projectId, String template) =>
      _git.gitSetBranchTemplate(projectId, template);
}
