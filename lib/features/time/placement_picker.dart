import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_loader.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;
import 'placement_picker_cubit.dart';
import '../../core/theme/app_type.dart';

/// Where an entry is filed: a project, an issue inside one, or nothing at all.
///
/// A single value rather than two fields, because the two constrain each other
/// — an issue always brings its own project, and the server refuses a pair that
/// disagrees. Making that impossible to express is cheaper than validating it.
@immutable
class TimePlacement {
  const TimePlacement({
    this.projectId,
    this.issueId,
    this.projectLabel,
    this.issueLabel,
  });

  /// Nothing chosen: the entry is the person's own, filed under no project.
  static const unfiled = TimePlacement();

  final String? projectId;
  final String? issueId;

  /// The project's name and the issue's "KEY · title", each on its own, for a
  /// form that shows the two as separate fields. Null when only the ids are
  /// known — a restored timer, an entry loaded from the list — and the caller
  /// then labels it from whatever it has.
  final String? projectLabel;
  final String? issueLabel;

  /// What to show for the placement as one value: the issue when there is one,
  /// else the project.
  String? get label => issueLabel ?? projectLabel;

  bool get isUnfiled => projectId == null && issueId == null;

  @override
  bool operator ==(Object other) =>
      other is TimePlacement &&
      other.projectId == projectId &&
      other.issueId == issueId;

  @override
  int get hashCode => Object.hash(projectId, issueId);
}

/// Shows a picker [body] the way every picker of an entry is shown: an
/// anchored glass popover on a wide window, a glass sheet on a phone.
///
/// The route rides the root navigator, so the body brings its own
/// [PlacementPickerCubit] from the repositories in [context].
Future<TimePlacement?> _showPicker(
  BuildContext context, {
  Rect? anchorRect,
  required Widget body,
}) {
  final scoped = BlocProvider(
    create: (context) => PlacementPickerCubit(
      context.read<ProjectRepository>(),
      context.read<IssueRepository>(),
    ),
    child: body,
  );
  final wide =
      anchorRect != null &&
      MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  return wide
      ? showGlassAnchoredPopover<TimePlacement>(
          context,
          anchorRect: anchorRect,
          width: 380,
          minHeight: 320,
          maxHeight: 460,
          builder: (_) => scoped,
        )
      : showGlassBottomSheet<TimePlacement>(
          context,
          // A cap, not a height: the body is a min-size Column, so a fixed box
          // leaves dead glass under a short list.
          builder: (_) => ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: scoped,
          ),
        );
}

/// Opens the placement picker: projects and issues in one list, for the timer
/// bar, the focus view, filters and shared entries.
///
/// Everything it lists comes from the server as the reader types — the project
/// search and the issue search, both paged. Nothing is pre-loaded: an instance
/// can hold hundreds of projects and tens of thousands of issues.
///
/// Resolves to the chosen placement, or null if dismissed. [TimePlacement.unfiled]
/// is a real answer, not a dismissal — clearing the field is something the
/// reader can mean.
Future<TimePlacement?> showTimePlacementPicker(
  BuildContext context, {
  Rect? anchorRect,
  required TimePlacement current,
  bool projectsOnly = false,
}) => _showPicker(
  context,
  anchorRect: anchorRect,
  body: _PlacementPickerBody(current: current, projectsOnly: projectsOnly),
);

/// Opens the project picker of an entry: the reader's projects, searched and
/// paged on the server, with "no project" first. Resolves to the project
/// picked — without an issue — or [TimePlacement.unfiled]; null if dismissed.
Future<TimePlacement?> showTimeProjectPicker(
  BuildContext context, {
  Rect? anchorRect,
  String? currentProjectId,
}) => _showPicker(
  context,
  anchorRect: anchorRect,
  body: _FieldPickerBody(
    field: _PickedField.project,
    currentId: currentProjectId,
  ),
);

/// Opens the issue picker of an entry: issues searched and paged on the
/// server, inside [projectId] when the entry has one, with "no issue" first.
/// Resolves to the issue picked together with its project, or to
/// `TimePlacement(projectId: projectId)` when the issue is taken away; null if
/// dismissed.
Future<TimePlacement?> showTimeIssuePicker(
  BuildContext context, {
  Rect? anchorRect,
  String? projectId,
  String? projectLabel,
  String? currentIssueId,
}) => _showPicker(
  context,
  anchorRect: anchorRect,
  body: _FieldPickerBody(
    field: _PickedField.issue,
    currentId: currentIssueId,
    projectId: projectId,
    projectLabel: projectLabel,
  ),
);

enum _PickedField { project, issue }

/// One field's picker: a search, a "none" row, and the server's results a page
/// at a time as the reader scrolls.
///
/// The pages live in a [PagedCubit] (de-duplicated by id); the widget holds the
/// query, the token that cancels a superseded request, and whether the last
/// page failed — after which scrolling stops asking until the reader taps
/// "load again".
class _FieldPickerBody extends StatefulWidget {
  const _FieldPickerBody({
    required this.field,
    this.currentId,
    this.projectId,
    this.projectLabel,
  });

