import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';

import '../../../core/api/api_client.dart';
import '../../../core/blocs/absence_report_cubit.dart';
import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/absence_models.dart';
import '../../../core/models/absence_report_models.dart';
import '../../../core/repositories/absence_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/util/file_download.dart';
import '../../../core/util/share_origin.dart';
import '../../../core/widgets/glass_filter_bar.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/project_picker.dart';
import '../../absences/absence_labels.dart';
import '../../absences/absence_report_view.dart';
import '../../sprint/modals/glass_modal.dart';
import 'report_actions.dart';
import 'report_list_parts.dart';

/// The tab "absences" of the report page (HIN-119): balances per person or per
/// type for one leave year, with the ring of the year at the top.
///
/// Who sees what the server decides: a keeper everybody, a lead of a project
/// sums over its people, everybody else themselves. The pills offer only what
/// the reader can ask — a person who keeps nobody's absences gets no "everybody".
///
/// [query] is owned by the page, because its head exports what this tab shows.
class AbsenceReportTab extends StatefulWidget {
  const AbsenceReportTab({
    super.key,
    required this.query,
    required this.padding,
  });

  final ValueNotifier<AbsenceReportQuery> query;

  /// The page's gutter, the bottom inset included — inside the scroll padding.
  final EdgeInsets padding;

  @override
  State<AbsenceReportTab> createState() => _AbsenceReportTabState();
}

class _AbsenceReportTabState extends State<AbsenceReportTab> {
  late final AbsenceRepository _repository = context.read<AbsenceRepository>();
  late final AbsenceReportCubit _rows = AbsenceReportCubit(
    (page, size) =>
        _repository.report(widget.query.value, page: page, size: size),
  );
  List<AbsenceType> _types = const [];
  bool _keeper = false;
  String? _projectName;

  AbsenceReportQuery get _query => widget.query.value;

  @override
  void initState() {
    super.initState();
    widget.query.addListener(_reload);
    unawaited(_start());
  }

