import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/account/account_screen.dart';
import '../../features/admin/admin_screen.dart';
import '../../features/absences/absence_entitlements_screen.dart';
import '../../features/absences/absence_year_run_screen.dart';
import '../../features/absences/absence_types_screen.dart';
import '../../features/organization/audit/org_audit_screen.dart';
import '../../features/organization/holidays/holidays_screen.dart';
import '../../features/auth/accept_invite_screen.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/auth/sso_callback_screen.dart';
import '../../features/auth/verify_email_screen.dart';
import '../../features/connect/connect_screen.dart';
import '../../features/connect/connecting_screen.dart';
import '../../features/connect/update_required_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/gantt/gantt_screen.dart';
import '../../features/issues/email_reply/email_reply_sheet.dart'
    show EmailReplyRouteArgs, EmailReplyScreen;
import '../../features/issues/issue_detail_screen.dart';
import '../../features/issues/issue_detail_sheet.dart' show IssueRouteArgs;
import '../../features/issues/issue_filter.dart' show IssuesInitialView;
import '../../features/issues/issues_screen.dart';
import '../../features/issues/watched_issues_screen.dart';
import '../../features/knowledge/knowledge_location.dart';
import '../../features/knowledge/knowledge_screen.dart';
import '../../features/moderation/app_terms_screen.dart';
import '../../features/moderation/house_rules_gate_screen.dart';
import '../../features/moderation/notice/notice_screen.dart';
import '../../features/moderation/queue/moderation_screen.dart';
import '../../features/moderation/suspensions/suspensions_screen.dart';
import '../../features/people/person_profile_screen.dart'
    show peopleRoute, personProfilePage;
import '../../features/notifications/notifications_screen.dart';
import '../../features/oauth/oauth_consent_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/organization/organization_screen.dart';
import '../../features/projects/projects_screen.dart';
import '../../features/projects/settings/project_settings_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/setup/setup_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/shell/not_found_screen.dart';
import '../../features/shell/shell_nav.dart' show sharedEntriesRoute;
import '../../features/teams/team_detail_screen.dart';
import '../../features/teams/teams_screen.dart';
import '../../features/time/time_focus_screen.dart';
import '../../features/time/shares/shared_entries_screen.dart';
import '../../features/billing/invoice_screen.dart';
import '../../features/billing/invoices_screen.dart';
import '../../features/billing/rates_screen.dart';
import '../../features/time/time_module_screen.dart';
import '../../features/time/time_views.dart';
import '../../features/timesheet/timesheet_screen.dart';
import '../../features/weekly_summary/weekly_summary_screen.dart';
import '../blocs/app_config_bloc.dart';
import '../blocs/auth_bloc.dart';
import '../models/core_models.dart' show AuthUser;
import '../models/time_share_models.dart' show TimeShareBox;
import '../storage/app_storage.dart';
import 'board_routes.dart';
import 'linked_target.dart';
import 'shift_routes.dart';

/// The root navigator, exposed so code that has no [BuildContext] can still
/// push a route — currently the desktop camera delegate, which image_picker
/// calls from a plain `Future` with no widget tree in reach.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Re-evaluates router redirects whenever one of the given streams emits.
class _MergedRefresh extends ChangeNotifier {
  _MergedRefresh(List<Stream<dynamic>> streams) {
    for (final stream in streams) {
      _subscriptions.add(stream.listen((_) => notifyListeners()));
    }
  }

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}

/// Where the router sends the user while the app is still booting, and the one
/// parking slot that carries a deep-linked destination across that boot.
///
/// A deep link (an e-mail link, a tapped push notification, an SSO callback)
/// almost always lands *before* the app is in any state to show it: the server
/// is still being verified, the session still being re-checked. The router
/// bounces such a request onto a gate screen — and unless the destination is
/// remembered here, it is simply gone, which from the outside looks exactly
/// like "I opened the link and the app did nothing".
///
/// Extracted from [buildRouter] with no widget tree attached, because the boot
/// orderings this has to survive are the whole point and a screen-less unit test
/// is the only way to walk through all of them.
@visibleForTesting
class BootGate {
  /// Screens the user is bounced through while the app boots (connects,
  /// onboards, authenticates) — never a deep-link destination in their own
  /// right, so they are never parked and never restored.
  static const gates = {
    '/connect',
    '/connecting',
    '/setup',
    '/onboarding',
    '/login',
    '/update',
    '/auth-callback',
    '/register',
    '/forgot-password',
    '/verify-email',
    '/terms',
    '/rules',
  };

