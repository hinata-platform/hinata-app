import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/team_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart';
import '../shell/page_chrome.dart';
import 'team_tabs.dart';
import 'team_widgets.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/team_repository.dart';
import '../../core/repositories/user_repository.dart';

/// Bundles everything the detail tabs need in one fetch (team + directory +
/// projects + activity), so the panels render without further round-trips.
typedef TeamDetailData = ({
  Team team,
  Map<String, DirectoryUser> usersById,
  Map<String, Project> projectsById,
  List<TeamActivity> activity,
  int activityTotal,
});

class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});

  final String teamId;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  late final FetchCubit<TeamDetailData> _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<TeamDetailData>(() async {
      final results = await Future.wait([
        context.read<TeamRepository>().team(widget.teamId),
        context.read<UserRepository>().users(),
        context.read<ProjectRepository>().projects(),
        context.read<TeamRepository>().teamActivityPage(widget.teamId),
      ]);
      final team = results[0] as Team;
      final users = results[1] as List<DirectoryUser>;
      final projects = results[2] as List<Project>;
      final activity = results[3] as ({List<TeamActivity> items, int total});
      return (
        team: team,
        usersById: {for (final u in users) u.id: u},
        projectsById: {for (final p in projects) p.id: p},
        activity: activity.items,
        activityTotal: activity.total,
      );
    })..load();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  bool _canManage(Team team) {
    final user = context.read<AuthBloc>().state.user;
    if (user == null) return false;
    if (user.isAdmin) return true;
    return team.membershipOf(user.id)?.isAdmin ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child:
          BlocBuilder<FetchCubit<TeamDetailData>, FetchState<TeamDetailData>>(
            builder: (context, state) {
              final data = state.data;
              // The shell bar shows back + the generic section title; the team
              // name lives only in the in-page _Header (avoids a doubled header).
              return PageChrome(
                title: context.t('teams.title'),
                child: () {
                  if (data == null) {
                    if (state.errorKey != null) {
                      return Center(
                        child: Text(
                          context.t(state.errorKey!),
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      );
                    }
                    return const Center(child: HiveLoader());
                  }
                  return _TeamDetailContent(
                    data: data,
                    manage: _canManage(data.team),
                    onReload: _cubit.load,
                  );
                }(),
              );
            },
          ),
    );
  }
}