  @override
  void dispose() {
    widget.query.removeListener(_reload);
    unawaited(_rows.close());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final answers = await Future.wait([
        _repository.types(),
        _repository.isKeeper(),
      ]);
      if (!mounted) return;
      setState(() {
        _types = (answers[0] as List<AbsenceType>)
            .where((type) => type.countsAgainstBalance && !type.unlimited)
            .toList();
        _keeper = answers[1] as bool;
      });
    } on ApiFailure {
      // The pills fall back to what needs no catalogue; the report still loads.
    }
    unawaited(_rows.load());
  }

  void _reload() => unawaited(_rows.load());

  void _set(AbsenceReportQuery next) {
    if (next != _query) widget.query.value = next;
  }

  String _typeName(String? typeId) {
    final type = _types
        .where((candidate) => candidate.id == typeId)
        .firstOrNull;
    return type == null ? '' : absenceTypeName(context, type);
  }

  // --- pills ------------------------------------------------------------------------

  Future<void> _pickGroup(Rect? anchor) async {
    final picked = await showGlassOptions<AbsenceReportGroupBy>(
      context,
      title: context.t('time.reports.groupBy'),
      anchorRect: anchor,
      options: [
        for (final group in AbsenceReportGroupBy.values)
          (
            value: group,
            child: Text(
              context.t(
                group == AbsenceReportGroupBy.person
                    ? 'absence.report.groupPerson'
                    : 'absence.report.groupType',
              ),
            ),
          ),
      ],
    );
    if (picked != null) _set(_query.copyWith(groupBy: picked));
  }

  Future<void> _pickType(Rect? anchor) async {
    const all = '';
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('absence.report.pickType'),
      anchorRect: anchor,
      options: [
        if (_query.groupBy == AbsenceReportGroupBy.type)
          (value: all, child: Text(context.t('absence.report.allTypes'))),
        for (final type in _types)
          (value: type.id, child: Text(absenceTypeName(context, type))),
      ],
    );
    if (picked == null) return;
    _set(_query.copyWith(typeId: picked == all ? null : picked));
  }

  Future<void> _pickScope(Rect? anchor) async {
    const everybody = '';
    const project = '@project';
    final picked = await showGlassOptions<String>(
      context,
      title: context.t('time.reports.workload.group'),
      anchorRect: anchor,
      options: [
        (
          value: everybody,
          child: Text(
            context.t(
              _keeper ? 'absence.report.everybody' : 'absence.report.onlyMe',
            ),
          ),
        ),
        (value: project, child: Text(context.t('absence.report.pickProject'))),
      ],
    );
    if (picked == null || !mounted) return;
    if (picked == everybody) {
      setState(() => _projectName = null);
      _set(_query.copyWith(projectId: null));
      return;
    }
    final projects = await showProjectPicker(
      context,
      anchorRect: anchor ?? Rect.zero,
      selected: {?_query.projectId},
      titleKey: 'absence.report.pickProject',
      multi: false,
    );
    if (projects == null || projects.isEmpty || !mounted) return;
    setState(() => _projectName = projects.first.name);
    // A lead reads a project as sums per type; only a keeper reads its people.
    _set(
      _query.copyWith(
        projectId: projects.first.id,
        groupBy: _keeper ? null : AbsenceReportGroupBy.type,
      ),
    );
  }

  void _moveYear(int by, int shown) => _set(_query.copyWith(year: shown + by));

  List<Widget> _pills(BuildContext context, AbsenceReportHead? head) {
    final year = _query.year ?? head?.year ?? DateTime.now().year;
    final byPerson = _query.groupBy == AbsenceReportGroupBy.person;
    final lead = !_keeper && _query.projectId != null;
    return [
      GlassStepperPill(
        label: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            context.t('absence.report.year', variables: {'year': '$year'}),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: AppColors.ink,
            ),
          ),
        ),
        onBack: () => _moveYear(-1, year),
        onForward: () => _moveYear(1, year),
        backTooltip: context.t('absence.report.previousYear'),
        forwardTooltip: context.t('absence.report.nextYear'),
      ),
      if (!lead)
        GlassFilterPill(
          icon: LucideIcons.layers,
          label: context.t(
            byPerson
                ? 'absence.report.groupPerson'
                : 'absence.report.groupType',
          ),
          active: !byPerson,
          onTap: (anchor) => unawaited(_pickGroup(anchor)),
        ),
      if (_types.length > 1 || !byPerson)
        GlassFilterPill(
          icon: LucideIcons.tag,
          label: _query.typeId == null
              ? context.t(
                  byPerson
                      ? 'absence.report.pickType'
                      : 'absence.report.allTypes',
                )
              : _typeName(_query.typeId),
          active: _query.typeId != null,
          onTap: (anchor) => unawaited(_pickType(anchor)),
        ),
      GlassFilterPill(
        icon: LucideIcons.folderKanban,
        label:
            _projectName ??
            context.t(
              _keeper ? 'absence.report.everybody' : 'absence.report.onlyMe',
            ),
        active: _query.projectId != null,
        onTap: (anchor) => unawaited(_pickScope(anchor)),
      ),
    ];
  }

  Widget _controls(BuildContext context, AbsenceReportHead? head) {
    final pills = _pills(context, head);
    if (context.isCompact) {
      return SizedBox(
        height: kGlassControlHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
          itemCount: pills.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, index) => pills[index],
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: pills);
  }

  // --- the list -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final padding = widget.padding;
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    final compact = context.isCompact;
    return BlocBuilder<AbsenceReportCubit, PagedState<AbsenceReportRow>>(
      bloc: _rows,
      builder: (context, state) {
        final head = _rows.head;
        final lead = !_keeper && _query.projectId != null;
        return RefreshIndicator(
          onRefresh: _rows.load,
          child: ReportPagedScroll(
            onEnd: _rows.loadMore,
            slivers: [
              SliverPadding(padding: EdgeInsets.only(top: padding.top)),
              SliverPadding(
                padding: compact
                    ? const EdgeInsets.only(bottom: 12)
                    : horizontal.copyWith(bottom: 12),
                sliver: SliverToBoxAdapter(child: _controls(context, head)),
              ),
              if (lead)
                SliverPadding(
                  padding: horizontal.copyWith(bottom: 12),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      context.t('absence.report.leadHint'),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                ),
              if (state.errorKey != null && !state.hasData)
                SliverToBoxAdapter(
                  child: HiveEmptyState(
                    title: context.t(state.errorKey!),
                    action: OutlinedButton(
                      onPressed: _reload,
                      child: Text(context.t('time.reports.retry')),
                    ),
                  ),
                )
              else if (!state.hasData)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: HiveLoader()),
                )
              else if (state.items.isEmpty || head == null)
                SliverToBoxAdapter(
                  child: HiveEmptyState(
                    title: context.t('absence.report.empty'),
                    message: context.t('absence.report.emptyHint'),
                  ),
                )
              else ...[
                SliverPadding(
                  padding: horizontal.copyWith(bottom: 12),
                  sliver: SliverToBoxAdapter(
                    child: AbsenceReportOverview(head: head, compact: compact),
                  ),
                ),
                SliverPadding(
                  padding: horizontal,
                  sliver: SliverToBoxAdapter(
                    child: ReportCardEdge(
                      top: true,
                      child: compact
                          ? const SizedBox(height: 4)
                          : AbsenceReportColumns(
                              groupBy: head.groupBy,
                              rateVisible: head.rateVisible,
                            ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: horizontal,
                  sliver: SliverList.builder(
                    itemCount: state.items.length,
                    itemBuilder: (context, index) {
                      final row = state.items[index];
                      return ReportCardEdge(
                        child: AbsenceReportRowView(
                          row: row,
                          label: row.userId != null
                              ? (row.name ?? '—')
                              : _typeName(row.typeId),
                          compact: compact,
                          rateVisible: head.rateVisible,
                        ),
                      );
                    },
                  ),
                ),
                SliverPadding(
                  padding: horizontal,
                  sliver: const SliverToBoxAdapter(
                    child: ReportCardEdge(
                      last: true,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: AbsenceReportLegend(),
                      ),
                    ),
                  ),
                ),
                if (state.isLoadingMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: HiveLoader(size: 28)),
                    ),
                  ),
              ],
              SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
            ],
          ),
        );
      },
    );
  }
}

/// Takes the absence report out as [file]: a download, a share sheet, or the
/// print dialog — the same ways out as the time report.
Future<void> exportAbsenceReport(
  BuildContext context, {
  required AbsenceReportQuery query,
  required ReportFile file,
  Rect? anchor,
}) async {
  final repository = context.read<AbsenceRepository>();
  final origin = shareOriginOf(context, preferred: anchor);
  final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
  try {
    if (file == ReportFile.print) {
      final pdf = await repository.exportReport(query, 'pdf');
      await Printing.layoutPdf(
        onLayout: (_) async => pdf.bytes,
        name: 'absences-$today.pdf',
      );
      return;
    }
    final name = 'absences-$today.${file.extension}';
    var truncated = false;
    final DownloadResult result;
    if (kIsWeb) {
      final bytes = await repository.exportReport(query, file.extension!);
      truncated = bytes.truncated;
      result = await downloadBytes(
        name,
        bytes.bytes,
        file.mimeType!,
        sharePositionOrigin: origin,
      );
    } else {
      result = await downloadFile(name, file.mimeType!, (path) async {
        truncated = await repository.exportReportTo(
          query,
          file.extension!,
          path,
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
