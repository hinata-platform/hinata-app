import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/app_config_bloc.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_usage_models.dart';
import '../../../core/repositories/time_usage_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/util/duration_input.dart';
import '../../../core/widgets/budget/budget.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        GlassModalFooter,
        GlassModalHeader,
        GlassToastKind,
        showGlassModal,
        showGlassToast;

/// A sprint's time budget in the sprint's head on the board (HIN-156): a
/// capsule when it has one, and for a lead of one of the board's projects the
/// way to set it. Nothing for anyone else without a budget, and nothing with
/// the extended module off.
class SprintBudget extends StatefulWidget {
  const SprintBudget({super.key, required this.sprintId});

  final String sprintId;

  @override
  State<SprintBudget> createState() => _SprintBudgetState();
}

class _SprintBudgetState extends State<SprintBudget> {
  SprintTimeUsage? _usage;
  String? _asked;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(SprintBudget old) {
    super.didUpdateWidget(old);
    if (old.sprintId != widget.sprintId) _load();
  }

  void _load({bool again = false}) {
    final id = widget.sprintId;
    if (id == _asked && !again) return;
    _asked = id;
    try {
      final on =
          context.read<AppConfigBloc>().state.meta?.advancedTimeTracking ??
          false;
      if (!on) return;
      unawaited(
        context.read<TimeUsageRepository>().sprint(id).then((usage) {
          if (mounted && _asked == id) setState(() => _usage = usage);
        }, onError: (Object _) {}),
      );
    } on ProviderNotFoundException {
      return;
    }
  }

  Future<void> _edit() async {
    final usage = _usage;
    if (usage == null) return;
    final saved = await showGlassModal<SprintTimeUsage>(
      context,
      width: 460,
      builder: (_) => _SprintBudgetForm(usage: usage),
    );
    if (saved != null && mounted) setState(() => _usage = saved);
  }

  @override
  Widget build(BuildContext context) {
    final usage = _usage;
    if (usage == null) return const SizedBox.shrink();
    final gauge = usage.gauge;
    if (gauge == null) {
      if (!usage.canEdit) return const SizedBox.shrink();
      return IconButton(
        tooltip: context.t('budget.sprint.set'),
        onPressed: _edit,
        icon: Icon(LucideIcons.timer, size: 18, color: AppColors.inkSoft),
      );
    }
    return BudgetCapsule(
      label: context.t('budget.sprint.label'),
      gauge: gauge,
      onTap: usage.canEdit ? _edit : null,
    );
  }
}

class _SprintBudgetForm extends StatefulWidget {
  const _SprintBudgetForm({required this.usage});

  final SprintTimeUsage usage;

  @override
  State<_SprintBudgetForm> createState() => _SprintBudgetFormState();
}

class _SprintBudgetFormState extends State<_SprintBudgetForm> {
  late final _field = TextEditingController(
    text: widget.usage.budgetMinutes == null
        ? ''
        : formatDurationInput(widget.usage.budgetMinutes!),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _field.text.trim();
    final minutes = text.isEmpty ? null : parseDurationInput(text);
    if (text.isNotEmpty && minutes == null) {
      setState(() => _error = 'time.error.duration');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await context.read<TimeUsageRepository>().setSprintBudget(
        widget.usage.sprintId,
        minutes,
      );
      if (!mounted) return;
      showGlassToast(context, context.t('common.saved'));
      Navigator.of(context).pop(saved);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
      showGlassToast(
        context,
        context.t(failure.message),
        kind: GlassToastKind.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.timer,
          title: context.t('budget.sprint.set'),
          subtitle: context.t('budget.sprint.hint'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _field,
                autofocus: true,
                onSubmitted: (_) => _saving ? null : _save(),
                decoration: InputDecoration(
                  labelText: context.t('budget.sprint.label'),
                  hintText: context.t('budget.sprint.hint'),
                  prefixIcon: const Icon(LucideIcons.timer, size: 16),
                ),
              ),
              if (widget.usage.gauge case final gauge?) ...[
                const SizedBox(height: 16),
                BudgetMeter(
                  label: context.t('budget.sprint.label'),
                  gauge: gauge,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  context.t(_error!),
                  style: TextStyle(
                    fontSize: AppType.label,
                    color: AppColors.dangerInk,
                  ),
                ),
              ],
            ],
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.save'),
          busy: _saving,
          onConfirm: _saving ? null : _save,
        ),
      ],
    );
  }
}
