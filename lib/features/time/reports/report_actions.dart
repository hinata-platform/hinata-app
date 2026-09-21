import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/repositories/time_report_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/file_download.dart';
import '../../../core/util/share_origin.dart';
import '../../../core/widgets/person_picker.dart';
import '../../sprint/modals/glass_modal.dart';

/// What the head of the report page does with a report (HIN-93): take it out
/// as a file or on paper, keep it under a name, mail it on a schedule.

/// The ways out of the app a report has.
enum ReportFile {
  pdf(
    'pdf',
    'application/pdf',
    'time.reports.export.pdf',
    LucideIcons.fileText,
  ),
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'time.reports.export.xlsx',
    LucideIcons.fileSpreadsheet,
  ),
  csv('csv', 'text/csv', 'time.reports.export.csv', LucideIcons.fileType),
  docx(
    'docx',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'time.reports.export.docx',
    LucideIcons.fileText,
  ),
  print(null, null, 'time.reports.export.print', LucideIcons.printer);

  const ReportFile(this.extension, this.mimeType, this.labelKey, this.icon);

  /// What the time report comes out as; it has no Word file.
  static const forTime = [pdf, xlsx, csv, print];

  /// What the absence report comes out as (HIN-119).
  static const forAbsences = [pdf, xlsx, csv, docx, print];

  final String? extension;
  final String? mimeType;
  final String labelKey;
  final IconData icon;
}

/// The export menu, anchored where it was asked for — the same popover the
/// issue export opens, so the two read as one idiom.
Future<ReportFile?> showReportFileMenu(
  BuildContext context,
  Rect? anchor, {
  List<ReportFile> files = ReportFile.forTime,
}) => showGlassOptions<ReportFile>(
  context,
  title: context.t('time.reports.export.title'),
  anchorRect: anchor,
  options: [
    for (final file in files)
      (
        value: file,
        child: Row(
          children: [
            Icon(file.icon, size: 16, color: AppColors.inkSoft),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.t(file.labelKey),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
  ],
);

/// Takes the report out as [file]: a download, a share sheet, or the print
/// dialog. Says what happened, and that a file was cut short when it was.
Future<void> exportReport(
  BuildContext context, {
  required ReportQuery query,
  required ReportFile file,
  required int weekStart,
  Rect? anchor,
}) async {
  final repository = context.read<TimeReportRepository>();
  final origin = shareOriginOf(context, preferred: anchor);
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  try {
    if (file == ReportFile.print) {
      final pdf = await repository.export(query, 'pdf', weekStart: weekStart);
      // layoutPdf opens the print dialog; the bytes are handed back on every
      // page-format change instead of being rendered again on the server.
      await Printing.layoutPdf(
        onLayout: (_) async => pdf.bytes,
        name: 'time-report-$today.pdf',
      );
      return;
    }
    final name = 'time-report-$today.${file.extension}';
    var truncated = false;
    final DownloadResult result;
    if (kIsWeb) {
      final bytes = await repository.export(
        query,
        file.extension!,
        weekStart: weekStart,
      );
      truncated = bytes.truncated;
      result = await downloadBytes(
        name,
        bytes.bytes,
        file.mimeType!,
        sharePositionOrigin: origin,
      );
    } else {
      // Straight to disk: a hundred thousand rows are tens of megabytes a phone
      // should not have to hold in memory to save them.
      result = await downloadFile(name, file.mimeType!, (path) async {
        truncated = await repository.exportTo(
          query,
          file.extension!,
          path,
          weekStart: weekStart,
        );
      }, sharePositionOrigin: origin);
    }
    if (!context.mounted || result.outcome == DownloadOutcome.dismissed) return;
    final failed = result.outcome == DownloadOutcome.failed;
    showGlassToast(
      context,
      context.t(
        failed
            ? 'time.reports.export.failed'
            : truncated
            ? 'time.reports.export.truncated'
            : 'time.reports.export.done',
      ),
      kind: failed ? GlassToastKind.error : GlassToastKind.success,
    );
  } on ApiFailure catch (failure) {
    if (!context.mounted) return;
    showGlassToast(
      context,
      context.t(failure.message),
      kind: GlassToastKind.error,
    );
  }
}

/// Asks for a report's name. Resolves to the trimmed name, or null.
Future<String?> askReportName(
  BuildContext context, {
  required String titleKey,
  String initial = '',
}) => showGlassModal<String>(
  context,
  width: 440,
  builder: (_) => _NameForm(titleKey: titleKey, initial: initial),
);

class _NameForm extends StatefulWidget {
  const _NameForm({required this.titleKey, required this.initial});

  final String titleKey;
  final String initial;

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.bookmarkPlus,
          title: context.t(widget.titleKey),
          subtitle: context.t('time.reports.saved.emptyHint'),
          subtitleMaxLines: 3,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
          child: GlassField(
            label: context.t('time.reports.save.name'),
            child: TextField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) => setState(() {}),
              decoration: glassInputDecoration(
                hint: context.t('time.reports.save.nameHint'),
              ).copyWith(counterText: ''),
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t(widget.titleKey),
          onConfirm: _name.text.trim().isEmpty ? null : _submit,
        ),
      ],
    );
  }
}

