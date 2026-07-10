import '../api/api_client.dart';
import '../models/git_connection.dart';
import '../models/git_dev_info.dart';
import '../models/work_models.dart';

/// Git integration: per-project repository connection + automation, and
/// per-issue development information. OAuth is brokered server-side; the
/// client never sees a token.
class GitRepository {
  GitRepository(this._api);

  final ApiClient _api;

  /// Kicks off the real OAuth flow for [provider]; returns the consent URL to
  /// open + the `state` to poll (or `available:false` when no provider app is
  /// configured, in which case the client uses the URL + token method).
  Future<GitOAuthStart> gitOAuthStart(
    String projectId,
    String provider,
  ) async => GitOAuthStart.fromJson(
    await _api.post(
          '/api/v1/projects/$projectId/git/oauth/start',
          body: {'provider': provider},
        )
        as Map<String, dynamic>,
  );

  /// Polls the server-side OAuth session (by [state]) for completion.
  Future<GitOAuthSessionStatus> gitOAuthSession(String state) async =>
      GitOAuthSessionStatus.fromJson(
        await _api.get('/api/v1/git/oauth/session/$state')
            as Map<String, dynamic>,
      );

  /// Owners (org / group / workspace) the authorized account exposes.
  Future<List<GitOwner>> gitOwners(
    String projectId,
    String provider, {
    String? state,
  }) async =>
      ((await _api.get(
                '/api/v1/projects/$projectId/git/owners',
                query: {'provider': provider, 'state': ?state},
              ))
              as List<dynamic>)
          .map((o) => GitOwner.fromJson(o as Map<String, dynamic>))
          .toList();

  /// Repositories under [owner], optionally filtered by [query].
  Future<List<GitRepo>> gitRepos(
    String projectId,
    String provider,
    String owner, {
    String? query,
    String? state,
  }) async =>
      ((await _api.get(
                '/api/v1/projects/$projectId/git/repos',
                query: {
                  'provider': provider,
                  'owner': owner,
                  if (query != null && query.isNotEmpty) 'q': query,
                  'state': ?state,
                },
              ))
              as List<dynamic>)
          .map((r) => GitRepo.fromJson(r as Map<String, dynamic>))
          .toList();

  /// Binds the chosen repo to the project; returns the updated project.
  Future<Project> gitConnect(
    String projectId, {
    required String provider,
    required String owner,
    required String repo,
    String? state,
  }) async => Project.fromJson(
    await _api.post(
          '/api/v1/projects/$projectId/git/connect',
          body: {
            'provider': provider,
            'owner': owner,
            'repo': repo,
            'state': ?state,
          },
        )
        as Map<String, dynamic>,
  );

  /// Self-managed fallback — connect with a repo URL + access token.
  Future<Project> gitConnectToken(
    String projectId, {
    required String repoUrl,
    required String token,
  }) async => Project.fromJson(
    await _api.post(
          '/api/v1/projects/$projectId/git/connect-token',
          body: {'repoUrl': repoUrl, 'token': token},
        )
        as Map<String, dynamic>,
  );

  Future<Project> gitDisconnect(String projectId, {String? repoId}) async {
    final q = repoId == null
        ? ''
        : '?repoId=${Uri.encodeQueryComponent(repoId)}';
    return Project.fromJson(
      await _api.delete('/api/v1/projects/$projectId/git$q')
          as Map<String, dynamic>,
    );
  }

  Future<Project> gitResync(String projectId, {String? repoId}) async {
    final q = repoId == null
        ? ''
        : '?repoId=${Uri.encodeQueryComponent(repoId)}';
    return Project.fromJson(
      await _api.post('/api/v1/projects/$projectId/git/resync$q')
          as Map<String, dynamic>,
    );
  }

  Future<Project> gitSetAutomation(
    String projectId,
    GitAutomation automation,
  ) async => Project.fromJson(
    await _api.patch(
          '/api/v1/projects/$projectId/git/automation',
          body: automation.toJson(),
        )
        as Map<String, dynamic>,
  );

  Future<Project> gitSetBranchTemplate(
    String projectId,
    String template,
  ) async => Project.fromJson(
    await _api.patch(
          '/api/v1/projects/$projectId/git/branch-template',
          body: {'branchTemplate': template},
        )
        as Map<String, dynamic>,
  );

  /// Development information (branches/commits/PRs/builds) for an issue key.
  Future<DevInfo> gitDevInfo(String issueKey) async => DevInfo.fromJson(
    await _api.get('/api/v1/issues/$issueKey/dev-info') as Map<String, dynamic>,
  );

  /// Merges a PR/MR from the Development panel; the server applies the project's
  /// `prMerged` automation and returns the updated dev-info + issue.
  Future<({DevInfo devInfo, Issue issue})> gitMergePr(
    String issueKey,
    int number,
  ) async {
    final json =
        await _api.post('/api/v1/issues/$issueKey/dev-info/prs/$number/merge')
            as Map<String, dynamic>;
    return (
      devInfo: DevInfo.fromJson(json['devInfo'] as Map<String, dynamic>),
      issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
    );
  }

  /// Marks a draft PR/MR ready for review; applies the `prOpened` automation.
  Future<({DevInfo devInfo, Issue issue})> gitReadyPr(
    String issueKey,
    int number,
  ) async {
    final json =
        await _api.post('/api/v1/issues/$issueKey/dev-info/prs/$number/ready')
            as Map<String, dynamic>;
    return (
      devInfo: DevInfo.fromJson(json['devInfo'] as Map<String, dynamic>),
      issue: Issue.fromJson(json['issue'] as Map<String, dynamic>),
    );
  }
}
