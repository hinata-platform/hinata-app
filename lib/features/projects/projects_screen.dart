import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/fetch_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/entity_avatar.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../shell/page_chrome.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../../core/widgets/hive_widgets.dart';
import '../../core/widgets/soft_card.dart';
import '../../core/widgets/entity_avatar_editor.dart';
import '../sprint/modals/glass_modal.dart';
import 'project_copy_sheet.dart';
import 'project_create_form.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/repositories/user_repository.dart';

/// The phone's docked row, the same height every other page's is.
const double _kProjectsDockHeight = kGlassDockRow;

typedef _ProjectsData = ({
  List<Project> active,
  List<Project> archived,
  Map<String, String> names,
  Map<String, String> avatars,
});

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  late final FetchCubit<_ProjectsData> _cubit;

  /// Which of the three lists is on screen: the running projects, the
  /// templates, or the archive. Templates only exist while the module is on.
  _ProjectTab _tab = _ProjectTab.active;

  /// The search in the head: closed until asked for, and what is typed in it.
  /// Both, because the pill stays washed while a query is in force and the head
  /// may have closed the field on the way to a narrower window.
  final TextEditingController _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _cubit = FetchCubit<_ProjectsData>(() async {
      final results = await Future.wait([
        context.read<ProjectRepository>().projects(),
        context.read<ProjectRepository>().projects(archived: true),
        context.read<UserRepository>().users(),
      ]);
      final active = results[0] as List<Project>;
      final archived = results[1] as List<Project>;
      final users = results[2] as List<DirectoryUser>;
      final names = {for (final u in users) u.id: u.displayName};
      final avatars = {
        for (final u in users)
          if (u.avatarUrl != null && u.avatarUrl!.isNotEmpty)
            u.id: u.avatarUrl!,
      };
      return (
        active: active,
        archived: archived,
        names: names,
        avatars: avatars,
      );
    })..load();
  }

  @override
  void dispose() {
    _search.dispose();
    _cubit.close();
    super.dispose();
  }

  Widget _searchField(BuildContext context) => GlassSearchExpander(
    searching: _searching,
    hint: context.t('projects.searchHint'),
    controller: _search,
    onChanged: (value) => setState(() => _query = value),
    onOpen: () => setState(() => _searching = true),
    onClose: () => setState(() => _searching = false),
  );

  /// Name or key, folded and trimmed: somebody looking for "HIN" should not
  /// have to know whether the project spells its key in capitals.
  List<Project> _matching(List<Project> projects) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return projects;
    return projects
        .where(
          (p) =>
              p.name.toLowerCase().contains(query) ||
              p.key.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocBuilder<FetchCubit<_ProjectsData>, FetchState<_ProjectsData>>(
        builder: (context, state) {
          final all = state.data?.active ?? const <Project>[];
          final archived = state.data?.archived ?? const <Project>[];
          final names = state.data?.names ?? const <String, String>{};
          final avatars = state.data?.avatars ?? const <String, String>{};
          // The list route answers with both kinds unless asked otherwise, so
          // the split happens here rather than in a second request.
          final templatesOffered = context.select<AppConfigBloc, bool>(
            (bloc) => bloc.state.meta?.projectTemplates ?? false,
          );
          final templates = templatesOffered
              ? all.where((p) => p.template).toList(growable: false)
              : const <Project>[];
          final active = templatesOffered
              ? all.where((p) => !p.template).toList(growable: false)
              : all;
          // A tab that stopped existing — the flag went off while we were
          // looking at it — falls back to the running projects rather than to
          // an empty screen with no way out.
          final tab = _tab == _ProjectTab.templates && !templatesOffered
              ? _ProjectTab.active
              : _tab;
          final projects = _matching(switch (tab) {
            _ProjectTab.active => active,
            _ProjectTab.templates => templates,
            _ProjectTab.archived => archived,
          });
          final compact = context.isCompact;
          final switcher = _TabSwitcher(
            current: tab,
            templates: templatesOffered ? templates.length : null,
            archived: archived.length,
            onChanged: (value) => setState(() => _tab = value),
          );
          return PageChrome(
            title: context.t('projects.title'),
            // A phone's app bar has room for one trailing action, and this page
            // has exactly one: a new project. On a wide window it is a button in
            // the page's own head instead, where it can carry its name.
            actions: compact
                ? [
                    PageAction(
                      icon: LucideIcons.plus,
                      label: context.t('projects.new'),
                      primary: true,
                      onTap: (_) => _showCreate(),
                    ),
                  ]
                : const [],
            // The pills ride in the app bar's blur, the way the audit log, user
            // management and the time module all wear them. Down the page they
            // were a second title under the one the bar already shows.
            bottom: compact
                ? _dockedToolbar(
                    context,
                    _TabSwitcher(
                      current: tab,
                      templates: templatesOffered ? templates.length : null,
                      archived: archived.length,
                      onChanged: (value) => setState(() => _tab = value),
                      dock: true,
                    ),
                  )
                : null,
            bottomHeight: compact ? _kProjectsDockHeight : 0,
            child: RefreshIndicator(
              onRefresh: _cubit.load,
              color: AppColors.accent,
              edgeOffset: context.topGutter,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (!compact)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        context.pageGutter,
                        24 + context.topGutter,
                        context.pageGutter,
                        16,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: PageHead(
                          title: context.t('projects.title'),
                          subtitle: context.t(
                            'projects.summary',
                            variables: {
                              'active': '${active.length}',
                              'archived': '${archived.length}',
                            },
                          ),
                          actions: [
                            _searchField(context),
                            switcher,
                            PrimaryButton(
                              icon: LucideIcons.plus,
                              label: context.t('projects.new'),
                              onPressed: _showCreate,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (state.isLoading && projects.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: HiveLoader()),
                    )
                  else if (projects.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          context.pageGutter,
                          compact ? context.topGutter + 24 : 24,
                          context.pageGutter,
                          24,
                        ),
                        child: Center(
                          child: HiveEmptyState(
                            title: context.t('projects.title'),
                            // A list emptied by a search is not an empty list,
                            // and "create your first project" is the wrong thing
                            // to say to somebody who has forty and mistyped one.
                            message: _query.trim().isNotEmpty
                                ? context.t(
                                    'search.noMatch',
                                    variables: {'q': _query.trim()},
                                  )
                                : switch (tab) {
                                    _ProjectTab.archived => context.t(
                                      'projects.emptyArchived',
                                    ),
                                    _ProjectTab.templates => context.t(
                                      'projects.emptyTemplates',
                                    ),
                                    _ProjectTab.active => context.t(
                                      'projects.empty',
                                    ),
                                  },
                          ),
                        ),
                      ),
                    )
                  else
                    SliverLayoutBuilder(
                      builder: (context, room) => SliverPadding(
                        // On a phone the head is the app bar, and it floats
                        // over the list: without this clearance the first card
                        // starts underneath it, which reads as a list that
                        // opened halfway down and will not scroll back up. On a
                        // wide window the head sliver above has already spent it.
                        padding: EdgeInsets.fromLTRB(
                          context.pageGutter,
                          compact ? context.topGutter + context.pageGutter : 0,
                          context.pageGutter,
                          context.pageGutter + context.bottomGutter,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: context.gridColumns(
                                  minTileWidth: 300,
                                  width: room.crossAxisExtent,
                                ),
                                mainAxisSpacing: 18,
                                crossAxisSpacing: 18,
                                mainAxisExtent: 210,
                              ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _ProjectCard(
                              project: projects[index],
                              names: names,
                              avatars: avatars,
                              onSettings: () => _openSettings(projects[index]),
                              onCopy: templatesOffered
                                  ? () => _copy(projects[index])
                                  : null,
                              onInstantiate:
                                  templatesOffered && projects[index].template
                                  ? () => _instantiate(projects[index])
                                  : null,
                            ),
                            childCount: projects.length,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The phone's one docked row: the search pill and the three lists, inside
  /// the app bar's blur. The field takes the row over while somebody is typing
  /// in it and hands it back on close, exactly as it does in the audit log and
  /// in user management.
  Widget _dockedToolbar(BuildContext context, Widget switcher) => Padding(
    padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
    // The Align is load-bearing: the bar hands the reserved height down as a
    // tight constraint, and the row has to be able to come in under it.
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: GlassSearchDock(
        searching: _searching,
        controller: _search,
        hint: context.t('projects.searchHint'),
        onChanged: (value) => setState(() => _query = value),
        onClose: () => setState(() => _searching = false),
        controls: SizedBox(
          height: kGlassControlHeight,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // The gutter is spent above; inside the scroller it would clip the
            // last pill instead of letting it come into view.
            clipBehavior: Clip.none,
            child: Row(
              children: [
                GlassSearchButton(
                  tooltip: context.t('projects.searchHint'),
                  active: _query.isNotEmpty,
                  onTap: () => setState(() => _searching = true),
                ),
                const SizedBox(width: 8),
                switcher,
              ],
            ),
          ),
        ),
      ),
    ),
  );

  /// Keys of the projects this user can see — archived ones included, since
  /// they hold their key too. What the create dialog steps around when it
  /// suggests one.
  Set<String> _takenProjectKeys() {
    final data = _cubit.state.data;
    if (data == null) return const {};
    return {
      for (final p in [...data.active, ...data.archived]) p.key.toUpperCase(),
    };
  }

  Future<void> _showCreate() async {
    final projects = context.read<ProjectRepository>();
    final users = context.read<UserRepository>();
    final meId = context.read<AuthBloc>().state.user?.id;
    final created = await showGlassModal<Project>(
      context,
      width: 580,
      builder: (modalContext) => MultiRepositoryProvider(
        providers: [
          RepositoryProvider.value(value: projects),
          RepositoryProvider.value(value: users),
        ],
        child: _CreateProjectBody(meId: meId, takenKeys: _takenProjectKeys()),
      ),
    );
    if (created != null) _cubit.load();
  }

  Future<void> _openSettings(Project project) async {
    await context.push('/projects/${project.id}/settings');
    if (mounted) _cubit.load();
  }

  /// Where a tab sits in the control, which is one place to the left when
  /// templates are not offered.
  Future<void> _copy(Project project) =>
      _copyThrough(project, ProjectCopyMode.copy);

  Future<void> _instantiate(Project project) =>
      _copyThrough(project, ProjectCopyMode.instantiate);

  /// Opens the sheet, and on success lands in the new project's issues with a
  /// toast saying what came along.
  Future<void> _copyThrough(Project project, ProjectCopyMode mode) async {
    final result = await showProjectCopySheet(
      context,
      source: project,
      mode: mode,
    );
    if (result == null || !mounted) return;
    // No reload here: the line below leaves this screen, and it loads again on
    // the way back in.
    showGlassToast(
      context,
      context.t(
        'projects.copy.done',
        variables: {
          'issues': '${result.issuesCopied}',
          'deadlines': '${result.deadlinesSet}',
        },
      ),
    );
    if (mounted) context.go('/issues?projectId=${result.project.id}');
  }
}

/// The three lists the projects page holds.
enum _ProjectTab { active, templates, archived }

/// Which of the three lists is on screen, as the switcher every other page of
/// the app wears: a glass pill with one chip per list, docked in the page head
/// beside the title.
///
/// It was a [SegmentedControl] here — full width, under the head, three opaque
/// navy blocks — which is the one control on this page that looked like it came
/// from a different app. Moving it into the head also gives the list back the
/// line it was taking.
class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({
    required this.current,
    required this.templates,
    required this.archived,
    required this.onChanged,
    this.dock = false,
  });

  /// Whether this is the copy inside the app bar's docked row. There it is a
  /// docked control tall, beside a search pill of the same height; in a page
  /// head it is a search field tall, beside one of those.

  final _ProjectTab current;

  /// How many templates there are, or null while the module is off — then the
  /// chip is not offered at all.
  final int? templates;
  final int archived;
  final ValueChanged<_ProjectTab> onChanged;
  final bool dock;

  @override
  Widget build(BuildContext context) {
    // Narrow windows get the glyphs and keep the name as a tooltip: three words
    // plus two counts do not fit beside a title and the new-project button on a
    // phone, and a switcher that pushes the title off the head is worse than one
    // that asks to be recognised by its icon.
    final iconOnly = dock || !context.isExpanded;
    final tabs = <(_ProjectTab, IconData, String, int?)>[
      (_ProjectTab.active, LucideIcons.folderOpen, 'projects.active', null),
      if (templates != null)
        (
          _ProjectTab.templates,
          LucideIcons.copy,
          'projects.templates',
          templates,
        ),
      (
        _ProjectTab.archived,
        LucideIcons.archive,
        'projects.archived',
        archived,
      ),
    ];
    String label((_ProjectTab, IconData, String, int?) tab) {
      final name = context.t(tab.$3);
      final count = tab.$4;
      // A count of nothing is not worth the width: an empty archive says so by
      // being empty once you are in it.
      return count == null || count == 0 ? name : '$name · $count';
    }

    return GlassSwitchBar(
      compact: dock,
      maxWidth: iconOnly ? 45.0 * tabs.length + 30 : 150.0 * tabs.length,
      chips: [
        for (final tab in tabs) ...[
          if (tab != tabs.first) const SizedBox(width: 2),
          GlassSwitchChip(
            label: label(tab),
            icon: tab.$2,
            active: tab.$1 == current,
            iconOnly: iconOnly,
            // The list you are on is not a button: null stops it rippling,
            // taking focus, and telling a screen reader it leads somewhere.
            onTap: tab.$1 == current ? null : () => onChanged(tab.$1),
          ),
        ],
      ],
    );
  }
}

/// Parses a project's stored hex color (e.g. "#AEC6F4") to a Color, with a
/// stable hue fallback derived from the project key.
Color _projectColor(Project project) {
  final raw = project.color.replaceAll('#', '').trim();
  if (raw.length == 6) {
    final value = int.tryParse(raw, radix: 16);
    if (value != null) return Color(0xFF000000 | value);
  }
  return hiveHueColor(project.key);
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.names,
    required this.avatars,
    required this.onSettings,
    this.onCopy,
    this.onInstantiate,
  });

  final Project project;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final VoidCallback onSettings;

  /// Null while project templates are switched off: then there is no way to
  /// copy a project and the entry does not exist.
  final VoidCallback? onCopy;

  /// Only on a template, and the first thing offered there.
  final VoidCallback? onInstantiate;

  @override
  Widget build(BuildContext context) {
    // Mobile shows the compact gear in the corner; larger views show the
    // full-width "Settings" button in the footer instead.
    final compact = context.isCompact;
    // Only project leads (and platform admins) may open project settings —
    // regular members work on the project but never see its configuration.
    final me = context.read<AuthBloc>().state.user;
    final canManage =
        me != null && (me.isAdmin || project.leadIds.contains(me.id));
    final color = _projectColor(project);
    final glyphColor = project.archived
        ? HSLColor.fromColor(color).withSaturation(0.25).toColor()
        : color;
    final leadName = project.leadId != null ? names[project.leadId!] : null;
    final memberNames = project.memberIds
        .map((id) => names[id] ?? id)
        .toList(growable: false);
    final memberAvatars = project.memberIds
        .map((id) => avatars[id])
        .toList(growable: false);
    final subtitle = leadName != null
        ? '${project.key} · ${context.t('projects.lead')} ${leadName.split(' ').first}'
        : project.key;

    final card = SoftCard(
      onTap: () => context.go('/issues?projectId=${project.id}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The project's picture when it has one, the mono-key square
              // otherwise — same 44px footprint either way, so the card's
              // header row never shifts.
              EntityAvatar(
                avatarUrl: project.avatarUrl,
                size: 44,
                radius: 12,
                fallback: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.soft(glyphColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    project.key,
                    style: TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: glyphColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Leave room for the corner gear only when it's shown.
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: compact && canManage ? 26 : 0,
                      ),
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontMono,
                              fontSize: 11.5,
                              color: AppColors.inkFaint,
                            ),
                          ),
                        ),
                        if (project.template) ...[
                          const SizedBox(width: 6),
                          _TemplateBadge(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Stat(
                value: '${project.memberIds.length}',
                label: context.t('projects.membersLabel'),
              ),
              const SizedBox(width: 20),
              _Stat(
                value: '${project.workflowStates.length}',
                label: context.t('projects.statesLabel'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          HiveProgress(value: _completion(project), color: glyphColor),
          const Spacer(),
          const SizedBox(height: 12),
          Row(
            children: [
              if (memberNames.isNotEmpty)
                Expanded(
                  child: HiveAvatarStack(
                    names: memberNames,
                    imageUrls: memberAvatars,
                    size: 26,
                  ),
                )
              else
                const Spacer(),
              if (project.labels.isNotEmpty) ...[
                Icon(LucideIcons.tag, size: 14, color: AppColors.inkFaint),
                const SizedBox(width: 4),
                Text(
                  '${project.labels.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (onInstantiate != null)
                _CardAction(
                  icon: LucideIcons.sparkles,
                  label: context.t('projects.copy.fromTemplateShort'),
                  onTap: onInstantiate!,
                  primary: true,
                )
              else if (onCopy != null && !compact)
                _CardAction(
                  icon: LucideIcons.copy,
                  label: context.t('projects.copy.short'),
                  onTap: onCopy!,
                ),
              if ((onInstantiate != null || (onCopy != null && !compact)) &&
                  !compact &&
                  canManage)
                const SizedBox(width: 8),
              if (!compact && canManage) _SettingsButton(onTap: onSettings),
            ],
          ),
        ],
      ),
    );

    final stacked = Stack(
      children: [
        card,
        if (compact && canManage)
          Positioned(top: 10, right: 10, child: _GearButton(onTap: onSettings)),
      ],
    );

    return project.archived ? Opacity(opacity: 0.82, child: stacked) : stacked;
  }

  // Resolved-state ratio gives a rough completion proxy when no counts exist.
  double _completion(Project project) {
    if (project.workflowStates.isEmpty) return 0.0;
    return (project.resolvedStates.length / project.workflowStates.length)
        .clamp(0.0, 1.0);
  }
}

/// Small gear affordance in the card corner that opens project settings.
class _GearButton extends StatelessWidget {
  const _GearButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: AppColors.hairline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(LucideIcons.settings, size: 15, color: AppColors.inkSoft),
        ),
      ),
    );
  }
}

/// Footer "Settings" ghost button on each project card.
class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // `container: true` is what makes this a node of its own. A bare
      // Semantics only annotates, and the card's own tappable node merges the
      // annotation into itself — which is how the label went missing.
      container: true,
      button: true,
      label: context.t('projects.settings'),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.slidersHorizontal,
                  size: 14,
                  color: AppColors.inkSoft,
                ),
                const SizedBox(width: 6),
                Text(
                  context.t('projects.settings'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: AppTheme.fontBrand,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
      ],
    );
  }
}