class _TeamDetailContent extends StatefulWidget {
  const _TeamDetailContent({
    required this.data,
    required this.manage,
    required this.onReload,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;

  @override
  State<_TeamDetailContent> createState() => _TeamDetailContentState();
}

class _TeamDetailContentState extends State<_TeamDetailContent> {
  int _tab = 0;

  // Activity is paginated: the bundle provides page 0; older pages load on
  // demand and append here. Re-synced whenever a reload replaces the bundle.
  late List<TeamActivity> _activity = widget.data.activity;
  late int _activityTotal = widget.data.activityTotal;
  int _activityPage = 0;
  bool _loadingMoreActivity = false;

  @override
  void didUpdateWidget(_TeamDetailContent old) {
    super.didUpdateWidget(old);
    // A reload emits a fresh bundle (new maps/instances) — reset to its page 0.
    if (!identical(old.data, widget.data)) {
      _activity = widget.data.activity;
      _activityTotal = widget.data.activityTotal;
      _activityPage = 0;
    }
  }

  bool get _hasMoreActivity => _activity.length < _activityTotal;

  Future<void> _loadMoreActivity() async {
    if (_loadingMoreActivity || !_hasMoreActivity) return;
    setState(() => _loadingMoreActivity = true);
    try {
      final next = _activityPage + 1;
      final p = await context.read<TeamRepository>().teamActivityPage(
        widget.data.team.id,
        page: next,
      );
      if (!mounted) return;
      final existing = {for (final a in _activity) a.id};
      final older = [
        for (final a in p.items)
          if (!existing.contains(a.id)) a,
      ];
      setState(() {
        _activity = [..._activity, ...older];
        _activityTotal = p.total;
        _activityPage = next;
      });
    } catch (_) {
      // Keep what we have; the user can retry.
    } finally {
      if (mounted) setState(() => _loadingMoreActivity = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = widget.data.team;
    final tabs = [
      (
        icon: LucideIcons.gauge,
        label: context.t('teams.tabOverview'),
        count: null,
      ),
      (
        icon: LucideIcons.users,
        label: context.t('teams.tabMembers'),
        count: team.members.length,
      ),
      (
        icon: LucideIcons.folder,
        label: context.t('teams.tabProjects'),
        count: team.projectIds.length,
      ),
      (
        icon: LucideIcons.settings,
        label: context.t('teams.tabSettings'),
        count: null,
      ),
    ];

    return RefreshIndicator(
      onRefresh: widget.onReload,
      color: AppColors.accent,
      edgeOffset: context.topGutter,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          context.pageGutter,
          16 + context.topGutter,
          context.pageGutter,
          context.pageGutter + context.bottomGutter,
        ),
        children: [
          _Header(
            data: widget.data,
            manage: widget.manage,
            onReload: widget.onReload,
          ),
          const SizedBox(height: 20),
          _TabStrip(
            tabs: tabs,
            selected: _tab,
            onSelected: (i) => setState(() => _tab = i),
          ),
          const SizedBox(height: 22),
          switch (_tab) {
            0 => TeamOverviewTab(
              data: widget.data,
              manage: widget.manage,
              onReload: widget.onReload,
              onGotoProjects: () => setState(() => _tab = 2),
              activity: _activity,
              activityHasMore: _hasMoreActivity,
              activityLoadingMore: _loadingMoreActivity,
              onLoadMoreActivity: _loadMoreActivity,
            ),
            1 => TeamMembersTab(
              data: widget.data,
              manage: widget.manage,
              onReload: widget.onReload,
            ),
            2 => TeamProjectsTab(
              data: widget.data,
              manage: widget.manage,
              onReload: widget.onReload,
            ),
            _ => TeamSettingsTab(
              data: widget.data,
              manage: widget.manage,
              onReload: widget.onReload,
            ),
          },
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.data,
    required this.manage,
    required this.onReload,
  });

  final TeamDetailData data;
  final bool manage;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    final team = data.team;
    final createdBy = team.createdBy != null
        ? data.usersById[team.createdBy]
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final identity = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TeamGlyph(team: team, size: 56, radius: 16),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.fontBrand,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      _KeyChip(label: team.key),
                    ],
                  ),
                  if ((team.description ?? '').isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      team.description!,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ],
                  const SizedBox(height: 11),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      _meta(
                        LucideIcons.user,
                        context.t(
                          'teams.createdBy',
                          variables: {
                            'name':
                                createdBy?.displayName.split(' ').first ?? '—',
                          },
                        ),
                      ),
                      if (team.createdAt != null)
                        _meta(LucideIcons.calendar, _date(team.createdAt!)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

        final actions = manage
            ? [
                GhostButton(
                  label: context.t('teams.addMembers'),
                  icon: LucideIcons.userPlus,
                  onPressed: () => openAddMembers(context, data, onReload),
                ),
                PrimaryButton(
                  label: context.t('teams.addProject'),
                  icon: LucideIcons.folderPlus,
                  onPressed: () => openAddProject(context, data, onReload),
                ),
              ]
            : <Widget>[];

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: identity),
            if (actions.isNotEmpty) ...[
              const SizedBox(width: 16),
              ...[
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  actions[i],
                ],
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _meta(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 13, color: AppColors.inkFaint),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
    ],
  );

  static String _date(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _KeyChip extends StatelessWidget {
  const _KeyChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppTheme.fontMono,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.tabs,
    required this.selected,
    required this.onSelected,
  });

  final List<({IconData icon, String label, int? count})> tabs;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              _Tab(
                tab: tabs[i],
                selected: i == selected,
                onTap: () => onSelected(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.tab, required this.selected, required this.onTap});

  final ({IconData icon, String label, int? count}) tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.ink : AppColors.inkSoft;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tab.icon,
              size: 15,
              color: selected ? AppColors.accentStrong : AppColors.inkFaint,
            ),
            const SizedBox(width: 7),
            Text(
              tab.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            if (tab.count != null) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.canvas2,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '${tab.count}',
                  style: TextStyle(
                    fontFamily: AppTheme.fontMono,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