/// When a saved report is mailed and to whom. Resolves to the schedule, or
/// null when dismissed. [names] labels the recipients already chosen.
Future<ReportSchedule?> showReportScheduleSheet(
  BuildContext context, {
  ReportSchedule? current,
  required Map<String, String> names,
}) => showGlassModal<ReportSchedule>(
  context,
  width: 520,
  builder: (_) => _ScheduleForm(current: current, names: names),
);

class _ScheduleForm extends StatefulWidget {
  const _ScheduleForm({required this.current, required this.names});

  final ReportSchedule? current;
  final Map<String, String> names;

  @override
  State<_ScheduleForm> createState() => _ScheduleFormState();
}

class _ScheduleFormState extends State<_ScheduleForm> {
  late ReportCadence _cadence = widget.current?.cadence ?? ReportCadence.weekly;
  late int _weekday = widget.current?.weekday ?? DateTime.monday;
  late int _hour = widget.current?.hour ?? 7;
  late final List<String> _recipients = [...?widget.current?.recipients];

  Future<void> _addRecipient(Rect? anchor) async {
    final picked = await showPersonPicker(
      context,
      anchorRect: anchor ?? Rect.zero,
    );
    if (picked == null || !mounted || _recipients.contains(picked.id)) return;
    widget.names[picked.id] = picked.displayName;
    setState(() => _recipients.add(picked.id));
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    Widget choice(bool selected, String label, VoidCallback onTap) => Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentSoft : Colors.transparent,
            border: Border.all(
              color: selected ? AppColors.accentLine : AppColors.hairline2,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.mailPlus,
          title: context.t('time.reports.schedule.title'),
          subtitle: context.t('time.reports.schedule.hint'),
          subtitleMaxLines: 3,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  label: context.t('time.reports.schedule.cadence'),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cadence in ReportCadence.values)
                        choice(
                          _cadence == cadence,
                          context.t(cadence.labelKey),
                          () => setState(() => _cadence = cadence),
                        ),
                    ],
                  ),
                ),
                if (_cadence == ReportCadence.weekly) ...[
                  const SizedBox(height: 18),
                  GlassField(
                    label: context.t('time.reports.schedule.day'),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var day = 1; day <= 7; day++)
                          choice(
                            _weekday == day,
                            DateFormat.E(locale).format(DateTime(2024, 1, day)),
                            () => setState(() => _weekday = day),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                GlassField(
                  label: context.t('time.reports.schedule.hour'),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final hour in const [6, 7, 8, 9, 12, 16, 18])
                        choice(
                          _hour == hour,
                          '${'$hour'.padLeft(2, '0')}:00',
                          () => setState(() => _hour = hour),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                GlassField(
                  label: context.t('time.reports.schedule.recipients'),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final id in _recipients)
                        InputChip(
                          label: Text(widget.names[id] ?? id),
                          onDeleted: () =>
                              setState(() => _recipients.remove(id)),
                          deleteButtonTooltipMessage: context.t(
                            'time.reports.sheet.remove',
                            variables: {'name': widget.names[id] ?? id},
                          ),
                          backgroundColor: AppColors.accentSoft,
                          side: BorderSide.none,
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                        ),
                      if (_recipients.length < 50)
                        Builder(
                          builder: (anchor) => TextButton.icon(
                            onPressed: () {
                              final box =
                                  anchor.findRenderObject() as RenderBox?;
                              unawaited(
                                _addRecipient(
                                  box == null || !box.hasSize
                                      ? null
                                      : box.localToGlobal(Offset.zero) &
                                            box.size,
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              minimumSize: const Size(48, 44),
                              foregroundColor: AppColors.accentInk,
                            ),
                            icon: const Icon(LucideIcons.userPlus, size: 16),
                            label: Text(
                              context.t('time.reports.schedule.addRecipient'),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_recipients.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.t('time.reports.schedule.noRecipients'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('time.reports.schedule.save'),
          onConfirm: _recipients.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  ReportSchedule(
                    cadence: _cadence,
                    weekday: _weekday,
                    hour: _hour,
                    recipients: List.of(_recipients),
                  ),
                ),
        ),
      ],
    );
  }
}
