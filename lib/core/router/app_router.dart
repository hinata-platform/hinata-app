import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_screen.dart';
import '../../features/admin/admin_users_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/sso_callback_screen.dart';
import '../../features/board/board_screen.dart';
import '../../features/board/project_boards_screen.dart';
import '../../features/connect/connect_screen.dart';
import '../../features/connect/update_required_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/gantt/gantt_screen.dart';
import '../../features/issues/issue_detail_screen.dart';
import '../../features/issues/issues_screen.dart';
import '../../features/knowledge/article_screen.dart';
import '../../features/knowledge/knowledge_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/projects/projects_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/setup/setup_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/timesheet/timesheet_screen.dart';
import '../blocs/app_config_bloc.dart';
import '../blocs/auth_bloc.dart';
import '../storage/app_storage.dart';

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

GoRouter buildRouter({
  required AppConfigBloc appConfig,
  required AuthBloc auth,
  required AppStorage storage,
}) {
  // Gate screens the user is bounced through while the app boots (connects,
  // onboards, authenticates). A deep-linked destination requested before the
  // app is ready gets parked here so it can be restored afterwards instead of
  // being lost to the default /dashboard.
  const gates = {
    '/connect', '/setup', '/onboarding', '/login', '/update', '/auth-callback',
  };
  String? pendingDeepLink;

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: _MergedRefresh([appConfig.stream, auth.stream]),
    redirect: (context, routerState) {
      final config = appConfig.state.status;
      final authStatus = auth.state.status;
      final location = routerState.matchedLocation;

      // Remember a real (non-gate) destination that we're about to bounce off a
      // gate, so we can return to it once the app is ready + authenticated.
      void parkIfDeepLink() {
        if (!gates.contains(location) && location != '/dashboard') {
          pendingDeepLink = routerState.uri.toString();
        }
      }

      // The SSO callback carries a one-time token pair in its query string.
      // On a web login the whole app reloads at this URL, so AppConfig is still
      // (re)connecting — without this guard the config switch below would bounce
      // us to /connect and discard the tokens before SsoCallbackScreen reads
      // them. Hold the route until the tokens have signed the user in.
      if (location == '/auth-callback' && authStatus != AuthStatus.authenticated) {
        return null;
      }

      switch (config) {
        case AppConfigStatus.initial:
        case AppConfigStatus.connecting:
        case AppConfigStatus.needsServerUrl:
          if (location == '/connect') return null;
          parkIfDeepLink();
          return '/connect';
        case AppConfigStatus.updateRequired:
          return location == '/update' ? null : '/update';
        case AppConfigStatus.needsSetup:
          return location == '/setup' ? null : '/setup';
        case AppConfigStatus.ready:
          break;
      }
      if (!storage.onboardingDone) {
        if (location == '/onboarding') return null;
        parkIfDeepLink();
        return '/onboarding';
      }
      if (authStatus != AuthStatus.authenticated) {
        // /auth-callback carries the SSO token pair and signs the user in.
        const allowed = {'/login', '/auth-callback'};
        if (allowed.contains(location)) return null;
        parkIfDeepLink();
        return '/login';
      }
      // Authenticated and ready: send the user to their parked deep link (if
      // any), otherwise keep them away from the gate screens.
      if (gates.contains(location)) {
        final target = pendingDeepLink;
        pendingDeepLink = null;
        return target ?? '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/connect', builder: (_, _) => const ConnectScreen()),
      GoRoute(path: '/setup', builder: (_, _) => const SetupScreen()),
      GoRoute(
        path: '/update',
        builder: (context, _) => UpdateRequiredScreen(
          appVersion: appConfig.state.appVersion,
          minVersion: appConfig.state.meta?.minAppVersion ?? '',
        ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, _) => OnboardingScreen(
          storage: storage,
          onDone: () => GoRouter.of(context).go(
            auth.state.status == AuthStatus.authenticated ? '/dashboard' : '/login',
          ),
        ),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/auth-callback',
        builder: (_, state) => SsoCallbackScreen(
          accessToken: state.uri.queryParameters['access_token'],
          refreshToken: state.uri.queryParameters['refresh_token'],
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, state) => _fadeUpPage(state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/projects',
            pageBuilder: (_, state) => _fadeUpPage(state, const ProjectsScreen()),
          ),
          GoRoute(
            path: '/issues',
            pageBuilder: (_, state) => _fadeUpPage(
              state,
              IssuesScreen(projectId: state.uri.queryParameters['projectId']),
            ),
          ),
          GoRoute(
            path: '/issues/:id',
            pageBuilder: (_, state) => _fadeUpPage(
              state,
              IssueDetailScreen(issueId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/board',
            pageBuilder: (_, state) => _fadeUpPage(state, const BoardScreen()),
          ),
          GoRoute(
            path: '/boards/:id',
            pageBuilder: (_, state) => _fadeUpPage(
              state,
              KanbanBoardScreen(boardId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/projects/:id/boards',
            pageBuilder: (_, state) => _fadeUpPage(
              state,
              ProjectBoardsScreen(
                projectId: state.pathParameters['id']!,
                projectName: (state.extra as String?) ?? '',
              ),
            ),
          ),
          GoRoute(
            path: '/gantt',
            pageBuilder: (_, state) => _fadeUpPage(state, const GanttScreen()),
          ),
          GoRoute(
            path: '/timesheet',
            pageBuilder: (_, state) => _fadeUpPage(state, const TimesheetScreen()),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (_, state) => _fadeUpPage(state, const ReportsScreen()),
          ),
          GoRoute(
            path: '/knowledge',
            pageBuilder: (_, state) => _fadeUpPage(state, const KnowledgeScreen()),
          ),
          GoRoute(
            path: '/knowledge/:id',
            pageBuilder: (_, state) => _fadeUpPage(
              state,
              ArticleScreen(articleId: state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/notifications',
            pageBuilder: (_, state) =>
                _fadeUpPage(state, const NotificationsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, state) => _fadeUpPage(state, const SettingsScreen()),
          ),
          GoRoute(
            path: '/admin',
            pageBuilder: (_, state) => _fadeUpPage(state, const AdminScreen()),
          ),
          GoRoute(
            path: '/admin/users',
            pageBuilder: (_, state) => _fadeUpPage(state, const AdminUsersScreen()),
          ),
        ],
      ),
    ],
  );
}

/// v2 page transition: a short, soft rise-up + fade for the incoming page.
///
/// Replaces the platform default (a horizontal Cupertino slide on macOS/desktop
/// where the new page flies in from the right and the old one slides out left,
/// briefly overlapping). Here the new page eases up a hair from below while
/// fading in; the outgoing page stays put underneath and is simply covered, so
/// there is no horizontal overlap. Quick (220ms in / 160ms out) and gentle.
CustomTransitionPage<void> _fadeUpPage(GoRouterState state, Widget child) =>
    CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final eased = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: eased,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.025),
              end: Offset.zero,
            ).animate(eased),
            child: child,
          ),
        );
      },
    );
