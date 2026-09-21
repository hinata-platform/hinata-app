import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/repositories/team_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/person_picker.dart';
import '../../../core/widgets/project_picker.dart';
import '../../sprint/modals/glass_modal.dart';
import '../tag_picker.dart';

/// Names of the ids a report filters by, so a chip says "Apollo" rather than
/// an id. Kept by the page; the sheet adds what it learns.
typedef ReportLabels = Map<String, String>;

/// The filters of a report on one glass sheet (HIN-93): projects, people,
/// teams, tags, billable, activities, a search word, approval and rounding.
/// Resolves to the new question, or null when dismissed.
///
/// [people] offers people and teams only to a reader who may see somebody
/// else's entries: for everybody else they would narrow to themselves.
/// [approvals] offers the approval states only where periods are handed in.
Future<ReportQuery?> showReportFilterSheet(
  BuildContext context, {
  required ReportQuery query,
  required ReportLabels labels,
  required bool people,
  required bool approvals,
}) => showGlassModal<ReportQuery>(
  context,
  width: 580,
  builder: (_) => _FilterSheet(
    query: query,
    labels: labels,
    people: people,
    approvals: approvals,
  ),
);

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.query,
    required this.labels,
    required this.people,
    required this.approvals,
  });

  final ReportQuery query;
  final ReportLabels labels;
  final bool people;
  final bool approvals;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ReportQuery _query = widget.query;
  late final _text = TextEditingController(text: widget.query.text ?? '');
  final _activity = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    _activity.dispose();
    super.dispose();
  }

  String _label(String id) => widget.labels[id] ?? id;

  void _apply() {
    final text = _text.text.trim();
    Navigator.of(
      context,
    ).pop(_query.copyWith(text: text.isEmpty ? null : text));
  }

  Future<void> _addProjects(Rect? anchor) async {
    final picked = await showProjectPicker(
      context,
      anchorRect: anchor ?? Rect.zero,
      selected: _query.projectIds.toSet(),
      titleKey: 'time.reports.sheet.projects',
    );
    if (picked == null || !mounted) return;
    for (final project in picked) {
      widget.labels[project.id] = project.name;
    }
    setState(
      () => _query = _query.copyWith(
        projectIds: [for (final project in picked) project.id],
      ),
    );
  }

  Future<void> _addPerson(Rect? anchor) async {
    final picked = await showPersonPicker(
      context,
      anchorRect: anchor ?? Rect.zero,
    );
    if (picked == null || !mounted) return;
    widget.labels[picked.id] = picked.displayName;
    if (_query.userIds.contains(picked.id)) return;
    setState(
      () => _query = _query.copyWith(userIds: [..._query.userIds, picked.id]),
    );
  }

  Future<void> _addTeam(Rect? anchor) async {
    List<({String id, String name})> teams = const [];
    try {
      teams = [
        for (final team in await context.read<TeamRepository>().teams())
          (id: team.id, name: team.name),
      ];
    } on ApiFailure {
      return;
    }
    if (!mounted) return;
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('time.reports.sheet.teams'),
      anchorRect: anchor,
      options: [
        for (final team in teams)
          if (!_query.teamIds.contains(team.id))
            (value: team.id, child: Text(team.name)),
      ],
    );
    if (picked == null || !mounted) return;
    widget.labels[picked] = teams.firstWhere((team) => team.id == picked).name;
    setState(
      () => _query = _query.copyWith(teamIds: [..._query.teamIds, picked]),
    );
  }

  Future<void> _pickTags(Rect? anchor) async {
    final picked = await showTimeTagPicker(
      context,
      anchorRect: anchor,
      selected: _query.tags,
      canCreate: false,
    );
    if (picked == null || !mounted) return;
    setState(() => _query = _query.copyWith(tags: picked));
  }

  void _addActivity() {
    final value = _activity.text.trim();
    if (value.isEmpty || _query.activities.contains(value)) return;
    setState(() {
      _query = _query.copyWith(activities: [..._query.activities, value]);
      _activity.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.listFilter,
          title: context.t('time.reports.sheet.title'),
          subtitle: context.t('time.reports.sheet.peopleHint'),
          subtitleMaxLines: 3,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(22, 0, 22, 8 + bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Section(
                  label: context.t('time.reports.sheet.projects'),
                  child: _Tokens(
                    values: [
                      for (final id in _query.projectIds) (id, _label(id)),
                    ],
                    onRemove: (id) => setState(
                      () => _query = _query.copyWith(
                        projectIds: [..._query.projectIds]..remove(id),
                      ),
                    ),
                    onAdd: (anchor) => unawaited(_addProjects(anchor)),
                  ),
                ),
                if (widget.people) ...[
                  _Section(
                    label: context.t('time.reports.sheet.people'),
                    child: _Tokens(
                      values: [
                        for (final id in _query.userIds) (id, _label(id)),
                      ],
                      onRemove: (id) => setState(
                        () => _query = _query.copyWith(
                          userIds: [..._query.userIds]..remove(id),
                        ),
                      ),
                      onAdd: (anchor) => unawaited(_addPerson(anchor)),
                    ),
                  ),
                  _Section(
                    label: context.t('time.reports.sheet.teams'),
                    child: _Tokens(
                      values: [
                        for (final id in _query.teamIds) (id, _label(id)),
                      ],
                      onRemove: (id) => setState(
                        () => _query = _query.copyWith(
                          teamIds: [..._query.teamIds]..remove(id),
                        ),
                      ),
                      onAdd: (anchor) => unawaited(_addTeam(anchor)),
                    ),
                  ),
                ],
                _Section(
                  label: context.t('time.reports.sheet.tags'),
                  child: _Tokens(
                    values: [for (final tag in _query.tags) (tag, '#$tag')],
                    onRemove: (tag) => setState(
                      () => _query = _query.copyWith(
                        tags: [..._query.tags]..remove(tag),
                      ),
                    ),
                    onAdd: (anchor) => unawaited(_pickTags(anchor)),
                  ),
                ),
                _Section(
                  label: context.t('time.reports.sheet.billable'),
                  child: _Choices<bool?>(
                    values: [
                      (null, context.t('time.reports.sheet.billableAll')),
                      (true, context.t('time.reports.sheet.billableYes')),
                      (false, context.t('time.reports.sheet.billableNo')),
                    ],
                    selected: {_query.billable},
                    onTap: (value) => setState(
                      () => _query = _query.copyWith(billable: value),
                    ),
                  ),
                ),
                _Section(
                  label: context.t('time.reports.sheet.activities'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_query.activities.isNotEmpty) ...[
                        _Tokens(
                          values: [
                            for (final activity in _query.activities)
                              (activity, activity),
                          ],
                          onRemove: (activity) => setState(
                            () => _query = _query.copyWith(
                              activities: [..._query.activities]
                                ..remove(activity),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        controller: _activity,
                        maxLength: 60,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addActivity(),
                        decoration: glassInputDecoration(
                          hint: context.t('time.reports.sheet.activityHint'),
                        ).copyWith(counterText: ''),
                      ),
                    ],
                  ),
                ),
                _Section(
                  label: context.t('time.reports.sheet.text'),
                  child: TextField(
                    controller: _text,
                    maxLength: 100,
                    decoration: glassInputDecoration(
                      hint: context.t('time.reports.sheet.textHint'),
                    ).copyWith(counterText: ''),
                  ),
                ),
                if (widget.approvals)
                  _Section(
                    label: context.t('time.reports.sheet.approval'),
                    child: _Choices<ReportApproval>(
                      values: [
                        for (final state in ReportApproval.values)
                          (state, context.t(state.labelKey)),
                      ],
                      selected: _query.approval,
                      onTap: (state) => setState(() {
                        final next = {..._query.approval};
                        if (!next.remove(state)) next.add(state);
                        _query = _query.copyWith(approval: next);
                      }),
                    ),
                  ),
                _Section(
                  label: context.t('time.reports.sheet.rounding'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Choices<ReportRounding>(
                        values: [
                          for (final mode in ReportRounding.values)
                            (mode, context.t(mode.labelKey)),
                        ],
                        selected: {_query.rounding},
                        onTap: (mode) => setState(
                          () => _query = _query.copyWith(rounding: mode),
                        ),
                      ),
                      if (_query.rounding != ReportRounding.policy &&
                          _query.rounding != ReportRounding.none) ...[
                        const SizedBox(height: 10),
                        _Choices<int>(
                          values: [
                            for (final step in const [5, 6, 10, 15, 30, 60])
                              (
                                step,
                                context.t(
                                  'time.reports.sheet.minutes',
                                  variables: {'n': step},
                                ),
                              ),
                          ],
                          selected: {_query.roundingIncrement},
                          onTap: (step) => setState(
                            () => _query = _query.copyWith(
                              roundingIncrement: step,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('time.reports.sheet.done'),
          onConfirm: _apply,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GlassField(label: label, child: child),
    );
  }
}

/// Chosen values as removable tokens, and a button to add more.
class _Tokens extends StatelessWidget {
  const _Tokens({required this.values, required this.onRemove, this.onAdd});

  final List<(String, String)> values;
  final ValueChanged<String> onRemove;
  final ValueChanged<Rect?>? onAdd;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (id, label) in values)
          _Token(
            label: label,
            removeLabel: context.t(
              'time.reports.sheet.remove',
              variables: {'name': label},
            ),
            onRemove: () => onRemove(id),
          ),
        if (onAdd != null)
          Builder(
            builder: (anchor) => TextButton.icon(
              onPressed: () {
                final box = anchor.findRenderObject() as RenderBox?;
                onAdd!(
                  box == null || !box.hasSize
                      ? null
                      : box.localToGlobal(Offset.zero) & box.size,
                );
              },
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 44),
                foregroundColor: AppColors.accentInk,
              ),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(context.t('time.reports.sheet.add')),
            ),
          ),
      ],
    );
  }
}

class _Token extends StatelessWidget {
  const _Token({
    required this.label,
    required this.removeLabel,
    required this.onRemove,
  });

  final String label;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsetsDirectional.only(start: 12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.ink),
            ),
          ),
          IconButton(
            tooltip: removeLabel,
            onPressed: onRemove,
            icon: Icon(LucideIcons.x, size: 14, color: AppColors.inkSoft),
            style: IconButton.styleFrom(
              minimumSize: const Size(40, 40),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat choice chips — not glass: the sheet is the glass, and glass in glass
/// refracts itself.
class _Choices<T> extends StatelessWidget {
  const _Choices({
    required this.values,
    required this.selected,
    required this.onTap,
  });

  final List<(T, String)> values;
  final Set<T> selected;
  final ValueChanged<T> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in values)
          Semantics(
            button: true,
            selected: selected.contains(value),
            child: InkWell(
              onTap: () => onTap(value),
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected.contains(value)
                      ? AppColors.accentSoft
                      : Colors.transparent,
                  border: Border.all(
                    color: selected.contains(value)
                        ? AppColors.accentLine
                        : AppColors.hairline2,
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected.contains(value)
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
