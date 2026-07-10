import 'package:dio/dio.dart';

import '../models/account_models.dart';
import '../models/admin_user_models.dart';
import '../models/audit_models.dart';
import '../models/content_models.dart';
import '../models/core_models.dart';
import '../models/deletion_models.dart';
import '../models/git_connection.dart';
import '../models/git_dev_info.dart';
import '../models/oauth_consent.dart';
import '../models/personal_access_token.dart';
import '../models/search_api.dart';
import '../models/team_models.dart';
import '../models/work_models.dart';
import '../repositories/repositories.dart';
import 'api_client.dart';

/// LEGACY facade over the domain repositories in `core/repositories/`.
///
/// The REST surface used to live here as one god class; it is now split into
/// per-domain repositories ([HinataRepositories]) that are provided app-wide
/// via `MultiRepositoryProvider`. This shim keeps the old call sites compiling
/// while they migrate — new code must inject the specific domain repository
/// (e.g. `context.read<IssueRepository>()`) instead of this class. Delete this
/// file once the last call site is migrated.
class HinataRepository {
  HinataRepository(ApiClient api)
    : _api = api,
      domains = HinataRepositories(api);

  final ApiClient _api;

  /// The split domain repositories this facade delegates to.
  final HinataRepositories domains;

  /// The configured backend base URL (e.g. `https://api.track.asta.hn`). Used
  /// to derive shareable web links to in-app resources.
  String get apiBaseUrl => _api.baseUrl;

  // --- Meta & setup ---------------------------------------------------------

  Future<ServerMeta> meta() => domains.meta.meta();

  Future<ServerProbe?> probeServer(String url) =>
      domains.meta.probeServer(url);

  Future<void> completeSetup({
    required String organizationName,
    required String adminEmail,
    required String adminUsername,
    required String adminDisplayName,
    required String adminPassword,
  }) => domains.meta.completeSetup(
    organizationName: organizationName,
    adminEmail: adminEmail,
    adminUsername: adminUsername,
    adminDisplayName: adminDisplayName,
    adminPassword: adminPassword,
  );

  Future<({List<int> bytes, bool isSvg})?> organizationLogo() =>
      domains.meta.organizationLogo();

  // --- Auth -----------------------------------------------------------------

  Future<LoginResult> login(String identifier, String password) =>
      domains.auth.login(identifier, password);

  Future<AuthUser> me() => domains.auth.me();

  Future<List<SsoProvider>> ssoProviders() => domains.auth.ssoProviders();

  Future<void> changePassword(String current, String next) =>
      domains.auth.changePassword(current, next);

  Future<({String email, String displayName})> inviteInfo(String token) =>
      domains.auth.inviteInfo(token);

  Future<({String access, String refresh})> acceptInvite(
    String token,
    String password,
  ) => domains.auth.acceptInvite(token, password);

  Future<({String access, String refresh})> acceptPasswordReset(
    String token,
    String password,
  ) => domains.auth.acceptPasswordReset(token, password);

  Future<void> register({
    required String email,
    required String username,
    required String displayName,
    required String password,
  }) => domains.auth.register(
    email: email,
    username: username,
    displayName: displayName,
    password: password,
  );

  Future<void> resendVerification(String email) =>
      domains.auth.resendVerification(email);

  Future<({bool pendingApproval, String? access, String? refresh})> verifyEmail(
    String token,
  ) => domains.auth.verifyEmail(token);

  Future<void> requestPasswordReset(String email) =>
      domains.auth.requestPasswordReset(email);

  Future<({String access, String refresh, AuthUser user})> verifyTwoFactor(
    String mfaToken,
    String code,
  ) => domains.auth.verifyTwoFactor(mfaToken, code);

  // --- Account (/me self-service) -------------------------------------------

  Future<Me> meAccount() => domains.account.meAccount();

  Future<Me> updateMyProfile({
    String? displayName,
    String? title,
    String? locale,
  }) => domains.account.updateMyProfile(
    displayName: displayName,
    title: title,
    locale: locale,
  );

  Future<String> uploadAvatar(
    MultipartFile file, {
    void Function(double pct)? onProgress,
  }) => domains.account.uploadAvatar(file, onProgress: onProgress);

  Future<void> deleteAvatar() => domains.account.deleteAvatar();

  Future<void> requestEmailChange(String newEmail) =>
      domains.account.requestEmailChange(newEmail);

  Future<void> sendPasswordReset() => domains.account.sendPasswordReset();

  Future<List<DeviceSession>> sessions() => domains.account.sessions();

