import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_avatar.dart';

class _Destination {
  const _Destination(this.route, this.labelKey, this.icon);

  final String route;
  final String labelKey;
  final IconData icon;
}

const _primary = [
  _Destination('/dashboard', 'nav.dashboard', Icons.dashboard_rounded),
  _Destination('/projects', 'nav.projects', Icons.folder_rounded),
  _Destination('/issues', 'nav.issues', Icons.task_alt_rounded),
  _Destination('/board', 'nav.board', Icons.view_kanban_rounded),
];

const _secondary = [
  _Destination('/gantt', 'nav.gantt', Icons.stacked_bar_chart_rounded),
  _Destination('/timesheet', 'nav.timesheet', Icons.table_chart_rounded),
  _Destination('/reports', 'nav.reports', Icons.insights_rounded),
  _Destination('/knowledge', 'nav.knowledge', Icons.menu_book_rounded),
];

/// Responsive scaffold: pill top navigation on wide screens (base design,
/// desktop) and a bottom navigation bar on compact screens (mobile design).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, size) => size == LayoutSize.compact
          ? _CompactShell(location: location, child: child)
          : _WideShell(location: location, child: child),
    );
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc bloc) => bloc.state.user);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  context.pageGutter, 16, context.pageGutter, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Hivora',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final destination in [..._primary, ..._secondary])
                              _NavPill(
                                destination: destination,
                                selected: location.startsWith(destination.route),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.t('nav.notifications'),
                      onPressed: () => context.go('/notifications'),
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    IconButton(
                      tooltip: context.t('nav.settings'),
                      onPressed: () => context.go('/settings'),
                      icon: const Icon(Icons.settings_rounded),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => context.go('/settings'),
                      borderRadius: BorderRadius.circular(100),
                      child: Row(
                        children: [
                          AppAvatar(
                            name: user?.displayName ?? '?',
                            imageUrl: user?.avatarUrl,
                            radius: 17,
                          ),
                          const SizedBox(width: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  user?.displayName ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  user?.email ?? '',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  const _NavPill({required this.destination, required this.selected});

  final _Destination destination;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: selected ? AppColors.navy : Colors.transparent,
        borderRadius: BorderRadius.circular(100),
        child: InkWell(
          onTap: () => context.go(destination.route),
          borderRadius: BorderRadius.circular(100),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              context.t(destination.labelKey),
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = [
    _Destination('/dashboard', 'nav.dashboard', Icons.dashboard_rounded),
    _Destination('/issues', 'nav.myTasks', Icons.task_alt_rounded),
    _Destination('/board', 'nav.board', Icons.view_kanban_rounded),
    _Destination('/more', 'nav.more', Icons.grid_view_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    var selected = _tabs.indexWhere((tab) => location.startsWith(tab.route));
    final isMore = selected == -1 && location != '/dashboard';
    if (selected == -1) selected = isMore ? 3 : 0;
    return Scaffold(
      body: SafeArea(bottom: false, child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) {
          final tab = _tabs[index];
          if (tab.route == '/more') {
            _showMoreSheet(context);
          } else {
            context.go(tab.route);
          }
        },
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(
              icon: Icon(tab.icon),
              label: context.t(tab.labelKey),
            ),
        ],
      ),
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            for (final destination in [
              const _Destination('/projects', 'nav.projects', Icons.folder_rounded),
              ..._secondary,
              const _Destination(
                  '/notifications', 'nav.notifications', Icons.notifications_rounded),
              const _Destination('/settings', 'nav.settings', Icons.settings_rounded),
            ])
              ListTile(
                leading: Icon(destination.icon, color: AppColors.navy),
                title: Text(sheetContext.t(destination.labelKey)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  context.go(destination.route);
                },
              ),
          ],
        ),
      ),
    );
  }
}
