import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/time_policy_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_share_models.dart';
import '../../../core/repositories/issue_repository.dart';
import '../../../core/repositories/project_repository.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/field_button.dart';
import '../../sprint/modals/glass_modal.dart';
import '../placement_picker.dart';
import '../tag_picker.dart';
import 'shared_entries_screen.dart' show SharedEntrySummary;
import 'time_shares_cubit.dart';

/// Takes an invitation with a change first (HIN-95): the copy filed on a
/// project or issue of the reader's choosing, with tags of their own.
///
/// Everything else is what was offered — day, hours, description — and stays
/// as offered: the copy is the reader's to edit once it is theirs, in the
/// ordinary sheet, under the ordinary rules. Resolves to true when the copy
/// was filed.
Future<bool?> showAcceptShareSheet(
  BuildContext context, {
  required TimeEntryShare share,
  required TimeSharesCubit shares,
}) {
  // The sheet rides the root navigator, outside the page's providers: the
  // pickers it opens read these.
  final providers = [
    RepositoryProvider<TimeRepository>.value(
      value: context.read<TimeRepository>(),
    ),
    RepositoryProvider<ProjectRepository>.value(
      value: context.read<ProjectRepository>(),
    ),
    RepositoryProvider<IssueRepository>.value(
      value: context.read<IssueRepository>(),
    ),
  ];
  final policy = context.read<TimePolicyCubit>();
  unawaited(policy.ensureLoaded());
  return showGlassModal<bool>(
    context,
    width: 480,
    builder: (_) => MultiRepositoryProvider(
      providers: providers,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<TimePolicyCubit>.value(value: policy),
          BlocProvider<TimeSharesCubit>.value(value: shares),
        ],
        child: _AcceptShareForm(share: share),
      ),
    ),
  );
}

class _AcceptShareForm extends StatefulWidget {
  const _AcceptShareForm({required this.share});

  final TimeEntryShare share;

  @override
  State<_AcceptShareForm> createState() => _AcceptShareFormState();
}

class _AcceptShareFormState extends State<_AcceptShareForm> {
  final _placementKey = GlobalKey();
  final _tagsKey = GlobalKey();

  late TimePlacement _placement = TimePlacement(
    projectId: widget.share.projectId,
    issueId: widget.share.issueId,
    label: _offeredLabel(widget.share),
  );
  late List<String> _tags = widget.share.tags;
  bool _placementTouched = false;
  bool _tagsTouched = false;
  bool _saving = false;
  String? _error;

  static String? _offeredLabel(TimeEntryShare share) => share.issueKey != null
      ? '${share.issueKey} ${share.issueTitle ?? ''}'.trim()
      : share.projectName;

  Future<void> _pickPlacement() async {
    final picked = await showTimePlacementPicker(
      context,
      anchorRect: anchorRectOf(_placementKey),
      current: _placement,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _placement = picked;
      _placementTouched = true;
    });
  }

  Future<void> _pickTags() async {
    final picked = await showTimeTagPicker(
      context,
      anchorRect: anchorRectOf(_tagsKey),
      selected: _tags,
      canCreate: !context.read<TimePolicyCubit>().state.limitTagAccess,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _tags = picked;
      _tagsTouched = true;
    });
  }

  Future<void> _accept() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<TimeSharesCubit>().accept(
        widget.share.id,
        acceptance: TimeShareAcceptance(
          projectId: _placementTouched ? _placement.projectId : null,
          // An empty id files the copy on the project alone.
          issueId: _placementTouched ? (_placement.issueId ?? '') : null,
          tags: _tagsTouched ? _tags : null,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.inbox,
        title: context.t('time.share.adjustTitle'),
        subtitle: context.t(
          'time.share.from',
          variables: {
            'name': widget.share.from.name ?? context.t('time.deletedUser'),
          },
        ),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SharedEntrySummary(share: widget.share),
              const SizedBox(height: 16),
              KeyedSubtree(
                key: _placementKey,
                child: FieldButton(
                  icon: LucideIcons.folder,
                  label: context.t('time.entry.placement'),
                  value:
                      _placement.label ??
                      (_placement.projectId == null
                          ? context.t('time.placement.none')
                          : context.t('time.placement.assigned')),
                  onTap: _saving ? () {} : () => unawaited(_pickPlacement()),
                ),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _tagsKey,
                child: FieldButton(
                  icon: LucideIcons.tag,
                  label: context.t('time.entry.tags'),
                  value: _tags.isEmpty
                      ? context.t('time.tags.none')
                      : _tags.join(', '),
                  onTap: _saving ? () {} : () => unawaited(_pickTags()),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    context.t(_error!),
                    style: const TextStyle(
                      fontSize: AppType.label,
                      height: 1.4,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('time.share.accept'),
        confirmIcon: LucideIcons.check,
        busy: _saving,
        onConfirm: _saving ? null : _accept,
      ),
    ],
  );
}