/// "New project" creation modal, rendered on the app's Liquid Glass material
/// (same as the sprint/team modals) and matching the design: glyph + name/key,
/// description, lead, accent color and the default-workflow note.
class _CreateProjectBody extends StatefulWidget {
  const _CreateProjectBody({required this.meId, this.takenKeys = const {}});

  final String? meId;

  /// Keys already in use, so the suggested one doesn't walk into a conflict the
  /// server would only report after the form is submitted. Best effort — the
  /// server stays the authority (it answers 409 for a key this list missed).
  final Set<String> takenKeys;

  @override
  State<_CreateProjectBody> createState() => _CreateProjectBodyState();
}

class _CreateProjectBodyState extends State<_CreateProjectBody> {
  late final ProjectDraft _draft = ProjectDraft(
    takenKeys: widget.takenKeys,
    meId: widget.meId,
  );

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_refresh);
  }

  @override
  void dispose() {
    _draft.removeListener(_refresh);
    _draft.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.folderPlus,
          title: context.t('projects.new'),
          subtitle: context.t('projects.newSubtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProjectCreateFields(draft: _draft),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.create'),
          confirmIcon: LucideIcons.check,
          busy: _saving,
          onConfirm: _draft.valid ? _save : null,
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_draft.valid || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<ProjectRepository>();
      final project = await repo.createProject(
        key: _draft.trimmedKey,
        name: _draft.trimmedName,
        description: _draft.trimmedDescription,
        color: _draft.colorHex,
        leadId: _draft.lead?.id,
      );
      if (mounted) {
        await uploadPendingAvatar(
          context,
          _draft.pendingAvatar,
          EntityAvatarStrings.project,
          (file) => repo.uploadProjectAvatar(project.id, file),
        );
      }
      if (mounted) Navigator.of(context).pop(project);
    } on ApiFailure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}

