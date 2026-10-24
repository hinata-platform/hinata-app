import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/util/dates.dart';
import '../../sprint/modals/glass_modal.dart';

/// The longest reason for uncovering a reporter or withheld content.
const revealReasonMax = 500;

/// Asks for the reason a step on a case needs (HIN-174): at least [min]
/// characters, kept in the case's history. Null when cancelled.
Future<String?> askCaseNote(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required String label,
  required String confirmLabel,
  int min = caseNoteMin,
  int max = caseNoteMax,
  bool destructive = false,
}) => showGlassModal<String>(
  context,
  width: 520,
  adaptive: !insideGlassSheet(context),
  builder: (_) => _NoteDialog(
    icon: icon,
    title: title,
    subtitle: subtitle,
    label: label,
    confirmLabel: confirmLabel,
    min: min,
    max: max,
    destructive: destructive,
  ),
);

/// Asks for a reason to uncover something covered, at most 500 characters.
Future<String?> askRevealReason(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String confirmLabel,
}) => askCaseNote(
  context,
  icon: LucideIcons.eye,
  title: title,
  subtitle: subtitle,
  label: context.t('moderation.case.revealReason'),
  confirmLabel: confirmLabel,
  min: 1,
  max: revealReasonMax,
);

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.label,
    required this.confirmLabel,
    required this.min,
    required this.max,
    required this.destructive,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String label;
  final String confirmLabel;
  final int min;
  final int max;
  final bool destructive;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlassModalHeader(
        icon: widget.icon,
        title: widget.title,
        subtitle: widget.subtitle,
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: GlassField(
            wrapCaption: true,
            label: widget.min > 1
                ? context.t(
                    'moderation.case.noteLabel',
                    variables: {'label': widget.label, 'min': '${widget.min}'},
                  )
                : widget.label,
            child: TextField(
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: widget.max,
              buildCounter: noteCounter,
              decoration: glassInputDecoration(),
            ),
          ),
        ),
      ),
      // Only the footer follows the typing.
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _text,
        builder: (context, value, _) => GlassModalFooter(
          confirmLabel: widget.confirmLabel,
          confirmColor: widget.destructive ? AppColors.danger : null,
          onConfirm: value.text.trim().length >= widget.min
              ? () => Navigator.of(context).pop(value.text.trim())
              : null,
        ),
      ),
    ],
  );
}

/// The counter under a field with a limit: 118 von 2000.
Widget noteCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => Text(
  context.t(
    'moderation.report.counter',
    variables: {'count': '$currentLength', 'max': '${maxLength ?? ''}'},
  ),
  style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
);

/// An appeal that came by a reply to the mail: its words and the day it came.
typedef RecordedAppeal = ({String text, DateTime receivedAt});

Future<RecordedAppeal?> askRecordedAppeal(BuildContext context) =>
    showGlassModal<RecordedAppeal>(
      context,
      width: 520,
      adaptive: !insideGlassSheet(context),
      builder: (_) => const _RecordAppealDialog(),
    );

class _RecordAppealDialog extends StatefulWidget {
  const _RecordAppealDialog();

  @override
  State<_RecordAppealDialog> createState() => _RecordAppealDialogState();
}

class _RecordAppealDialogState extends State<_RecordAppealDialog> {
  final _text = TextEditingController();
  DateTime _received = dateOnly(DateTime.now());

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = dateOnly(DateTime.now());
    final picked = await showGlassDatePicker(
      context,
      initialDate: _received,
      firstDate: addDays(today, -366),
      lastDate: today,
      title: context.t('moderation.appealReview.receivedOn'),
    );
    if (picked != null && mounted) setState(() => _received = picked);
  }

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    // The day it came, at the moment it is entered when that is today; the
    // server takes no moment after now.
    final receivedAt = _received == today ? DateTime.now() : _received;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.mailOpen,
          title: context.t('moderation.appealReview.recordTitle'),
          subtitle: context.t('moderation.appealReview.recordSubtitle'),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  wrapCaption: true,
                  label: context.t('moderation.appealReview.recordText'),
                  child: TextField(
                    controller: _text,
                    autofocus: true,
                    minLines: 4,
                    maxLines: 10,
                    maxLength: caseNoteMax,
                    buildCounter: noteCounter,
                    decoration: glassInputDecoration(),
                  ),
                ),
                const SizedBox(height: 8),
                GlassField(
                  label: context.t('moderation.appealReview.receivedOn'),
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_pickDay()),
                    icon: const Icon(LucideIcons.calendar, size: 16),
                    label: Text(recentDay(context, _received)),
                  ),
                ),
              ],
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _text,
          builder: (context, value, _) => GlassModalFooter(
            confirmLabel: context.t('moderation.appealReview.record'),
            onConfirm: value.text.trim().isEmpty
                ? null
                : () => Navigator.of(
                    context,
                  ).pop((text: value.text.trim(), receivedAt: receivedAt)),
          ),
        ),
      ],
    );
  }
}

/// Holding a decided case beyond its time: until a day, or without an end,
/// and always why.
typedef LegalHold = ({DateTime? until, bool indefinite, String reason});

Future<LegalHold?> askLegalHold(BuildContext context) =>
    showGlassModal<LegalHold>(
      context,
      width: 520,
      adaptive: !insideGlassSheet(context),
      builder: (_) => const _LegalHoldDialog(),
    );

class _LegalHoldDialog extends StatefulWidget {
  const _LegalHoldDialog();

  @override
  State<_LegalHoldDialog> createState() => _LegalHoldDialogState();
}

class _LegalHoldDialogState extends State<_LegalHoldDialog> {
  final _reason = TextEditingController();
  late DateTime _until = addDays(dateOnly(DateTime.now()), 365);
  bool _indefinite = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final tomorrow = addDays(dateOnly(DateTime.now()), 1);
    final picked = await showGlassDatePicker(
      context,
      initialDate: _until,
      firstDate: tomorrow,
      lastDate: addDays(tomorrow, 365 * 10),
      title: context.t('moderation.case.holdUntil'),
    );
    if (picked != null && mounted) setState(() => _until = picked);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      GlassModalHeader(
        icon: LucideIcons.archive,
        title: context.t('moderation.case.holdTitle'),
        subtitle: context.t('moderation.case.holdSubtitle'),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassOptionRow(
                title: context.t('moderation.case.holdIndefinite'),
                subtitle: context.t('moderation.case.holdIndefiniteHint'),
                value: _indefinite,
                onChanged: (value) => setState(() => _indefinite = value),
              ),
              if (!_indefinite)
                GlassField(
                  label: context.t('moderation.case.holdUntil'),
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_pickDay()),
                    icon: const Icon(LucideIcons.calendar, size: 16),
                    label: Text(recentDay(context, _until)),
                  ),
                ),
              const SizedBox(height: 8),
              GlassField(
                wrapCaption: true,
                label: context.t('moderation.case.holdReason'),
                child: TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: revealReasonMax,
                  buildCounter: noteCounter,
                  decoration: glassInputDecoration(),
                ),
              ),
            ],
          ),
        ),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: _reason,
        builder: (context, value, _) => GlassModalFooter(
          confirmLabel: context.t('moderation.case.hold'),
          onConfirm: value.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop((
                  until: _indefinite ? null : _until,
                  indefinite: _indefinite,
                  reason: value.text.trim(),
                )),
        ),
      ),
    ],
  );
}