  Future<void> revokeSession(String id) => domains.account.revokeSession(id);

  Future<void> revokeOtherSessions() => domains.account.revokeOtherSessions();

  Future<NotifPrefs> notificationPrefs() => domains.account.notificationPrefs();

  Future<NotifPrefs> saveNotificationPrefs(NotifPrefs prefs) =>
      domains.account.saveNotificationPrefs(prefs);

  Future<TotpSetup> beginTotpSetup() => domains.account.beginTotpSetup();

  Future<List<String>> verifyTotpSetup(String code) =>
      domains.account.verifyTotpSetup(code);

  Future<List<String>> regenerateRecoveryCodes(String code) =>
      domains.account.regenerateRecoveryCodes(code);

  Future<void> disableTotp(String code) => domains.account.disableTotp(code);

  Future<List<AccessTeam>> myTeams() => domains.account.myTeams();

  Future<List<AccessProject>> myProjects() => domains.account.myProjects();

  Future<void> requestDataReport() => domains.account.requestDataReport();

  Future<void> deleteMyAccount() => domains.account.deleteMyAccount();

  Future<List<PersonalAccessToken>> listPats() => domains.account.listPats();

  Future<CreatedPat> createPat({
    required String name,
    required List<String> scopes,
    int? ttlDays,
  }) => domains.account.createPat(name: name, scopes: scopes, ttlDays: ttlDays);

  Future<void> revokePat(String id) => domains.account.revokePat(id);

  Future<void> deletePat(String id) => domains.account.deletePat(id);

  Future<Stream<List<int>>> meEventStream({CancelToken? cancelToken}) =>
      domains.account.meEventStream(cancelToken: cancelToken);

  // --- OAuth 2.1 consent (MCP authorization) --------------------------------

  Future<OAuthConsentInfo> oauthConsentInfo(String requestId) =>
      domains.auth.oauthConsentInfo(requestId);

  Future<String> oauthConsentDecision(
    String requestId, {
    required bool approved,
    required List<String> grantedScopes,
  }) => domains.auth.oauthConsentDecision(
    requestId,
    approved: approved,
    grantedScopes: grantedScopes,
  );

  // --- Users ----------------------------------------------------------------

