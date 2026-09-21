import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/time_report_models.dart';
import '../../../core/models/core_models.dart' show DirectoryUser;
import '../../../core/repositories/time_report_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/util/file_pick.dart';
import '../../../core/widgets/hive_widgets.dart' show fmtDuration;
import '../../../core/widgets/person_picker.dart';
import '../../sprint/modals/glass_modal.dart';

/// Time entries from a CSV file (HIN-93), as one glass sheet in three moves:
/// choose the file, see how its columns were read and every row that fails,
/// then import the rows that passed — all of them or none.
///
/// Nothing is written until the last button: the server checks every row the
/// way a typed entry is checked and keeps the result until it is committed or
/// thrown away. Closing the sheet throws it away. Resolves to the number of
/// entries written, or null.
Future<int?> showTimeImportWizard(
  BuildContext context, {
  required bool admin,
}) => showGlassModal<int>(
  context,
  width: 640,
  builder: (_) => _ImportWizard(admin: admin),
);

class _ImportWizard extends StatefulWidget {
  const _ImportWizard({required this.admin});

  final bool admin;

  @override
  State<_ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends State<_ImportWizard> {
  ChosenFile? _file;
  ImportPreview? _preview;
  Map<ImportColumn, int> _mapping = const {};
  bool _mappingChanged = false;
  List<ImportRowError> _errors = const [];
  bool _moreErrors = false;
  bool _busy = false;

  /// Whether the busy line is about writing rather than checking.
  bool _writing = false;
  String? _failure;
  DirectoryUser? _target;
  bool _committed = false;
  late final TimeReportRepository _repository = context
      .read<TimeReportRepository>();

  @override
  void dispose() {
    final preview = _preview;
    // Closed without importing: the server may forget the checked rows now
    // rather than in a day.
    if (preview != null && !_committed) {
      unawaited(_repository.discardImport(preview.importId).catchError((_) {}));
    }
    super.dispose();
  }

  Future<void> _choose() async {
    final List<ChosenFile> chosen;
    try {
      chosen = await pickFilesToUpload(context, withData: kIsWeb);
    } catch (_) {
      return;
    }
    if (chosen.isEmpty || !mounted) return;
    _file = chosen.first;
    _mapping = const {};
    await _check();
  }

  Future<void> _check() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final previous = _preview;
      final preview = await _repository.previewImport(
        fileName: file.name,
        bytes: file.bytes,
        path: file.path,
        mapping: _mapping,
        userId: _target?.id,
      );
      if (previous != null) {
        unawaited(
          _repository.discardImport(previous.importId).catchError((_) {}),
        );
      }
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _mapping = preview.mapping;
        _mappingChanged = false;
        _errors = preview.errors;
        _moreErrors = preview.errorCount > preview.errors.length;
      });
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadMoreErrors() async {
    final preview = _preview;
    if (preview == null) return;
    try {
      final page = await _repository.importErrors(
        preview.importId,
        page: _errors.length ~/ 20,
      );
      if (!mounted) return;
      setState(() {
        _errors = [..._errors, ...page.items];
        _moreErrors = _errors.length < page.total && page.items.isNotEmpty;
      });
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure.message);
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null) return;
    setState(() {
      _busy = true;
      _writing = true;
      _failure = null;
    });
    try {
      final inserted = await _repository.commitImport(preview.importId);
      _committed = true;
      if (mounted) Navigator.of(context).pop(inserted);
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _failure = failure.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _writing = false;
        });
      }
    }
  }

  Future<void> _pickColumn(int index, Rect? anchor) async {
    const ignore = -1;
    final current = _mapping.entries
        .where((entry) => entry.value == index)
        .map((entry) => entry.key)
        .firstOrNull;
    final picked = await showGlassOptions<Object>(
      context,
      title: _preview!.headers[index],
      anchorRect: anchor,
      options: [
        (value: ignore, child: Text(context.t('time.import.ignore'))),
        for (final column in ImportColumn.values)
          if (column != ImportColumn.user || widget.admin)
            (
              value: column,
              child: Text(
                context.t(column.labelKey),
                style: TextStyle(
                  fontWeight: column == current
                      ? FontWeight.w700
                      : FontWeight.w500,
                ),
              ),
            ),
      ],
    );
    if (picked == null || !mounted) return;
    final next = {
      for (final entry in _mapping.entries)
        if (entry.value != index && entry.key != picked) entry.key: entry.value,
      if (picked is ImportColumn) picked: index,
    };
    setState(() {
      _mapping = next;
      _mappingChanged = true;
    });
  }

  Future<void> _pickTarget(Rect? anchor) async {
    final picked = await showPersonPicker(
      context,
      anchorRect: anchor ?? Rect.zero,
    );
    if (picked == null || !mounted) return;
    setState(() => _target = picked);
    if (_file != null) await _check();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassModalHeader(
          icon: LucideIcons.fileUp,
          title: context.t('time.import.title'),
          subtitle: context.t('time.import.pickHint'),
          subtitleMaxLines: 3,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : () => unawaited(_choose()),
                      icon: const Icon(LucideIcons.fileSpreadsheet, size: 16),
                      label: Text(_file?.name ?? context.t('time.import.pick')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 44),
                      ),
                    ),
                    if (widget.admin)
                      Builder(
                        builder: (anchor) => TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () {
                                  final box =
                                      anchor.findRenderObject() as RenderBox?;
                                  unawaited(
                                    _pickTarget(
                                      box == null || !box.hasSize
                                          ? null
                                          : box.localToGlobal(Offset.zero) &
                                                box.size,
                                    ),
                                  );
                                },
                          icon: const Icon(LucideIcons.userRound, size: 16),
                          label: Text(
                            '${context.t('time.import.for')}: '
                            '${_target?.displayName ?? context.t('time.import.me')}',
                          ),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 44),
                            foregroundColor: AppColors.accentInk,
                          ),
                        ),
                      ),
                  ],
                ),
                if (_busy) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        context.t(
                          _writing
                              ? 'time.import.writing'
                              : 'time.import.reading',
                        ),
                        style: TextStyle(color: AppColors.inkSoft),
                      ),
                    ],
                  ),
                ],
                if (_failure != null) ...[
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      context.t(_failure!),
                      style: const TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
                if (preview != null) ..._checked(preview),
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: preview == null
              ? context.t('time.import.commit', count: 0)
              : context.t('time.import.commit', count: preview.validRows),
          confirmIcon: LucideIcons.fileCheck2,
          busy: _busy,
          onConfirm:
              preview == null || preview.validRows == 0 || _mappingChanged
              ? null
              : () => unawaited(_commit()),
        ),
      ],
    );
  }

  List<Widget> _checked(ImportPreview preview) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final caption = TextStyle(fontSize: 12, color: AppColors.inkSoft);
    return [
      const SizedBox(height: 18),
      Semantics(
        liveRegion: true,
        child: Text(
          context.t(
            'time.import.rows',
            variables: {'valid': preview.validRows, 'total': preview.totalRows},
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
      if (preview.errorCount > 0)
        Text(
          context.t('time.import.errors', count: preview.errorCount),
          style: const TextStyle(fontSize: 13, color: AppColors.danger),
        ),
      if (preview.validRows == 0)
        Text(context.t('time.import.nothing'), style: caption),
      const SizedBox(height: 18),
      GlassField(
        label: context.t('time.import.mapping'),
        trailing: _mappingChanged
            ? TextButton(
                onPressed: _busy ? null : () => unawaited(_check()),
                child: Text(context.t('time.import.recheck')),
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.t('time.import.mappingHint'), style: caption),
            const SizedBox(height: 6),
            for (final (index, header) in preview.headers.indexed)
              Builder(
                builder: (anchor) {
                  final column = _mapping.entries
                      .where((entry) => entry.value == index)
                      .map((entry) => entry.key)
                      .firstOrNull;
                  return InkWell(
                    onTap: () {
                      final box = anchor.findRenderObject() as RenderBox?;
                      unawaited(
                        _pickColumn(
                          index,
                          box == null || !box.hasSize
                              ? null
                              : box.localToGlobal(Offset.zero) & box.size,
                        ),
                      );
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              header,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTheme.fontMono,
                                fontSize: 12.5,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          Icon(
                            LucideIcons.arrowRight,
                            size: 14,
                            color: AppColors.inkSoft,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              column == null
                                  ? context.t('time.import.ignore')
                                  : context.t(column.labelKey),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: column == null
                                    ? FontWeight.w400
                                    : FontWeight.w600,
                                color: column == null
                                    ? AppColors.inkSoft
                                    : AppColors.ink,
                              ),
                            ),
                          ),
                          Icon(
                            LucideIcons.chevronDown,
                            size: 14,
                            color: AppColors.inkSoft,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      GlassField(
        label: context.t('time.import.preview'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in preview.rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: MergeSemantics(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text('${row.line}', style: caption),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                if (row.date != null)
                                  DateFormat.yMMMd(locale).format(row.date!),
                                ?row.project,
                                ?row.issue,
                              ].join(' · '),
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.ink,
                              ),
                            ),
                            if ((row.description ?? '').isNotEmpty)
                              Text(
                                row.description!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: caption,
                              ),
                            if (row.error != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    LucideIcons.circleAlert,
                                    size: 13,
                                    color: AppColors.danger,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      row.error!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      if (row.minutes != null)
                        Text(
                          fmtDuration(context, row.minutes),
                          style: TextStyle(
                            fontFamily: AppTheme.fontMono,
                            fontSize: 12.5,
                            color: AppColors.ink,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      if (_errors.isNotEmpty) ...[
        const SizedBox(height: 18),
        GlassField(
          label: context.t('time.import.errorsTitle'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final error in _errors)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text:
                              '${context.t('time.import.line', variables: {'line': error.line})}  ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        TextSpan(text: error.message),
                      ],
                    ),
                    style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                  ),
                ),
              if (_moreErrors)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => unawaited(_loadMoreErrors()),
                    child: Text(context.t('common.seeAll')),
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }
}
