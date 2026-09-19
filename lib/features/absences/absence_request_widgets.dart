/// The parts a request is shown with, wherever it is shown: its card in a
/// list, its status, a line of warning, a step of its story, and the sheet that
/// asks for the sentence a decision carries.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_request_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/soft_card.dart';
import '../sprint/modals/glass_modal.dart';
import 'absence_labels.dart';

/// One request, from whichever side the reader is on.
///
/// The inbox leads with who asked; one's own list leads with what was asked
/// for. Everything else is the same row, because it is the same row.
class AbsenceRequestCard extends StatelessWidget {
  const AbsenceRequestCard({
    super.key,
    required this.request,
    required this.type,
    required this.inbox,
    required this.isMine,
    this.onApprove,
    this.onReject,
    this.onWithdraw,
    this.onCancel,
    this.onOpen,
  });

  final AbsenceRequest request;
  final AbsenceType? type;
  final bool inbox;

  /// Whether the request is the reader's own. A lead's own request appears in
  /// their own inbox — the server does not filter it out, deliberately — and it
  /// is the one they may not decide.
  final bool isMine;

  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onWithdraw;
  final VoidCallback? onCancel;

  /// A tap on the card: the request with its whole story and what can still be
  /// done about it.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final name = typeName(context, request, type);
    final decidable = inbox && !isMine && request.status.open;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                absenceIcon(type?.icon),
                size: 18,
                color: absenceColor(context, type?.hue),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inbox ? (request.personName ?? name) : name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        spanLabel(context, request.from, request.to),
                        daysLabel(context, request.milliDays),
                        if (inbox) name,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AbsenceStatusChip(status: request.status),
            ],
          ),
          if (request.note != null && request.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              request.note!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.inkSoft,
              ),
            ),
          ],
          // Only where they mean something: a warning about a decided request
          // is a warning about a decision nobody can take back from here.
          if (request.status.open) ..._warnings(context),
          if (request.status == AbsenceRequestStatus.rejected &&
              (request.decisionNote?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 8),
            AbsenceNoteLine(
              icon: LucideIcons.messageSquareQuote,
              tint: AppColors.danger,
              text: request.decisionNote!,
            ),
          ],
          if (decidable || _canWithdraw || _canCancel) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (decidable) ...[
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(LucideIcons.check, size: 16),
                    label: Text(context.t('absence.request.approve')),
                  ),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(LucideIcons.x, size: 16),
                    label: Text(context.t('absence.request.reject')),
                  ),
                ],
                if (_canWithdraw)
                  OutlinedButton.icon(
                    onPressed: onWithdraw,
                    icon: const Icon(LucideIcons.undo2, size: 16),
                    label: Text(context.t('absence.request.withdraw')),
                  ),
                if (_canCancel)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(LucideIcons.calendarMinus, size: 16),
                    label: Text(context.t('absence.request.cancel')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  bool get _canWithdraw => !inbox && request.withdrawableBy(mine: isMine);

  bool get _canCancel =>
      !inbox && request.cancellableBy(mine: isMine, keeper: false);

  List<Widget> _warnings(BuildContext context) {
    final lines = <(IconData, Color, String)>[
      if (request.balanceShort)
        (
          LucideIcons.triangleAlert,
          AppColors.warning,
          context.t('absence.request.balanceShortRow'),
        ),
      if (request.shortNotice)
        (
          LucideIcons.clock,
          AppColors.warning,
          context.t('absence.request.shortNoticeRow'),
        ),
      if (inbox && request.clashes > 0)
        (
          LucideIcons.users,
          AppColors.inkSoft,
          context.t(
            'absence.request.clashes',
            count: request.clashes,
            variables: {'count': '${request.clashes}'},
          ),
        ),
    ];
    return [
      for (final (icon, tint, text) in lines) ...[
        const SizedBox(height: 6),
        AbsenceNoteLine(icon: icon, tint: tint, text: text),
      ],
    ];
  }
}

class AbsenceNoteLine extends StatelessWidget {
  const AbsenceNoteLine({
    super.key,
    required this.icon,
    required this.tint,
    required this.text,
  });

