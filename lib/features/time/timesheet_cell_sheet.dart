import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/models/time_policy_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/time_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/duration_input.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/hive_widgets.dart' show fmtDuration;
import '../sprint/modals/glass_modal.dart'
    show GlassModalFooter, GlassModalHeader, showGlassModal;

/// One cell of the timesheet, opened.
///
/// The grid answers "how long" for a person, a project and a day; this is the
/// "of what" behind it — the entries that add up to the number, and a field to
/// put another one there. Typing a duration into a cell is the whole point of a
/// timesheet, and it has to stay that fast: a field, a number, done.
///
/// Returns true when anything changed, so the caller knows to reload the week
/// rather than guessing from the sheet being dismissed.
Future<bool> showTimesheetCellSheet(
  BuildContext context, {
  required DateTime day,
  String? projectId,
  required String projectLabel,
}) async {
  // The rules travel with it, as they do for the entry sheet: this composer can
  // collect a duration and a description and nothing else, so a day it may not
  // write to has to say so instead of offering a field whose save is refused.
  final policy = context.read<TimePolicyCubit>();
  unawaited(policy.ensureLoaded());
  final changed = await showGlassModal<bool>(
    context,
    adaptive: true,
    width: 460,
    builder: (_) => RepositoryProvider<TimeRepository>.value(
      value: context.read<TimeRepository>(),
      child: BlocProvider<TimePolicyCubit>.value(
        value: policy,
        child: _CellForm(
          day: day,
          projectId: projectId,
          projectLabel: projectLabel,
        ),
      ),
    ),
  );
  return changed ?? false;
}

class _CellForm extends StatefulWidget {
  const _CellForm({
    required this.day,
    required this.projectId,
    required this.projectLabel,
  });

  final DateTime day;
  final String? projectId;
  final String projectLabel;

  @override
  State<_CellForm> createState() => _CellFormState();
}

class _CellFormState extends State<_CellForm> {
  final _duration = TextEditingController();
  final _description = TextEditingController();

  List<WorkItem> _entries = const [];
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _duration.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page = await context.read<TimeRepository>().entries(
        filter: TimeEntryFilter(
          from: widget.day,
          to: widget.day,
          projectId: widget.projectId,
        ),
        size: 50,
      );
      if (!mounted) return;
      setState(() {
        // The filter cannot say "no project at all" — an absent `projectId`
        // means "any" on the wire — so the unfiled cell narrows what came back
        // instead. A day holds few enough entries for that to be free.
        _entries = widget.projectId == null
            ? page.items.where((entry) => entry.projectId == null).toList()
            : page.items;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final minutes = parseDurationInput(_duration.text);
    if (minutes == null) {
      setState(() => _error = 'time.error.duration');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<TimeRepository>().create(
        TimeEntryDraft(
          projectId: widget.projectId,
          durationMinutes: minutes,
          date: widget.day,
          description: _description.text.trim().isEmpty
              ? null
              : _description.text.trim(),
        ),
      );
      if (!mounted) return;
      _duration.clear();
      _description.clear();
      _changed = true;
      setState(() => _saving = false);
      await _load();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _remove(WorkItem entry) async {
    setState(() => _saving = true);
    try {
      await context.read<TimeRepository>().delete(entry.id);
      if (!mounted) return;
      _changed = true;
      setState(() => _saving = false);
      await _load();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  int get _total =>
      _entries.fold(0, (sum, entry) => sum + entry.durationMinutes);

  /// The first required field this two-line composer cannot collect, or null.
  ///
  /// A cell holds a duration and a description. An instance that requires a tag
  /// or an issue on every entry has made this shape of composing impossible, and
  /// saying so is better than a server refusal on a form with no field to fix.
  String? _unsupported(TimePolicySnapshot policy) {
    if (policy.requiredIssue) return 'time.policy.needIssue';
    if (policy.requiredTag) return 'time.policy.needTag';
    // A project is fine: the cell is a project column, so it always carries one
    // — except the unfiled column, which by definition does not.
    if (policy.requiredProject && widget.projectId == null) {
      return 'time.policy.needProject';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final policy = context.watch<TimePolicyCubit>().state;
    // Two ways this cell can be read-only, and they read differently. A frozen
    // day is closed to everyone and cannot be argued with; a required field this
    // sheet has no room for is a rule the entry editor can satisfy, so it says
    // which one and sends people there.
    final locked = policy.isLocked(widget.day);
    final missing = _unsupported(policy);
    final readOnly = locked || missing != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassModalHeader(
            icon: LucideIcons.tableProperties,
            title: widget.projectLabel,
            subtitle: localizations.formatFullDate(widget.day),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: HiveLoader(size: 32)),
                    )
                  else if (_entries.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        context.t('timesheet.cell.none'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.inkFaint,
                        ),
                      ),
                    )
                  else
                    for (final entry in _entries)
                      _EntryRow(
                        entry: entry,
                        onDelete: _saving || locked
                            ? null
                            : () => _remove(entry),
                      ),
                  if (_entries.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          context.t('timesheet.total'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSoft,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          fmtDuration(context, _total),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Divider(height: 1, color: AppColors.hairline),
                  const SizedBox(height: 16),
                  if (readOnly)
                    Row(
                      children: [
                        Icon(
                          locked ? LucideIcons.lock : LucideIcons.info,
                          size: 15,
                          color: AppColors.inkSoft,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.t(locked ? 'time.policy.locked' : missing!),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.inkSoft,
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    TextField(
                      controller: _duration,
                      autofocus: true,
                      onSubmitted: (_) => _saving ? null : _add(),
                      decoration: InputDecoration(
                        labelText: context.t('timesheet.cell.add'),
                        // Notation, not prose — the same literal the entry sheet
                        // shows, and nothing to translate. Showing it is what
                        // makes the field obviously more forgiving than a number
                        // box.
                        hintText: '1h 30m · 90m · 1:30',
                        prefixIcon: const Icon(LucideIcons.clock, size: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusControl,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _description,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: context.t('time.entry.description'),
                      counterText: '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusControl,
                        ),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.t(_error!),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          GlassModalFooter(
            confirmLabel: context.t('timesheet.cell.add'),
            confirmIcon: LucideIcons.plus,
            busy: _saving,
            onConfirm: _saving || readOnly ? null : _add,
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, this.onDelete});

  final WorkItem entry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final description = entry.description?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              description == null || description.isEmpty
                  ? context.t('time.entry.noDescription')
                  : description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: AppColors.ink),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            fmtDuration(context, entry.durationMinutes),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          IconButton(
            onPressed: onDelete,
            iconSize: 15,
            visualDensity: VisualDensity.compact,
            tooltip: context.t('common.delete'),
            icon: Icon(LucideIcons.trash2, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}
