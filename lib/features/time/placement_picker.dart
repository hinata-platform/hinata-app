import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_loader.dart';
import '../sprint/modals/glass_modal.dart'
    show
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;

/// Where an entry is filed: a project, an issue inside one, or nothing at all.
///
/// A single value rather than two fields, because the two constrain each other
/// — an issue always brings its own project, and the server refuses a pair that
/// disagrees. Making that impossible to express is cheaper than validating it.
@immutable
class TimePlacement {
  const TimePlacement({this.projectId, this.issueId, this.label});

  /// Nothing chosen: the entry is the person's own, filed under no project.
  static const unfiled = TimePlacement();

  final String? projectId;
  final String? issueId;

  /// What to show for it, resolved when it was picked. Null when only the ids
  /// are known — a restored timer, an entry loaded from the list — and the
  /// caller then labels it from whatever it has.
  final String? label;

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
  final body = _PlacementPickerBody(
    current: current,
    projectsOnly: projectsOnly,
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
    final projects = context.read<ProjectRepository>();
    final issues = context.read<IssueRepository>();
    try {
      // Both searches at once: they are independent, and running them in
      // sequence would double the wait for every keystroke.
      final found = await projects.searchProjects(
        query: query,
        size: widget.projectsOnly ? 20 : 8,
      );
      final matched = widget.projectsOnly
          ? const <Issue>[]
          : (await issues.issues(
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
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
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
                            fontSize: 13,
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
        fontSize: 10.5,
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
    return Material(
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
                color: selected ? AppColors.accentStrong : AppColors.inkSoft,
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
                        fontSize: 13.5,
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
                          fontSize: 11.5,
                          color: AppColors.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                const Icon(
                  LucideIcons.check,
                  size: 15,
                  color: AppColors.accentStrong,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
