import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/admin_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/board/board_screen.dart';
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
        return location == '/login' ? null : '/login';
      }
      // Authenticated and ready: keep users away from gate screens.
      const gates = {'/connect', '/setup', '/onboarding', '/login', '/update'};
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
        ],
      ),
    ],
  );
}
