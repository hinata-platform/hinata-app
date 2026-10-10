import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/core_models.dart' show DirectoryUser;
import '../../../core/models/time_share_models.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/time_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/field_button.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/person_picker.dart';
import '../../sprint/modals/glass_modal.dart';
import 'shared_entries_screen.dart' show ShareStatusLabel;
import 'time_shares_cubit.dart';

/// "Share with…" for one of the reader's own entries (HIN-95).
///
/// The people come from the entry's project, through the same searchable,
/// paged picker every other person field uses. Each of them gets an invitation
/// and decides for themselves whether a copy goes into their own entries; the
/// sheet lists who has been asked and where each stands, and takes back an
/// invitation nobody has answered yet. Resolves to true when invitations went
/// out.
Future<bool?> showShareEntrySheet(
  BuildContext context, {
  required WorkItem entry,
}) {
  final time = context.read<TimeRepository>();
  return showGlassModal<bool>(
    context,
    width: 480,
    builder: (_) => BlocProvider(
      create: (_) => TimeSharesCubit(time),
      child: _ShareEntryForm(entry: entry),
    ),
  );
}

class _ShareEntryForm extends StatefulWidget {
  const _ShareEntryForm({required this.entry});

  final WorkItem entry;

  @override
  State<_ShareEntryForm> createState() => _ShareEntryFormState();
}

class _ShareEntryFormState extends State<_ShareEntryForm> {
  final _pickerKey = GlobalKey();

  /// People picked in this sheet and not asked yet.
  final List<DirectoryUser> _picked = [];

  /// Who has been asked before, as the server last said.
  List<TimeEntryShare> _asked = const [];
  bool _loading = true;
  bool _sending = false;
  final Set<String> _revoking = {};
  String? _error;

  String get _projectId => widget.entry.projectId!;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final asked = await context.read<TimeSharesCubit>().entryShares(
        widget.entry.id,
      );
      if (!mounted) return;
      setState(() {
        _asked = asked;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _pick() async {
    final shares = context.read<TimeSharesCubit>();
    final picked = await showPersonPicker(
      context,
      anchorRect: anchorRectOf(_pickerKey) ?? Rect.zero,
      // Who has been asked and not taken back is not offered again: asking
      // twice changes nothing, and a refusal stays a refusal.
      search: (query, page, size) async {
        final asked = {
          for (final share in _asked)
            if (share.status != TimeShareStatus.revoked) share.to.id,
        };
        final found = await shares.candidates(
          _projectId,
          query: query,
          page: page,
          size: size,
        );
        final offered = [
          for (final person in found.items)
            if (!asked.contains(person.id)) person,
        ];
        return (
          items: offered,
          total: found.total - (found.items.length - offered.length),
        );
      },
    );
    if (picked == null || !mounted) return;
    if (_picked.any((person) => person.id == picked.id)) return;
    setState(() => _picked.add(picked));
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await context.read<TimeSharesCubit>().share(widget.entry.id, [
        for (final person in _picked) person.id,
      ]);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _revoke(TimeEntryShare share) async {
    setState(() => _revoking.add(share.id));
    try {
      final shares = context.read<TimeSharesCubit>();
      await shares.revoke(widget.entry.id, share.to.id);
      final asked = await shares.entryShares(widget.entry.id);
      if (mounted) setState(() => _asked = asked);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _revoking.remove(share.id));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.userPlus,
        title: context.t('time.share.title'),
        subtitle: context.t('time.share.subtitle'),
        subtitleMaxLines: 3,
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: _pickerKey,
                child: FieldButton(
                  icon: LucideIcons.userPlus,
                  label: context.t('time.share.people'),
                  value: context.t('time.share.addPerson'),
                  onTap: _sending ? () {} : () => unawaited(_pick()),
                ),
              ),
              if (_picked.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final person in _picked)
                      InputChip(
                        label: Text(
                          person.displayName.isEmpty
                              ? person.username
                              : person.displayName,
                        ),
                        deleteButtonTooltipMessage: context.t(
                          'time.share.removePerson',
                        ),
                        onDeleted: _sending
                            ? null
                            : () => setState(() => _picked.remove(person)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              _askedSection(context),
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
        confirmLabel: context.t('time.share.send'),
        confirmIcon: LucideIcons.send,
        busy: _sending,
        onConfirm: _sending || _picked.isEmpty ? null : _send,
      ),
    ],
  );

  Widget _askedSection(BuildContext context) {
    if (_loading) {
      return const Align(
        alignment: AlignmentDirectional.centerStart,
        child: HiveLoader(size: 22),
      );
    }
    if (_asked.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.t('time.share.asked'),
          style: TextStyle(
            fontSize: AppType.caption,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: AppColors.inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        for (final share in _asked)
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    share.to.name ?? context.t('time.deletedUser'),
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                ShareStatusLabel(status: share.status),
                if (share.isPending)
                  IconButton(
                    tooltip: context.t('time.share.revoke'),
                    icon: const Icon(LucideIcons.undo2, size: 18),
                    onPressed: _revoking.contains(share.id)
                        ? null
                        : () => unawaited(_revoke(share)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