  final _PickedField field;
  final String? currentId;

  /// The project an issue search stays inside, and its name for the result.
  final String? projectId;
  final String? projectLabel;

  @override
  State<_FieldPickerBody> createState() => _FieldPickerBodyState();
}

/// A row of the field picker: a project or an issue, reduced to what a row
/// shows and what picking it answers.
@immutable
class _Choice {
  const _Choice({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.placement,
  });

  final String id;
  final String title;
  final String subtitle;
  final TimePlacement placement;
}

class _FieldPickerBodyState extends State<_FieldPickerBody> {
  static const _pageSize = 20;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  String _query = '';
  CancelToken _cancel = CancelToken();

  /// The last page failed: scrolling no longer asks again on its own.
  bool _pageFailed = false;

  late final PagedCubit<_Choice> _pages = PagedCubit<_Choice>(
    _fetch,
    pageSize: _pageSize,
    keyOf: (choice) => choice.id,
  );

  bool get _isProject => widget.field == _PickedField.project;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_pages.load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cancel.cancel();
    _controller.dispose();
    _scroll.dispose();
    unawaited(_pages.close());
    super.dispose();
  }

  Future<PageResult<_Choice>> _fetch(int page, int size) async {
    final search = context.read<PlacementPickerCubit>();
    if (_isProject) {
      final found = await search.searchProjects(
        query: _query,
        size: size,
        page: page,
        cancelToken: _cancel,
      );
      return (
        items: [
          for (final project in found.projects)
            _Choice(
              id: project.id,
              title: project.name,
              subtitle: project.key,
              placement: TimePlacement(
                projectId: project.id,
                projectLabel: project.name,
              ),
            ),
        ],
        total: found.total,
      );
    }
    final found = await search.searchIssues(
      query: _query.isEmpty ? null : _query,
      size: size,
      page: page,
      projectId: widget.projectId,
      cancelToken: _cancel,
    );
    return (
      items: [
        for (final issue in found.issues)
          _Choice(
            id: issue.id,
            title: issue.title,
            subtitle: issue.readableId,
            placement: TimePlacement(
              projectId: issue.projectId,
              issueId: issue.id,
              issueLabel: '${issue.readableId} · ${issue.title}',
              // Known only when the search stayed inside it.
              projectLabel: issue.projectId == widget.projectId
                  ? widget.projectLabel
                  : null,
            ),
          ),
      ],
      total: found.total,
    );
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      // The request for the old query is of no use any more.
      _cancel.cancel();
      _cancel = CancelToken();
      _query = value.trim();
      setState(() => _pageFailed = false);
      unawaited(_pages.load());
    });
  }

  void _onScroll() {
    if (_pageFailed) return;
    if (_scroll.position.extentAfter < 120) unawaited(_loadMore());
  }

  Future<void> _loadMore() async {
    final loaded = await _pages.loadMore();
    if (!mounted || loaded != _pageFailed) return;
    setState(() => _pageFailed = !loaded);
  }

  void _pick(TimePlacement placement) => Navigator.of(context).pop(placement);

  @override
  Widget build(BuildContext context) {
    final searchKey = _isProject
        ? 'time.placement.searchProjects'
        : 'time.placement.searchIssues';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Semantics(
            label: context.t(searchKey),
            textField: true,
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: context.t(searchKey),
                prefixIcon: const Icon(LucideIcons.search, size: 16),
              ),
            ),
          ),
        ),
        if (!_isProject && widget.projectLabel != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
            child: Text(
              context.t(
                'time.placement.issuesIn',
                variables: {'project': widget.projectLabel!},
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppType.caption,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        Flexible(
          child: BlocBuilder<PagedCubit<_Choice>, PagedState<_Choice>>(
            bloc: _pages,
            builder: (context, state) {
              if (!state.hasData && state.errorKey == null) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: HiveLoader(size: 34),
                );
              }
              final choices = state.items;
              // The "none" row, the results, then one row that is the next
              // page loading, a way to ask for it again, or the empty answer.
              final tail = state.hasMore || choices.isEmpty ? 1 : 0;
              return ListView.builder(
                controller: _scroll,
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 10),
                itemCount: 1 + choices.length + tail,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _PlacementRow(
                      icon: LucideIcons.circleSlash,
                      title: context.t(
                        _isProject
                            ? 'time.placement.none'
                            : 'time.placement.noIssue',
                      ),
                      selected: widget.currentId == null,
                      onTap: () => _pick(
                        _isProject
                            ? TimePlacement.unfiled
                            : TimePlacement(
                                projectId: widget.projectId,
                                projectLabel: widget.projectLabel,
                              ),
                      ),
                    );
                  }
                  final at = index - 1;
                  if (at < choices.length) {
                    final choice = choices[at];
                    return _PlacementRow(
                      icon: _isProject
                          ? LucideIcons.folder
                          : LucideIcons.circleCheckBig,
                      title: choice.title,
                      subtitle: choice.subtitle,
                      selected: widget.currentId == choice.id,
                      onTap: () => _pick(choice.placement),
                    );
                  }
                  if (state.hasMore && _pageFailed) {
                    return Center(
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() => _pageFailed = false);
                          unawaited(_loadMore());
                        },
                        icon: const Icon(LucideIcons.rotateCw, size: 15),
                        label: Text(context.t('time.placement.loadAgain')),
                      ),
                    );
                  }
                  if (state.hasMore) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Center(child: HiveLoader(size: 22)),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 24,
                    ),
                    child: Text(
                      context.t(
                        state.errorKey != null
                            ? 'time.placement.searchFailed'
                            : 'search.noMatch',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppType.label,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlacementPickerBody extends StatefulWidget {
  const _PlacementPickerBody({
    required this.current,
    this.projectsOnly = false,
  });

  final TimePlacement current;

  /// Offer projects and nothing else — for a filter, which has no issue to
  /// narrow by. Without it an issue row would quietly resolve to its project.
  final bool projectsOnly;

  @override
  State<_PlacementPickerBody> createState() => _PlacementPickerBodyState();
}

class _PlacementPickerBodyState extends State<_PlacementPickerBody> {
  final _controller = TextEditingController();
  Timer? _debounce;

  List<Project> _projects = const [];
  List<Issue> _issues = const [];
  bool _loading = true;

  /// Monotonic token: a slow search that resolves after a later one must not
  /// overwrite the results the reader is already looking at.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Long enough that a typed word is one request rather than five, short
    // enough that the list feels attached to the keyboard.
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_search(value)),
    );
  }

  Future<void> _search(String query) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final search = context.read<PlacementPickerCubit>();
    try {
      // Both searches at once: they are independent, and running them in
      // sequence would double the wait for every keystroke.
      final found = await search.searchProjects(
        query: query,
        size: widget.projectsOnly ? 20 : 8,
      );
      final matched = widget.projectsOnly
          ? const <Issue>[]
          : (await search.searchIssues(
              query: query.isEmpty ? null : query,
              size: 12,
            )).issues;
      if (!mounted || seq != _seq) return;
      setState(() {
        _projects = found.projects;
        _issues = matched;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      // An empty list and no spinner: the picker stays usable and the reader
      // can still clear the field, which is the one action that never needs
      // the server.
      setState(() {
        _projects = const [];
        _issues = const [];
        _loading = false;
      });
    }
  }

  void _pick(TimePlacement placement) => Navigator.of(context).pop(placement);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          // The hint goes when typing starts; the label stays for a screen
          // reader.
          child: Semantics(
            label: context.t(
              widget.projectsOnly
                  ? 'time.placement.searchProjects'
                  : 'time.placement.search',
            ),
            textField: true,
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: context.t(
                  widget.projectsOnly
                      ? 'time.placement.searchProjects'
                      : 'time.placement.search',
                ),
                prefixIcon: const Icon(LucideIcons.search, size: 16),
              ),
            ),
          ),
        ),
        Flexible(
          child: _loading && _projects.isEmpty && _issues.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: HiveLoader(size: 34),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  children: [
                    _PlacementRow(
                      icon: widget.projectsOnly
                          ? LucideIcons.layers
                          : LucideIcons.circleSlash,
                      title: context.t(
                        widget.projectsOnly
                            ? 'time.filter.allProjects'
                            : 'time.placement.none',
                      ),
                      selected: widget.current.isUnfiled,
                      onTap: () => _pick(TimePlacement.unfiled),
                    ),
                    if (_projects.isNotEmpty)
                      _SectionLabel(context.t('nav.projects')),
                    for (final project in _projects)
                      _PlacementRow(
                        icon: LucideIcons.folder,
                        title: project.name,
                        subtitle: project.key,
                        selected:
                            widget.current.projectId == project.id &&
                            widget.current.issueId == null,
                        onTap: () => _pick(
                          TimePlacement(
                            projectId: project.id,
                            projectLabel: project.name,
                          ),
                        ),
                      ),
                    if (_issues.isNotEmpty)
                      _SectionLabel(context.t('nav.issues')),
                    for (final issue in _issues)
                      _PlacementRow(
                        icon: LucideIcons.circleCheckBig,
                        title: issue.title,
                        subtitle: issue.readableId,
                        selected: widget.current.issueId == issue.id,
                        onTap: () => _pick(
                          TimePlacement(
                            projectId: issue.projectId,
                            issueId: issue.id,
                            issueLabel: '${issue.readableId} · ${issue.title}',
                          ),
                        ),
                      ),
                    if (!_loading && _projects.isEmpty && _issues.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 24,
                        ),
                        child: Text(
                          context.t('search.noMatch'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppType.label,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: AppType.caption,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.inkFaint,
      ),
    ),
  );
}

class _PlacementRow extends StatelessWidget {
  const _PlacementRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            color: selected ? AppColors.accentSoft : Colors.transparent,
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.accentInk : AppColors.inkSoft,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppType.label,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppType.caption,
                            color: AppColors.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(LucideIcons.check, size: 15, color: AppColors.accentInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