  Future<List<DirectoryUser>> users() => domains.users.users();

  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) => domains.users.searchUsers(query, page: page, size: size);

  // --- Projects -------------------------------------------------------------

  Future<List<Project>> projects({bool archived = false}) =>
      domains.projects.projects(archived: archived);

  Future<Project> project(String id) => domains.projects.project(id);

  Future<Map<String, int>> projectStateUsage(String id) =>
      domains.projects.projectStateUsage(id);

  Future<Project> createProject({
    required String key,
    required String name,
    String? description,
    String? color,
    String? leadId,
  }) => domains.projects.createProject(
    key: key,
    name: name,
    description: description,
    color: color,
    leadId: leadId,
  );

  Future<Project> updateProject(String id, Map<String, dynamic> patch) =>
      domains.projects.updateProject(id, patch);

  Future<void> deleteProjectLabel(String projectId, String label) =>
      domains.projects.deleteProjectLabel(projectId, label);

  // --- Issues ---------------------------------------------------------------

  Future<({List<Issue> issues, int total})> issues({
    String? projectId,
    String? state,
    String? assigneeId,
    String? sprintId,
    String? type,
    String? query,
    bool noSprint = false,
    int page = 0,
    int size = 50,
  }) => domains.issues.issues(
    projectId: projectId,
    state: state,
    assigneeId: assigneeId,
    sprintId: sprintId,
    type: type,
    query: query,
    noSprint: noSprint,
    page: page,
    size: size,
  );

  Future<List<Issue>> allIssues({
    String? projectId,
    String? state,
    String? assigneeId,
    String? sprintId,
    String? query,
    bool noSprint = false,
  }) => domains.issues.allIssues(
    projectId: projectId,
    state: state,
    assigneeId: assigneeId,
    sprintId: sprintId,
    query: query,
    noSprint: noSprint,
  );

  Future<Issue> issue(String id) => domains.issues.issue(id);

  Future<IssueHierarchy> issueHierarchy(String id) =>
      domains.issues.issueHierarchy(id);

  Future<Issue> createIssue(Map<String, dynamic> body) =>
      domains.issues.createIssue(body);

  Future<Issue> updateIssue(String id, Map<String, dynamic> patch) =>
      domains.issues.updateIssue(id, patch);

  Future<void> deleteIssue(String id) => domains.issues.deleteIssue(id);

  Future<List<IssueLink>> issueLinks(String issueId) =>
      domains.issues.issueLinks(issueId);

  Future<List<IssueLink>> addIssueLinks(
    String issueId, {
    required String type,
    required bool outward,
    required List<String> targetIds,
  }) => domains.issues.addIssueLinks(
    issueId,
    type: type,
    outward: outward,
    targetIds: targetIds,
  );

  Future<List<IssueLink>> deleteIssueLink(String issueId, String linkId) =>
      domains.issues.deleteIssueLink(issueId, linkId);

  Future<Stream<List<int>>> issueLinkEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => domains.issues.issueLinkEventStream(issueId, cancelToken: cancelToken);

  Future<({List<IssueActivity> items, int total})> issueActivity(
    String issueId, {
    int page = 0,
    int size = 30,
  }) => domains.issues.issueActivity(issueId, page: page, size: size);

  // --- Comments ---------------------------------------------------------------

  Future<({List<IssueComment> items, int total})> comments(
    String issueId, {
    int page = 0,
    int size = 30,
    String sort = 'newest',
  }) => domains.comments.comments(issueId, page: page, size: size, sort: sort);

  Future<({List<IssueComment> items, int total})> commentReplies(
    String issueId,
    String rootId, {
    int page = 0,
    int size = 10,
  }) => domains.comments.commentReplies(issueId, rootId, page: page, size: size);

  Future<IssueComment> addComment(
    String issueId,
    String text, {
    String? replyToId,
  }) => domains.comments.addComment(issueId, text, replyToId: replyToId);

  Future<IssueComment> reactToComment(
    String issueId,
    String commentId,
    String emoji,
  ) => domains.comments.reactToComment(issueId, commentId, emoji);

  Future<IssueComment> pinComment(
    String issueId,
    String commentId,
    bool pinned,
  ) => domains.comments.pinComment(issueId, commentId, pinned);

  Future<List<IssueComment>> pinnedComments(String issueId) =>
      domains.comments.pinnedComments(issueId);

  Future<IssueComment> editComment(
    String issueId,
    String commentId,
    String text,
  ) => domains.comments.editComment(issueId, commentId, text);

  Future<void> deleteComment(String issueId, String commentId) =>
      domains.comments.deleteComment(issueId, commentId);

  Future<IssueComment> addVoiceComment(
    String issueId, {
    required List<int> bytes,
    required String mime,
    required int durationMs,
    required List<int> peaks,
    String? replyToId,
    CancelToken? cancelToken,
  }) => domains.comments.addVoiceComment(
    issueId,
    bytes: bytes,
    mime: mime,
    durationMs: durationMs,
    peaks: peaks,
    replyToId: replyToId,
    cancelToken: cancelToken,
  );

  Future<Stream<List<int>>> commentEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => domains.comments.commentEventStream(issueId, cancelToken: cancelToken);

  Future<({List<int> bytes, String contentType})?> voiceCommentAudio(
    String issueId,
    String commentId,
  ) => domains.comments.voiceCommentAudio(issueId, commentId);

  // --- Media & attachments -----------------------------------------------------

  Future<({List<int> bytes, String contentType})?> mediaBytes(String url) =>
      domains.media.mediaBytes(url);

  Future<Issue> uploadAttachment(
    String issueId,
    MultipartFile file, {
    void Function(double pct)? onProgress,
    CancelToken? cancelToken,
  }) => domains.issues.uploadAttachment(
    issueId,
    file,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  Future<String> uploadMedia(MultipartFile file, {CancelToken? cancelToken}) =>
      domains.media.uploadMedia(file, cancelToken: cancelToken);

  Future<String> attachmentDownloadUrl(String issueId, String attachmentId) =>
      domains.issues.attachmentDownloadUrl(issueId, attachmentId);

  Future<void> deleteAttachment(String issueId, String attachmentId) =>
      domains.issues.deleteAttachment(issueId, attachmentId);

  Future<Stream<List<int>>> attachmentEventStream(
    String issueId, {
    CancelToken? cancelToken,
  }) => domains.issues.attachmentEventStream(issueId, cancelToken: cancelToken);

  // --- Boards ---------------------------------------------------------------

  Future<List<AgileBoard>> boards({String? projectId}) =>
      domains.boards.boards(projectId: projectId);

  Future<AgileBoard> createBoard(
    String name,
    List<String> projectIds, {
    BoardType type = BoardType.kanban,
  }) => domains.boards.createBoard(name, projectIds, type: type);

  Future<AgileBoard> renameBoard(String boardId, String name) =>
      domains.boards.renameBoard(boardId, name);

  Future<BoardView> boardView(String boardId, {String? sprintId}) =>
      domains.boards.boardView(boardId, sprintId: sprintId);

  // --- Sprints --------------------------------------------------------------

  Future<List<Sprint>> sprints(String boardId, {bool includeArchived = false}) =>
      domains.sprints.sprints(boardId, includeArchived: includeArchived);

  Future<Sprint> createSprint({
    required String boardId,
    required String name,
    String? goal,
    DateTime? startDate,
    DateTime? endDate,
    int? capacityPoints,
  }) => domains.sprints.createSprint(
    boardId: boardId,
    name: name,
    goal: goal,
    startDate: startDate,
    endDate: endDate,
    capacityPoints: capacityPoints,
  );

  Future<List<Sprint>> sprintsForProject(String projectId) =>
      domains.sprints.sprintsForProject(projectId);

  Future<Sprint> updateSprint(String id, Map<String, dynamic> patch) =>
      domains.sprints.updateSprint(id, patch);

  Future<Sprint> startSprint(String id, {String? goal, DateTime? endDate}) =>
      domains.sprints.startSprint(id, goal: goal, endDate: endDate);

  Future<void> completeSprint(String id, {required String moveOpenTo}) =>
      domains.sprints.completeSprint(id, moveOpenTo: moveOpenTo);

  Future<SprintReport> sprintReport(String id) =>
      domains.sprints.sprintReport(id);

  // --- Time tracking --------------------------------------------------------

  Future<List<WorkItem>> workItems(String issueId) =>
      domains.issues.workItems(issueId);

  Future<WorkItem> addWorkItem(
    String issueId, {
    required int minutes,
    String? activityType,
    String? description,
    DateTime? date,
  }) => domains.issues.addWorkItem(
    issueId,
    minutes: minutes,
    activityType: activityType,
    description: description,
    date: date,
  );

  Future<List<TimesheetRow>> timesheet(
    DateTime from,
    DateTime to, {
    String? userId,
    String? projectId,
  }) => domains.timesheet.timesheet(
    from,
    to,
    userId: userId,
    projectId: projectId,
  );

  // --- Gantt ----------------------------------------------------------------

  Future<List<GanttTask>> gantt(String projectId) =>
      domains.projects.gantt(projectId);

  // --- Global search --------------------------------------------------------

  Future<SearchApiResponse> search({String query = '', String? scope}) =>
      domains.search.search(query: query, scope: scope);

  // --- Knowledge base -------------------------------------------------------

  Future<List<Article>> articles({String? projectId, bool all = false}) =>
      domains.articles.articles(projectId: projectId, all: all);

  Future<Article> article(String id) => domains.articles.article(id);

  Future<Article> saveArticle({
    String? id,
    required String title,
    String? content,
    String? projectId,
    String? teamId,
    String? parentId,
    String? space,
    String? icon,
    List<String>? tags,
  }) => domains.articles.saveArticle(
    id: id,
    title: title,
    content: content,
    projectId: projectId,
    teamId: teamId,
    parentId: parentId,
    space: space,
    icon: icon,
    tags: tags,
  );

  Future<Article> moveArticle(
    String id, {
    required String title,
    String? parentId,
    String? space,
  }) => domains.articles.moveArticle(
    id,
    title: title,
    parentId: parentId,
    space: space,
  );

  Future<void> deleteArticle(String id) => domains.articles.deleteArticle(id);

  Future<List<Space>> spaces() => domains.articles.spaces();

  Future<Space> createSpace({
    required String name,
    String? icon,
    int? hue,
    String? description,
  }) => domains.articles.createSpace(
    name: name,
    icon: icon,
    hue: hue,
    description: description,
  );

  Future<void> deleteSpace(String id) => domains.articles.deleteSpace(id);

  // --- Dashboard, reports, notifications ------------------------------------

  Future<DashboardData> dashboard({DashboardPrefs? override}) =>
      domains.dashboard.dashboard(override: override);

  Future<DashboardPrefs> saveDashboardPrefs(DashboardPrefs prefs) =>
      domains.dashboard.saveDashboardPrefs(prefs);

  Future<Map<String, int>> report(String name, Map<String, dynamic> query) =>
      domains.dashboard.report(name, query);

  Future<List<TrendPoint>> createdVsResolved(
    String projectId, {
    int days = 30,
  }) => domains.dashboard.createdVsResolved(projectId, days: days);

  Future<List<AppNotification>> notifications({int page = 0}) =>
      domains.notifications.notifications(page: page);

  Future<({List<AppNotification> items, int total})> notificationsPage({
    int page = 0,
    int size = 25,
  }) => domains.notifications.notificationsPage(page: page, size: size);

  Future<int> unreadNotifications() =>
      domains.notifications.unreadNotifications();

  Future<void> markNotificationRead(String id) =>
      domains.notifications.markNotificationRead(id);

  Future<void> markNotificationsRead(Iterable<String> ids) =>
      domains.notifications.markNotificationsRead(ids);

  // --- Admin ----------------------------------------------------------------

  Future<Map<String, dynamic>> adminSettings() => domains.admin.adminSettings();

  Future<Map<String, dynamic>> updateAdminSettings(
    Map<String, dynamic> settings,
  ) => domains.admin.updateAdminSettings(settings);

  Future<AdminUserPage> adminUsersPage({
    String query = '',
    AdminRole? role,
    UserStatus? status,
    UserOrigin? origin,
    UserSortKey sort = UserSortKey.lastActive,
    bool desc = true,
    int page = 1,
    int perPage = 25,
  }) => domains.admin.adminUsersPage(
    query: query,
    role: role,
    status: status,
    origin: origin,
    sort: sort,
    desc: desc,
    page: page,
    perPage: perPage,
  );

  Future<int> adminInvite({
    required List<String> emails,
    required AdminRole role,
    String? message,
  }) => domains.admin.adminInvite(emails: emails, role: role, message: message);

  Future<void> adminResendInvites(List<String> ids) =>
      domains.admin.adminResendInvites(ids);

  Future<void> adminSetStatus(List<String> ids, UserStatus status) =>
      domains.admin.adminSetStatus(ids, status);

  Future<void> adminApproveUsers(List<String> ids) =>
      domains.admin.adminApproveUsers(ids);

  Future<AdminUser> adminUser(String id) => domains.admin.adminUser(id);

  Future<void> adminSetRole(List<String> ids, AdminRole role) =>
      domains.admin.adminSetRole(ids, role);

  Future<void> adminSendPasswordReset(List<String> ids) =>
      domains.admin.adminSendPasswordReset(ids);

  Future<void> adminRevokeSessions(List<String> ids) =>
      domains.admin.adminRevokeSessions(ids);

  Future<void> adminUpdateUserDetails(
    String id, {
    String? displayName,
    String? title,
    String? email,
  }) => domains.admin.adminUpdateUserDetails(
    id,
    displayName: displayName,
    title: title,
    email: email,
  );

  Future<void> adminDeleteUsers(List<String> ids) =>
      domains.admin.adminDeleteUsers(ids);

  Future<AuditPage> auditLog({
    String query = '',
    AuditCategory? category,
    AuditSeverity? severity,
    String? action,
    String? outcome,
    String? actorId,
    int page = 1,
    int perPage = 30,
  }) => domains.admin.auditLog(
    query: query,
    category: category,
    severity: severity,
    action: action,
    outcome: outcome,
    actorId: actorId,
    page: page,
    perPage: perPage,
  );

  Future<List<AuditEventType>> auditEventTypes() =>
      domains.admin.auditEventTypes();

  // --- Teams ----------------------------------------------------------------

  Future<List<Team>> teams() => domains.teams.teams();

  Future<Team> team(String id) => domains.teams.team(id);

  Future<Team> createTeam({
    required String name,
    required String key,
    String? description,
    required int colorHue,
    required String icon,
  }) => domains.teams.createTeam(
    name: name,
    key: key,
    description: description,
    colorHue: colorHue,
    icon: icon,
  );

  Future<Team> updateTeam(String id, Map<String, dynamic> patch) =>
      domains.teams.updateTeam(id, patch);

  Future<void> deleteTeam(String id) => domains.teams.deleteTeam(id);

  Future<Team> addTeamMembers(
    String teamId,
    List<String> userIds, {
    required TeamRole role,
    required ProjectAccess access,
  }) => domains.teams.addTeamMembers(teamId, userIds, role: role, access: access);

  Future<Team> updateTeamMembership(
    String teamId,
    String userId, {
    TeamRole? role,
    ProjectAccess? access,
  }) => domains.teams.updateTeamMembership(
    teamId,
    userId,
    role: role,
    access: access,
  );

  Future<Team> removeTeamMember(String teamId, String userId) =>
      domains.teams.removeTeamMember(teamId, userId);

  Future<Team> attachTeamProjects(String teamId, List<String> projectIds) =>
      domains.teams.attachTeamProjects(teamId, projectIds);

  Future<Project> createTeamProject(
    String teamId, {
    required String key,
    required String name,
    String? description,
    String? color,
    String? leadId,
  }) => domains.teams.createTeamProject(
    teamId,
    key: key,
    name: name,
    description: description,
    color: color,
    leadId: leadId,
  );

  Future<Team> detachTeamProject(String teamId, String projectId) =>
      domains.teams.detachTeamProject(teamId, projectId);

  Future<List<TeamActivity>> teamActivity(String teamId, {int page = 0}) =>
      domains.teams.teamActivity(teamId, page: page);

  Future<({List<TeamActivity> items, int total})> teamActivityPage(
    String teamId, {
    int page = 0,
    int size = 20,
  }) => domains.teams.teamActivityPage(teamId, page: page, size: size);

  // --- Cascading deletion ---------------------------------------------------

  Future<BoardDeletionImpact> boardDeletionImpact(String boardId) =>
      domains.boards.boardDeletionImpact(boardId);

  Future<ProjectDeletionImpact> projectDeletionImpact(String projectId) =>
      domains.projects.projectDeletionImpact(projectId);

  Future<TeamDeletionImpact> teamDeletionImpact(String teamId) =>
      domains.teams.teamDeletionImpact(teamId);

  Future<Stream<List<int>>> boardDeleteStream(
    String boardId, {
    CancelToken? cancelToken,
  }) => domains.boards.boardDeleteStream(boardId, cancelToken: cancelToken);

  Future<Stream<List<int>>> projectDeleteStream(
    String projectId, {
    IssueStrategy? strategy,
    String? migrateToProjectId,
    CancelToken? cancelToken,
  }) => domains.projects.projectDeleteStream(
    projectId,
    strategy: strategy,
    migrateToProjectId: migrateToProjectId,
    cancelToken: cancelToken,
  );

  Future<Stream<List<int>>> teamDeleteStream(
    String teamId, {
    CancelToken? cancelToken,
  }) => domains.teams.teamDeleteStream(teamId, cancelToken: cancelToken);

  // --- Git integration ------------------------------------------------------

  Future<GitOAuthStart> gitOAuthStart(String projectId, String provider) =>
      domains.git.gitOAuthStart(projectId, provider);

  Future<GitOAuthSessionStatus> gitOAuthSession(String state) =>
      domains.git.gitOAuthSession(state);

  Future<List<GitOwner>> gitOwners(
    String projectId,
    String provider, {
    String? state,
  }) => domains.git.gitOwners(projectId, provider, state: state);

  Future<List<GitRepo>> gitRepos(
    String projectId,
    String provider,
    String owner, {
    String? query,
    String? state,
  }) => domains.git.gitRepos(
    projectId,
    provider,
    owner,
    query: query,
    state: state,
  );

  Future<Project> gitConnect(
    String projectId, {
    required String provider,
    required String owner,
    required String repo,
    String? state,
  }) => domains.git.gitConnect(
    projectId,
    provider: provider,
    owner: owner,
    repo: repo,
    state: state,
  );

  Future<Project> gitConnectToken(
    String projectId, {
    required String repoUrl,
    required String token,
  }) => domains.git.gitConnectToken(projectId, repoUrl: repoUrl, token: token);

  Future<Project> gitDisconnect(String projectId, {String? repoId}) =>
      domains.git.gitDisconnect(projectId, repoId: repoId);

  Future<Project> gitResync(String projectId, {String? repoId}) =>
      domains.git.gitResync(projectId, repoId: repoId);

  Future<Project> gitSetAutomation(String projectId, GitAutomation automation) =>
      domains.git.gitSetAutomation(projectId, automation);

  Future<Project> gitSetBranchTemplate(String projectId, String template) =>
      domains.git.gitSetBranchTemplate(projectId, template);

  Future<DevInfo> gitDevInfo(String issueKey) =>
      domains.git.gitDevInfo(issueKey);

  Future<({DevInfo devInfo, Issue issue})> gitMergePr(
    String issueKey,
    int number,
  ) => domains.git.gitMergePr(issueKey, number);

  Future<({DevInfo devInfo, Issue issue})> gitReadyPr(
    String issueKey,
    int number,
  ) => domains.git.gitReadyPr(issueKey, number);
}