  /// The destination waiting for the app to become able to show it.
  String? pendingDeepLink;

  /// A login screen that has something to tell, held through the boot.
  ///
  /// A refused SSO sign-in comes back to the web app as a full page load of
  /// `/login?ssoError=…` while the app is still connecting (HIN-179). The
  /// boot's own bounce to `/login` would drop the reason; this is where it
  /// waits, and it is handed out once.
  String? pendingLogin;

  /// The location to redirect to, or null to let [location] render.
  String? redirect({
    required String location,
    required String uri,
    required AppConfigStatus config,
    required AuthStatus auth,
    required bool hasServerUrl,
    required bool onboardingDone,
    bool appTermsAccepted = true,
    bool rulesPending = false,
  }) {
    // Remember a real (non-gate) destination that we're about to bounce off a
    // gate, so we can return to it once the app is ready + authenticated.
    void parkIfDeepLink() {
      if (!gates.contains(location) && location != '/dashboard') {
        pendingDeepLink = uri;
      }
    }

    if (location == '/login' &&
        Uri.parse(uri).queryParameters.containsKey('ssoError')) {
      pendingLogin = uri;
    }

    // The app's own terms come before connecting and before signing in, once
    // per device (HIN-175). Not while the session is still being checked: it
    // may well be signed in, and a session from before the terms counts as
    // having agreed (AppStorage). One that a link signed in on a fresh device
    // meets them right after (below).
    final termsDue = !appTermsAccepted && auth == AuthStatus.unauthenticated;

    /// [entry], or the terms first while they are due.
    String? toEntry(String entry) {
      final target = termsDue ? '/terms' : entry;
      if (location == target) return null;
      parkIfDeepLink();
      return target;
    }

    // The SSO callback carries a one-time token pair in its query string.
    // On a web login the whole app reloads at this URL, so AppConfig is still
    // (re)connecting — without this guard the config switch below would bounce
    // us to /connect and discard the tokens before SsoCallbackScreen reads
    // them. Hold the route until the tokens have signed the user in.
    if (location == '/auth-callback' && auth != AuthStatus.authenticated) {
      return null;
    }

    // The invite + password-reset deep links are self-contained public flows
    // (validate token → set password → auto-sign-in). Let them render
    // regardless of config/auth state; they set the server URL from the link
    // and navigate on themselves.
    if (location == '/invite' ||
        location == '/reset-password' ||
        location == '/verify-email') {
      return null;
    }

    switch (config) {
      case AppConfigStatus.initial:
      case AppConfigStatus.connecting:
        // No server chosen yet → URL-entry screen. Otherwise (boot with a
        // saved server, or a deliberate server switch) show a brief branded
        // splash rather than flashing the connect form.
        if (!hasServerUrl) return toEntry('/connect');
        if (location == '/connecting') return null;
        parkIfDeepLink();
        return '/connecting';
      case AppConfigStatus.needsServerUrl:
        return toEntry('/connect');
      case AppConfigStatus.updateRequired:
        if (location == '/update') return null;
        parkIfDeepLink();
        return '/update';
      case AppConfigStatus.needsSetup:
        if (location == '/setup') return null;
        parkIfDeepLink();
        return '/setup';
      case AppConfigStatus.ready:
        break;
    }
    if (!onboardingDone) {
      if (location == '/onboarding') return null;
      parkIfDeepLink();
      return '/onboarding';
    }
    if (auth != AuthStatus.authenticated) {
      // /auth-callback carries the SSO token pair and signs the user in;
      // /register + /forgot-password are the public logged-out auth flows.
      const allowed = {
        '/login',
        '/auth-callback',
        '/register',
        '/forgot-password',
      };
      if (termsDue) return toEntry('/login');
      if (allowed.contains(location)) {
        if (location == '/login' && uri == pendingLogin) pendingLogin = null;
        return null;
      }
      parkIfDeepLink();
      final login = pendingLogin ?? '/login';
      pendingLogin = null;
      return login;
    }
    // Signed in without the app's terms: an invitation, a reset, a verification
    // or a sign-in by SSO passed the gate signed out and signed the person in
    // on a fresh device. The terms first, then the house rules (HIN-175).
    if (!appTermsAccepted) {
      if (location == '/terms') return null;
      parkIfDeepLink();
      return '/terms';
    }
    // Signed in: the instance's house rules, whenever a version waits for this
    // person, before anything else and before the parked link (HIN-175).
    if (rulesPending) {
      if (location == '/rules') return null;
      parkIfDeepLink();
      return '/rules';
    }
    // Authenticated and ready: hand back the parked deep link, wherever the
    // user is standing right now. Deliberately not limited to the gates: the
    // gates are where a link gets parked, but they are not the only place the
    // app can be when it finally settles. A link that arrives a beat after the
    // app is already home parks nothing and needs nothing; one that arrives
    // while a *later* boot step is still running (a server switch dropping
    // AppConfig back to `connecting`, a re-`AuthChecked` after it) is parked
    // from a location that is by then no longer a gate — and used to sit there
    // forever, which is exactly what "the app opens and does nothing" looked
    // like.
    pendingLogin = null;
    final parked = pendingDeepLink;
    pendingDeepLink = null;
    if (parked != null && parked != uri) return parked;
    // Nothing parked: just keep the user off the gate screens.
    if (gates.contains(location)) return '/dashboard';
    return null;
  }
}

