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
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: _MergedRefresh([appConfig.stream, auth.stream]),
    redirect: (context, routerState) {
      final config = appConfig.state.status;
      final authStatus = auth.state.status;
      final location = routerState.matchedLocation;

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
          return location == '/connect' ? null : '/connect';
        case AppConfigStatus.updateRequired:
          return location == '/update' ? null : '/update';
        case AppConfigStatus.needsSetup:
          return location == '/setup' ? null : '/setup';
        case AppConfigStatus.ready:
          break;
      }
      if (!storage.onboardingDone) {
        return location == '/onboarding' ? null : '/onboarding';
      }
      if (authStatus != AuthStatus.authenticated) {
        // /auth-callback carries the SSO token pair and signs the user in.
        const allowed = {'/login', '/auth-callback'};
        return allowed.contains(location) ? null : '/login';
      }
      // Authenticated and ready: keep users away from gate screens.
      const gates = {
        '/connect', '/setup', '/onboarding', '/login', '/update', '/auth-callback',
      };
      if (gates.contains(location)) return '/dashboard';
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
          GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
          GoRoute(path: '/projects', builder: (_, _) => const ProjectsScreen()),
          GoRoute(path: '/issues', builder: (_, state) {
            return IssuesScreen(projectId: state.uri.queryParameters['projectId']);
          }),
          GoRoute(
            path: '/issues/:id',
            builder: (_, state) =>
                IssueDetailScreen(issueId: state.pathParameters['id']!),
          ),
          GoRoute(path: '/board', builder: (_, _) => const BoardScreen()),
          GoRoute(
            path: '/boards/:id',
            builder: (_, state) =>
                KanbanBoardScreen(boardId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/projects/:id/boards',
            builder: (_, state) => ProjectBoardsScreen(
              projectId: state.pathParameters['id']!,
              projectName: (state.extra as String?) ?? '',
            ),
          ),
          GoRoute(path: '/gantt', builder: (_, _) => const GanttScreen()),
          GoRoute(path: '/timesheet', builder: (_, _) => const TimesheetScreen()),
          GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
          GoRoute(path: '/knowledge', builder: (_, _) => const KnowledgeScreen()),
          GoRoute(
            path: '/knowledge/:id',
            builder: (_, state) =>
                ArticleScreen(articleId: state.pathParameters['id']!),
          ),
          GoRoute(
              path: '/notifications',
              builder: (_, _) => const NotificationsScreen()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
          GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
          GoRoute(
            path: '/admin/users',
            builder: (_, _) => const AdminUsersScreen(),
          ),
        ],
      ),
    ],
  );
}