/// The small "template" mark on a project card.
///
/// The Templates tab already says it for the cards under it — this is for the
/// moment the tab is not what somebody is looking at: a card in the middle of a
/// search, or the one they landed on from a link.
class _TemplateBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline2),
      ),
      child: Text(
        context.t('projects.templateBadge'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.inkSoft,
        ),
      ),
    );
  }
}

/// A ghost action in a project card's footer, beside the settings button.
class _CardAction extends StatelessWidget {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// The one action a card leads with — "create a project from this" on a
  /// template. Drawn filled so it reads as the thing to do.
  final bool primary;

  @override
  Widget build(BuildContext context) {
    // One node, named, and it answers. The card around it is tappable, so its
    // own semantics take every plain Text below with them — which left the two
    // buttons in the footer with a role and no name: "button" and "button", on
    // every card. Excluding what is underneath and stating the label and the
    // tap here is the arrangement that survives that merge.
    return Semantics(
      // `container: true` is what makes this a node of its own. A bare
      // Semantics only annotates, and the card's own tappable node merges the
      // annotation into itself — which is how the label went missing.
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: primary ? AppColors.navy : AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusControl),
              border: Border.all(
                color: primary ? AppColors.navy : AppColors.hairline,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 13,
                  color: primary ? Colors.white : AppColors.inkSoft,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: primary ? Colors.white : AppColors.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