  final IconData icon;
  final Color tint;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 14, color: tint),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.inkSoft),
        ),
      ),
    ],
  );
}

class AbsenceStatusChip extends StatelessWidget {
  const AbsenceStatusChip({super.key, required this.status});

  final AbsenceRequestStatus status;

  @override
  Widget build(BuildContext context) => _Pill(
    label: context.t(status.labelKey),
    tint: switch (status) {
      AbsenceRequestStatus.submitted => AppColors.accentStrong,
      AbsenceRequestStatus.approved => AppColors.success,
      AbsenceRequestStatus.rejected => AppColors.danger,
      AbsenceRequestStatus.withdrawn ||
      AbsenceRequestStatus.cancelled => AppColors.inkFaint,
    },
  );
}

/// The status of an absence nobody had to decide: entered, or — for sickness —
/// reported. Green like an approved one, because it is in effect the same way;
/// amber is what still waits.
class AbsenceEnteredChip extends StatelessWidget {
  const AbsenceEnteredChip({super.key, required this.sick});

  final bool sick;

  @override
  Widget build(BuildContext context) => _Pill(
    label: context.t(sick ? 'absence.sheet.reported' : 'absence.sheet.entered'),
    tint: sick ? AppColors.inkSoft : AppColors.success,
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.tint});

  final String label;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: tint.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tint),
    ),
  );
}

class AbsenceHistoryRow extends StatelessWidget {
  const AbsenceHistoryRow({
    super.key,
    required this.step,
    this.hideNote = false,
  });

  final AbsenceRequestEvent step;

  /// Leaves the step's note out: the sheet prints the request's own note above
  /// the history, and the step that filed it carries the same words.
  final bool hideNote;

  @override
  Widget build(BuildContext context) {
    final at = step.at;
    final to = step.to;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  to == null
                      ? '—'
                      // From waiting to waiting is an edit; from approved to
                      // approved, leave that sickness shortened (§ 9 BUrlG).
                      : step.from == to && to == AbsenceRequestStatus.submitted
                      ? context.t('absence.request.history.edited')
                      : step.from == to && to == AbsenceRequestStatus.approved
                      ? context.t('absence.request.history.shortened')
                      : context.t(to.labelKey),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (at != null)
                Text(
                  DateFormat.yMMMd(
                    Localizations.localeOf(context).toLanguageTag(),
                  ).add_Hm().format(at),
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                ),
            ],
          ),
          if (!hideNote && step.note != null && step.note!.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              step.note!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.inkSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks for the sentence a decision carries. Resolves to it, or to null when
/// the sheet was dismissed — which is not the same as an empty reason.
Future<String?> showAbsenceReasonSheet(
  BuildContext context, {
  required String titleKey,
  required bool required,
}) => showGlassModal<String>(
  context,
  width: 440,
  builder: (sheetContext) =>
      _ReasonForm(titleKey: titleKey, required: required),
);

class _ReasonForm extends StatefulWidget {
  const _ReasonForm({required this.titleKey, required this.required});

  final String titleKey;
  final bool required;

  @override
  State<_ReasonForm> createState() => _ReasonFormState();
}

class _ReasonFormState extends State<_ReasonForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.messageSquareQuote,
        title: context.t(widget.titleKey),
        subtitle: context.t(
          widget.required
              ? 'absence.request.reasonRequiredHint'
              : 'absence.request.reasonOptionalHint',
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            labelText: context.t('absence.request.reason'),
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t('common.ok'),
        onConfirm: widget.required && _controller.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(_controller.text.trim()),
      ),
    ],
  );
}

/// What a request's type is called, from the catalogue when it is loaded and
/// from the keys the server sent with the row when it is not.
String typeName(
  BuildContext context,
  AbsenceRequest request,
  AbsenceType? type,
) {
  if (type != null) return absenceTypeName(context, type);
  final systemKey = request.typeSystemKey;
  if (systemKey != null && systemKey.isNotEmpty) {
    // The same key the catalogue uses for a built-in nobody renamed, so a row
    // read without the catalogue says exactly what the same row says with it.
    return context.t('absence.type.$systemKey');
  }
  return request.typeKey ?? '—';
}
