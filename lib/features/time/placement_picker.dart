import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    this.label,
    this.projectLabel,
    this.issueLabel,
  });

  /// Nothing chosen: the entry is the person's own, filed under no project.
  static const unfiled = TimePlacement();

  final String? projectId;
  final String? issueId;

  /// What to show for it, resolved when it was picked. Null when only the ids
  /// are known — a restored timer, an entry loaded from the list — and the
  /// caller then labels it from whatever it has.
  final String? label;

  /// The project's name and the issue's "KEY · title", each on its own, for a
  /// form that shows the two as separate fields. Null when not known yet.
  final String? projectLabel;
  final String? issueLabel;

  bool get isUnfiled => projectId == null && issueId == null;

  @override
  bool operator ==(Object other) =>
      other is TimePlacement &&
      other.projectId == projectId &&
      other.issueId == issueId;

  @override
  int get hashCode => Object.hash(projectId, issueId);
}

/// Opens the placement picker: an anchored glass popover on a wide window, a
/// glass sheet on a phone.
///
/// Everything it lists comes from the server as the reader types — the project
/// search and the issue search, both paged. Nothing is pre-loaded: an instance
/// can hold hundreds of projects and tens of thousands of issues, and a picker
/// that drains them is a picker that stops working on exactly the instances
/// that need it most.
///
/// Resolves to the chosen placement, or null if dismissed. [TimePlacement.unfiled]
/// is a real answer, not a dismissal — clearing the field is something the
/// reader can mean.
Future<TimePlacement?> showTimePlacementPicker(
  BuildContext context, {
  Rect? anchorRect,
  required TimePlacement current,
  bool projectsOnly = false,
}) {
  // The route rides the root navigator, so the picker brings its own cubit.
  final body = BlocProvider(
    create: (context) => PlacementPickerCubit(
      context.read<ProjectRepository>(),
      context.read<IssueRepository>(),
    ),
    child: _PlacementPickerBody(current: current, projectsOnly: projectsOnly),
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
          builder: (_) => body,
        )
      : showGlassBottomSheet<TimePlacement>(
          context,
          // A cap, not a height -- same reason as the tag picker beside it in
          // the entry sheet: the body is a min-size Column, so a fixed box
          // leaves dead glass under the buttons on a short list.
          builder: (_) => ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: body,
          ),
        );
}

/// Opens the project picker of an entry: the reader's projects, searched and
/// paged on the server, with "no project" first. Resolves to the project
/// picked — without an issue — or [TimePlacement.unfiled]; null if dismissed.
Future<TimePlacement?> showTimeProjectPicker(
  BuildContext context, {
  Rect? anchorRect,
  String? currentProjectId,
}) => _showFieldPicker(
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
}) => _showFieldPicker(
  context,
  anchorRect: anchorRect,
  body: _FieldPickerBody(
    field: _PickedField.issue,
    currentId: currentIssueId,
    projectId: projectId,
    projectLabel: projectLabel,
  ),
);

Future<TimePlacement?> _showFieldPicker(
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
          builder: (_) => ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 460),
            child: scoped,
          ),
        );
}

enum _PickedField { project, issue }

/// One field's picker: a search, a "none" row, and the server's results a page
/// at a time as the reader scrolls.
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

class _FieldPickerBodyState extends State<_FieldPickerBody> {
  static const _pageSize = 20;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  List<Project> _projects = const [];
  List<Issue> _issues = const [];
  int _total = 0;
  int _page = 0;
  bool _loading = true;
  String _query = '';

  /// Monotonic token, as in the combined picker: a slow answer to an older
  /// query must not land on top of the newer one.
  int _seq = 0;

  bool get _isProject => widget.field == _PickedField.project;
  int get _count => _isProject ? _projects.length : _issues.length;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _query = value.trim();
      unawaited(_load(reset: true));
    });
  }

  void _onScroll() {
    if (_loading || _count >= _total) return;
    if (_scroll.position.extentAfter < 120) unawaited(_load(reset: false));
  }

  Future<void> _load({required bool reset}) async {
    final seq = ++_seq;
    final page = reset ? 0 : _page + 1;
    setState(() => _loading = true);
    final search = context.read<PlacementPickerCubit>();
    try {
      if (_isProject) {
        final found = await search.searchProjects(
          query: _query,
          size: _pageSize,
          page: page,
        );
        if (!mounted || seq != _seq) return;
        setState(() {
          _projects = reset
              ? found.projects
              : [..._projects, ...found.projects];
          _total = found.total;
        });
      } else {
        final found = await search.searchIssues(
          query: _query.isEmpty ? null : _query,
          size: _pageSize,
          page: page,
          projectId: widget.projectId,
        );
        if (!mounted || seq != _seq) return;
        setState(() {
          _issues = reset ? found.issues : [..._issues, ...found.issues];
          _total = found.total;
        });
      }
      if (!mounted || seq != _seq) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      // What was found stays; "none" never needs the server.
      setState(() {
        if (reset) {
          _projects = const [];
          _issues = const [];
          _total = 0;
        }
        _loading = false;
      });
    }
  }

  void _pick(TimePlacement placement) => Navigator.of(context).pop(placement);

  @override
  Widget build(BuildContext context) {
    final searchKey = _isProject
        ? 'time.placement.searchProjects'
        : 'time.placement.searchIssues';
    final noneRow = _PlacementRow(
      icon: LucideIcons.circleSlash,
      title: context.t(
        _isProject ? 'time.placement.none' : 'time.placement.noIssue',
      ),
      selected: widget.currentId == null,
      onTap: () => _pick(
        _isProject
            ? TimePlacement.unfiled
            : TimePlacement(
                projectId: widget.projectId,
                label: widget.projectLabel,
                projectLabel: widget.projectLabel,
              ),
      ),
    );
    final more = _count < _total;
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
          child: _loading && _count == 0
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: HiveLoader(size: 34),
                )
              : ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  // The "none" row, the results, then one row that is either
                  // the next page loading or the empty answer.
                  itemCount: 1 + _count + (more || _count == 0 ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == 0) return noneRow;
                    final at = index - 1;
                    if (at < _count) {
                      if (_isProject) {
                        final project = _projects[at];
                        return _PlacementRow(
                          icon: LucideIcons.folder,
                          title: project.name,
                          subtitle: project.key,
                          selected: widget.currentId == project.id,
                          onTap: () => _pick(
                            TimePlacement(
                              projectId: project.id,
                              label: project.name,
                              projectLabel: project.name,
                            ),
                          ),
                        );
                      }
                      final issue = _issues[at];
                      final label = '${issue.readableId} · ${issue.title}';
                      return _PlacementRow(
                        icon: LucideIcons.circleCheckBig,
                        title: issue.title,
                        subtitle: issue.readableId,
                        selected: widget.currentId == issue.id,
                        onTap: () => _pick(
                          TimePlacement(
                            projectId: issue.projectId,
                            issueId: issue.id,
                            label: label,
                            issueLabel: label,
                            // Known only when the search stayed inside it.
                            projectLabel: issue.projectId == widget.projectId
                                ? widget.projectLabel
                                : null,
                          ),
                        ),
                      );
                    }
                    if (more) {
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
                        context.t('search.noMatch'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: AppType.label,
                          color: AppColors.inkSoft,
                        ),
                      ),
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
                            label: project.name,
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
                            label: '${issue.readableId} · ${issue.title}',
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