GoRouter buildRouter({
  required AppConfigBloc appConfig,
  required AuthBloc auth,
  required AppStorage storage,
}) {
  final bootGate = BootGate();

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: storage.screenshotRoute ?? '/dashboard',
    refreshListenable: _MergedRefresh([appConfig.stream, auth.stream]),
    redirect: (context, routerState) => bootGate.redirect(
      location: routerState.matchedLocation,
      uri: routerState.uri.toString(),
      config: appConfig.state.status,
      auth: auth.state.status,
      hasServerUrl: storage.serverUrl != null,
      onboardingDone: storage.onboardingDone,
      appTermsAccepted: storage.appTermsAccepted,
      rulesPending: auth.state.user?.rulesPending ?? false,
    ),
    // A path that matches nothing used to render an empty page under the brand
    // mark, which reads as a broken app rather than a bad link.
    errorBuilder: (_, _) => const NotFoundScreen(),
    routes: [
      GoRoute(path: '/connect', builder: (_, _) => const ConnectScreen()),
      GoRoute(path: '/connecting', builder: (_, _) => const ConnectingScreen()),
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(
        path: '/update',
        builder: (context, _) => UpdateRequiredScreen(
          appVersion: appConfig.state.appVersion,
          minVersion: appConfig.state.meta?.minAppVersion ?? '',
          storeUrl: storeUrlForPlatform(appConfig.state.meta),
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, _) => OnboardingScreen(
          storage: storage,
          onDone: () => GoRouter.of(context).go(
            auth.state.status == AuthStatus.authenticated
                ? '/dashboard'
                : '/login',
          ),
        ),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, _) => AppTermsScreen(
          storage: storage,
          // Wherever the boot goes next: connecting, signing in, the house
          // rules, or the link that waited.
          onDone: () => GoRouter.of(context).go('/dashboard'),
        ),
      ),
      GoRoute(path: '/rules', builder: (_, _) => const HouseRulesGateScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, state) => VerifyEmailScreen(
          token: state.uri.queryParameters['token'] ?? '',
          server: state.uri.queryParameters['server'],
        ),
      ),
      GoRoute(
        path: '/invite',
        builder: (_, state) => AcceptInviteScreen(
          token: state.uri.queryParameters['token'] ?? '',
          server: state.uri.queryParameters['server'],
        ),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'] ?? '',
          server: state.uri.queryParameters['server'],
        ),
      ),
      GoRoute(
        path: '/oauth-consent',
        builder: (_, state) => OAuthConsentScreen(
          requestId: state.uri.queryParameters['request_id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/auth-callback',
        builder: (_, state) => SsoCallbackScreen(
          // A single-use handoff code, redeemed for tokens via a POST — the
          // bearer tokens are never carried in the URL. `access_token`/
          // `refresh_token` are still read as a fallback for older redirects.
          code: state.uri.queryParameters['code'],
          accessToken: state.uri.queryParameters['access_token'],
          refreshToken: state.uri.queryParameters['refresh_token'],
          error: state.uri.queryParameters['error'],
        ),
      ),
      // The focus view. A top-level route on purpose, outside the ShellRoute:
      // it is full-screen on *every* width, and the shell's immersive mode is a
      // compact-only affordance. A rail down the left is exactly what somebody
      // asking for a focus mode is asking to be rid of.
      //
      // Listed before the shell's routes so that the intent reads in order;
      // nothing under the shell would catch it either way.
      GoRoute(
        path: '/time/focus',
        pageBuilder: (_, state) => _transition(
          state,
          timeFocusPage(
            advancedTime: appConfig.state.meta?.advancedTimeTracking ?? false,
          ),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, state) =>
                _transition(state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/projects',
            pageBuilder: (_, state) =>
                _transition(state, const ProjectsScreen()),
          ),
          GoRoute(
            path: '/projects/:id/settings',
            pageBuilder: (_, state) => _transition(
              state,
              ProjectSettingsScreen(projectId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/teams',
            pageBuilder: (_, state) => _transition(state, const TeamsScreen()),
          ),
          GoRoute(
            path: '/teams/:id',
            pageBuilder: (_, state) => _transition(
              state,
              TeamDetailScreen(teamId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/issues',
            pageBuilder: (_, state) {
              final projectId = state.uri.queryParameters['projectId'];
              final view = _issuesView(state.uri.queryParameters['view']);
              // Dashboard KPI deep-links carry the active project scope so the
              // Issues page shows exactly the set the card counted.
              final projectsCsv = state.uri.queryParameters['projects'] ?? '';
              // A person's profile links to that person's issues.
              final assignee = state.uri.queryParameters['assignee'];
              final scope = projectsCsv.isEmpty
                  ? const <String>[]
                  : projectsCsv.split(',').where((s) => s.isNotEmpty).toList();
              // Key by the preset + scope so switching KPI deep-links always
              // yields a fresh screen (clean filter) instead of reusing the prior
              // state — go_router's pageKey ignores the query on its own.
              return _transition(
                state,
                IssuesScreen(
                  key: ValueKey(
                    'issues-${view?.name ?? 'all'}-${projectId ?? ''}-${scope.join(',')}-${assignee ?? ''}',
                  ),
                  projectId: projectId,
                  initialView: view,
                  scopeProjectIds: scope,
                  assigneeId: assignee,
                ),
              );
            },
          ),
          // Jira-familiar alias: /browse/ASTA-42 → the canonical issue detail
          // route. Everything (deep links, App Links / Universal Links) targets
          // /issues/*, so we redirect here rather than duplicating the screen.
          GoRoute(
            path: '/browse/:key',
            redirect: (_, state) => '/issues/${state.pathParameters['key']!}',
          ),
          GoRoute(
            path: '/issues/:id',
            pageBuilder: (_, state) {
              final args = state.extra is IssueRouteArgs
                  ? state.extra as IssueRouteArgs
                  : null;
              final id = state.pathParameters['id']!;
              return _transition(
                state,
                IssueDetailScreen(
                  // Key by the issue id so navigating issue→issue (e.g. global
                  // search while a fullscreen issue is open) always yields a
                  // fresh screen instead of reusing the prior State —
                  // go_router's pageKey is per-pattern and ignores :id.
                  key: ValueKey('issue-$id'),
                  issueId: id,
                  fromModal: args?.fromModal ?? false,
                  onChanged: args?.onChanged,
                  // Deep link `…/issues/ID?comment=<id>` scrolls to that comment.
                  targetCommentId: state.uri.queryParameters['comment'],
                  // `…/issues/ID?attachment=<id>` opens that file in the viewer.
                  targetAttachmentId: state.uri.queryParameters['attachment'],
                  linkVisit: LinkVisit.of(state),
                ),
              );
            },
          ),
          // Maximized "Reply by email" composer — rendered inside the shell like
          // a maximized issue. Only reachable by promoting the reply sheet
          // (which carries the issue + draft via `extra`); a cold navigation
          // with no `extra` (e.g. a browser refresh) can't compose, so it
          // redirects to the issue itself.
          GoRoute(
            path: '/issues/:id/reply-email',
            redirect: (_, state) => state.extra is EmailReplyRouteArgs
                ? null
                : '/issues/${state.pathParameters['id']!}',
            pageBuilder: (_, state) {
              final args = state.extra as EmailReplyRouteArgs;
              return _transition(
                state,
                EmailReplyScreen(
                  key: ValueKey('reply-email-${state.pathParameters['id']}'),
                  issue: args.issue,
                  initialDraft: args.draft,
                  canMinimize: args.fromModal,
                ),
              );
            },
          ),
          ...boardRoutes(_transition),
          GoRoute(
            path: '/gantt',
            pageBuilder: (_, state) => _transition(state, const GanttScreen()),
          ),
          // The base timesheet. With the module on it is one of the module's
          // pages and lives under `/time/timesheet`, so this path forwards
          // there — deep links and the published app both still reach it, and
          // with the module off it stays exactly where it has always been.
          GoRoute(
            path: '/timesheet',
            // The query goes along: a search hit names the day to open on.
            redirect: (_, state) =>
                (appConfig.state.meta?.advancedTimeTracking ?? false)
                ? Uri(
                    path: '/time/timesheet',
                    queryParameters: state.uri.queryParameters.isEmpty
                        ? null
                        : state.uri.queryParameters,
                  ).toString()
                : null,
            pageBuilder: (_, state) => _transition(
              state,
              TimesheetScreen(date: linkDay(state.uri.queryParameters['date'])),
            ),
          ),
          // The extended time-tracking module. Its routes exist for the client
          // only while `advanced_time_tracking` is on — with the flag off the
          // server answers 404 on every one of them, and a deep link must land
          // on the same not-found page any unknown path would.
          //
          // The gate sits in the builder rather than in the route table because
          // go_router fixes that table at construction while the flag is a
          // runtime value an admin can flip mid-session. The router's
          // refreshListenable already carries AppConfig, so a flipped flag swaps
          // this page without a restart. Inside the shell, so the chrome (back
          // button, title, nav) stays right either way.
          GoRoute(
            path: '/time',
            pageBuilder: (_, state) => _timePage(
              timeModulePage(
                advancedTime:
                    appConfig.state.meta?.advancedTimeTracking ?? false,
              ),
            ),
          ),
          GoRoute(
            path: '/time/calendar',
            pageBuilder: (_, state) => _timePage(
              timeModulePage(
                advancedTime:
                    appConfig.state.meta?.advancedTimeTracking ?? false,
                view: TimeView.calendar,
                query: state.uri.queryParameters,
                visit: LinkVisit.of(state),
              ),
            ),
          ),
          GoRoute(
            path: '/time/timesheet',
            pageBuilder: (_, state) => _timePage(
              timeModulePage(
                advancedTime:
                    appConfig.state.meta?.advancedTimeTracking ?? false,
                view: TimeView.timesheet,
                query: state.uri.queryParameters,
                visit: LinkVisit.of(state),
              ),
            ),
          ),
          GoRoute(
            path: '/time/approvals',
            pageBuilder: (_, _) => _timePage(
              timeModulePage(
                advancedTime:
                    appConfig.state.meta?.advancedTimeTracking ?? false,
                view: TimeView.approvals,
              ),
            ),
          ),
          // Days away, beside the calendar they are planned in (HIN-117).
          // `scope` names the list it opens on — `requests`, or `inbox` for a
          // notification about somebody else's request.
          GoRoute(
            path: '/time/absences',
            pageBuilder: (_, state) => _timePage(
              timeModulePage(
                advancedTime:
                    appConfig.state.meta?.advancedTimeTracking ?? false,
                view: TimeView.absences,
                scope: state.uri.queryParameters['scope'],
                query: state.uri.queryParameters,
                visit: LinkVisit.of(state),
              ),
            ),
          ),
          // Reports (HIN-93). `shared` is the token of a colleague's link,
          // `saved` the id a report mail points at; either opens that report in
          // the reader's own scope.
          GoRoute(
            path: '/time/reports',
            pageBuilder: (_, state) => _timePage(
              timeModulePage(
                advancedTime:
                    appConfig.state.meta?.advancedTimeTracking ?? false,
                view: TimeView.reports,
                scope: switch (state.uri.queryParameters) {
                  {'shared': final token} => 'shared:$token',
                  {'saved': final id} => 'saved:$id',
                  {'tab': final tab} => 'tab:$tab',
                  _ => null,
                },
              ),
            ),
          ),
          // Shared entries (HIN-95): invitations to answer, and what the
          // reader offered. `box=sent` is where the note that somebody accepted
          // points.
          GoRoute(
            path: sharedEntriesRoute,
            pageBuilder: (_, state) => _transition(
              state,
              (appConfig.state.meta?.advancedTimeTracking ?? false)
                  ? SharedEntriesScreen(
                      // Keyed by the side, which is read once: a link to the
                      // sent list has to open it even with the inbox on screen.
                      key: ValueKey(
                        'shared-${state.uri.queryParameters['box']}',
                      ),
                      box: state.uri.queryParameters['box'] == 'sent'
                          ? TimeShareBox.sent
                          : TimeShareBox.inbox,
                    )
                  : const NotFoundScreen(standalone: false),
            ),
          ),
          // Billing (HIN-96): invoices, one invoice, and the rates. Only while
          // the server reports billing on; the pages themselves ask who may.
          GoRoute(
            path: invoicesRoute,
            pageBuilder: (_, state) => _transition(
              state,
              (appConfig.state.meta?.billing ?? false)
                  ? const InvoicesScreen()
                  : const NotFoundScreen(standalone: false),
            ),
          ),
          GoRoute(
            path: '$invoicesRoute/:id',
            pageBuilder: (_, state) => _transition(
              state,
              (appConfig.state.meta?.billing ?? false)
                  ? InvoiceScreen(
                      key: ValueKey('invoice-${state.pathParameters['id']}'),
                      id: state.pathParameters['id']!,
                    )
                  : const NotFoundScreen(standalone: false),
            ),
          ),
          GoRoute(
            path: ratesRoute,
            pageBuilder: (_, state) => _transition(
              state,
              (appConfig.state.meta?.billing ?? false)
                  // `?rate=<id>` opens that rate's timeline (search, HIN-165).
                  ? RatesScreen(
                      rateId: state.uri.queryParameters['rate'],
                      visit: LinkVisit.of(state),
                    )
                  : const NotFoundScreen(standalone: false),
            ),
          ),
          // Shift planning (HIN-27), gated on `shift_planning` like the time
          // module above.
          ...shiftRoutes(
            _transition,
            enabled: () => appConfig.state.meta?.shiftPlanning ?? false,
          ),
          // A person's profile (HIN-165): a panel over the page it was opened
          // from on a wide window, a page of its own otherwise.
          GoRoute(
            path: '$peopleRoute/:id',
            pageBuilder: (context, state) =>
                personProfilePage(context, state, fullPage: _transition),
          ),
          GoRoute(
            path: '/watched',
            pageBuilder: (_, state) =>
                _transition(state, const WatchedIssuesScreen()),
          ),
          GoRoute(
            path: '/reports',
            // With the extended module on there is one report page (HIN-157):
            // the module's, opened on its overview. Without it the overview
            // stands alone here.
            redirect: (_, _) =>
                (appConfig.state.meta?.advancedTimeTracking ?? false)
                ? '/time/reports?tab=overview'
                : null,
            pageBuilder: (_, state) =>
                _transition(state, const ReportsScreen()),
          ),
          // Every knowledge address builds the same page (one key), so moving
          // between them keeps the screen and its state; the address alone
          // says what it shows. Literal segments before `:id`.
          GoRoute(
            path: '/knowledge',
            pageBuilder: (_, state) =>
                _knowledgePage(state, const KnowledgeHomeLocation()),
          ),
          GoRoute(
            path: '/knowledge/new',
            pageBuilder: (_, state) => _knowledgePage(
              state,
              KnowledgeNewLocation(
                spaceId: state.uri.queryParameters['space'],
                parentId: state.uri.queryParameters['parent'],
              ),
            ),
          ),
          GoRoute(
            path: '/knowledge/spaces/:space',
            pageBuilder: (_, state) => _knowledgePage(
              state,
              KnowledgeSpaceLocation(state.pathParameters['space']!),
            ),
          ),
          GoRoute(
            path: '/knowledge/:id',
            pageBuilder: (_, state) => _knowledgePage(
              state,
              KnowledgeArticleLocation(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/knowledge/:id/edit',
            pageBuilder: (_, state) => _knowledgePage(
              state,
              KnowledgeEditLocation(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/knowledge/:id/history',
            pageBuilder: (_, state) => _knowledgePage(
              state,
              KnowledgeHistoryLocation(
                state.pathParameters['id']!,
                version: int.tryParse(state.uri.queryParameters['v'] ?? ''),
              ),
            ),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (_, state) =>
                _transition(state, const NotificationsScreen()),
          ),
          // The moderation's notice to the person concerned (HIN-173): the
          // bell and the mail lead here. Outside /moderation on purpose, which
          // is the moderators' own page with its own guard.
          GoRoute(
            path: '/notices/:caseId',
            pageBuilder: (_, state) => _transition(
              state,
              NoticeScreen(caseId: state.pathParameters['caseId']!),
            ),
          ),
          // Moderation (HIN-174): the moderators' page, a page of the
          // settings like Organisation. One route for list and case, so the
          // lists stay while cases are opened; a case's own address, which
          // the notifications use, lands on it. The server refuses everybody
          // else too; the guard keeps them from a page that could only say so.
          GoRoute(
            path: '/moderation',
            redirect: (_, _) => moderationGuard(auth.state.user),
            pageBuilder: (_, state) => _transition(
              state,
              ModerationScreen(
                view: caseViewOf(state.uri.queryParameters['view']),
                caseId: state.uri.queryParameters['case'],
              ),
            ),
          ),
          GoRoute(
            path: '/moderation/cases/:id',
            redirect: (_, state) =>
                moderationGuard(auth.state.user) ??
                moderationLocation(caseId: state.pathParameters['id']),
          ),
          GoRoute(
            path: suspensionsLocation,
            redirect: (_, _) => moderationGuard(auth.state.user),
            pageBuilder: (_, state) =>
                _transition(state, const SuspensionsScreen()),
          ),
          GoRoute(
            path: '/weekly-summary',
            pageBuilder: (_, state) =>
                _transition(state, const WeeklySummaryScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, state) => _transition(
              state,
              AccountScreen(section: state.uri.queryParameters['section']),
            ),
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (_, state) => _transition(
              state,
              AdminScreen(
                initialSection: state.uri.queryParameters['section'],
                focusUserId: state.uri.queryParameters['user'],
              ),
            ),
          ),
          // User management is a section of the admin area now, the way the
          // audit log is one. Old links and approval mails still land on it.
          GoRoute(
            path: '/admin/users',
            redirect: (_, state) => adminUsersRedirect(state.uri),
          ),
          // Where the holiday calendars lived before they became an
          // organisation duty (HIN-129). Old links still land on them.
          GoRoute(
            path: '/admin/holidays',
            redirect: (_, _) => '/organization/holidays',
          ),
          // Organisation (HIN-129): the organisation admin's page, apart from
          // the platform's admin area. The server refuses everybody else too;
          // the guard keeps them from a page that could only say so.
          GoRoute(
            path: '/organization',
            redirect: (_, _) => organizationGuard(auth.state.user),
            pageBuilder: (_, state) => _transition(
              state,
              OrganizationScreen(
                initialSection: state.uri.queryParameters['section'],
              ),
            ),
          ),
          // Holiday calendars (HIN-91), a page of its own under Organisation.
          GoRoute(
            path: '/organization/holidays',
            redirect: (_, _) => organizationGuard(auth.state.user),
            pageBuilder: (_, state) =>
                _transition(state, const OrgHolidaysScreen()),
          ),
          // The organisation's audit records, apart from the admin's log.
          GoRoute(
            path: '/organization/audit',
            redirect: (_, _) => organizationGuard(auth.state.user),
            pageBuilder: (_, state) =>
                _transition(state, const OrgAuditScreen()),
          ),
          // Absence management 2.0 (HIN-116). Outside `/admin` on purpose: an
          // operator names who keeps absences, and a named keeper need not be
          // an administrator. The server decides what each of them may do; the
          // pages themselves say so when it answers no.
          GoRoute(
            path: '/absences/types',
            pageBuilder: (_, state) =>
                _transition(state, const AbsenceTypesScreen()),
          ),
          GoRoute(
            path: '/absences/entitlements',
            pageBuilder: (_, state) =>
                _transition(state, const AbsenceEntitlementsScreen()),
          ),
          // The yearly run (HIN-119): what it did, who was not told, and the
          // lapses it proposes after a long illness. A keeper's page.
          GoRoute(
            path: '/absences/year-run',
            pageBuilder: (_, state) =>
                _transition(state, const AbsenceYearRunScreen()),
          ),
          // Where requests used to live before absences moved into the time
          // module. Notifications already sent link here, and the server still
          // writes these paths, so both land on the list they always meant.
          GoRoute(
            path: '/absences/requests',
            redirect: (_, _) => '/time/absences?scope=requests',
          ),
          GoRoute(
            path: '/absences/inbox',
            redirect: (_, _) => '/time/absences?scope=inbox',
          ),
        ],
      ),
    ],
  );
}

/// Where an old `/admin/users` link goes: the admin area with its user section
/// open, carrying the user whose drawer it should open. In-app links name that
/// user as `user`; the Connect relay (native email deep link) delivers it as
/// the relay `token`.
String adminUsersRedirect(Uri uri) {
  final user = uri.queryParameters['user'] ?? uri.queryParameters['token'];
  return Uri(
    path: '/admin',
    queryParameters: {
      'section': 'users',
      if (user != null && user.isNotEmpty) 'user': user,
    },
  ).toString();
}

/// Where somebody who does not moderate is sent from the moderation pages
/// (HIN-174), or null to let a moderator through.
@visibleForTesting
String? moderationGuard(AuthUser? user) =>
    (user?.isModerator ?? false) ? null : '/dashboard';

/// Where somebody without the organisation role is sent from the Organisation
/// pages, or null to let an organisation admin through.
///
/// The platform role does not open them: an administrator runs the platform,
/// and the organisation's time, absences and holidays are the organisation
/// admin's (HIN-129). Named so the rule can be tested without a router.
@visibleForTesting
String? organizationGuard(AuthUser? user) =>
    (user?.isOrgAdmin ?? false) ? null : '/dashboard';

/// The page behind `/time`, for a server whose extended time-tracking module is
/// ([advancedTime]) or is not switched on.
///
/// Named rather than inlined because the second branch is the whole point of the
/// route: a deep link into a module this server does not offer has to land on
/// the not-found page, and `standalone: false` is what keeps it inside the shell
/// — where the back button and the title come from.
@visibleForTesting
Widget timeModulePage({
  required bool advancedTime,
  TimeView view = TimeView.list,
  String? scope,
  Map<String, String> query = const {},
  LinkVisit? visit,
}) {
  if (!advancedTime) return const NotFoundScreen(standalone: false);
  return TimeModuleScreen(view: view, scope: scope, query: query, visit: visit);
}

/// The page behind `/time/focus`.
///
/// Named for the same reason [timeModulePage] is: the second branch is the
/// point of the route. Unlike the module's other pages this one is
/// `standalone` — there is no shell around it to draw a back button, so a deep
/// link into a module this server does not offer has to land on a page that
/// can bring you home by itself.
@visibleForTesting
Widget timeFocusPage({required bool advancedTime}) =>
    advancedTime ? const TimeFocusScreen() : const NotFoundScreen();

/// Maps the `/issues?view=…` query value to a preset filter (dashboard KPIs).
IssuesInitialView? _issuesView(String? value) => switch (value) {
  'today' => IssuesInitialView.today,
  'inprogress' => IssuesInitialView.inProgress,
  'backlog' => IssuesInitialView.backlog,
  'done' => IssuesInitialView.done,
  _ => null,
};

/// v2 page transition: a soft vertical "fade through" — content rises from
/// just below and fades in, with no overlap of the old and new pages.
///
/// Replaces the platform default (a horizontal Cupertino slide on macOS/desktop
/// where the new page flies in from the right and the old one slides out left,
/// briefly overlapping).
///
/// The earlier hand-rolled crossfade only faded the *incoming* page, so the
/// outgoing page sat fully opaque underneath and the two visibly overlapped
/// mid-transition. [SharedAxisTransition] (vertical) instead coordinates both
/// pages on a shared timeline: the outgoing page fades + drifts up and out
/// first, then the incoming page fades + rises in — they are never both visible
/// at once. `fillColor` is transparent so the canvas (not an opaque box) shows
/// through during the brief hand-off.
/// The five views of the time module, under **one** page key.
///
/// A page key is what tells the navigator whether an address change is a new
/// page or the same one saying something new. Given `state.pageKey`, every
/// view of the module was a page of its own: switching from the list to the
/// calendar tore the list down, played a transition and read the calendar back
/// from the server, which is exactly what the reader complained about. Under
/// one key the navigator keeps the page and hands [TimeModuleScreen] the view
/// the address names, and that screen keeps the branches it has already built.
///
/// The addresses do not change: each view keeps its route, its deep link and
/// its place in the back stack.
CustomTransitionPage<void> _timePage(Widget child) =>
    CustomTransitionPage<void>(
      key: const ValueKey('time-module'),
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          SharedAxisTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            transitionType: SharedAxisTransitionType.vertical,
            fillColor: Colors.transparent,
            child: child,
          ),
    );

/// A knowledge address. One key for all of them: the navigator keeps the one
/// screen and hands it the new location instead of stacking a page per step.
CustomTransitionPage<void> _knowledgePage(
  GoRouterState state,
  KnowledgeLocation location,
) => CustomTransitionPage<void>(
  key: const ValueKey('knowledge'),
  transitionDuration: const Duration(milliseconds: 280),
  reverseTransitionDuration: const Duration(milliseconds: 180),
  child: KnowledgeScreen(location: location),
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.vertical,
        fillColor: Colors.transparent,
        child: child,
      ),
);

CustomTransitionPage<void> _transition(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          SharedAxisTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            transitionType: SharedAxisTransitionType.vertical,
            fillColor: Colors.transparent,
            child: child,
          ),
    );
