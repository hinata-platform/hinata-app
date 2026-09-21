import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_report_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../shell/page_chrome.dart';
import '../time/reports/report_list_parts.dart';
import '../sprint/modals/glass_modal.dart';
import 'absence_labels.dart';
import 'absence_year_views.dart';

/// The yearly run, for the people who keep absences (HIN-119): what it did last
/// night, who would lose days without having been told, and the lapses it
/// proposes after a long illness.
///
/// The run itself happens on the server every night; this page only reads it
/// and does the two things the run leaves to a person: sending a notice by
/// hand, and deciding a proposal with a reason. The server refuses both to
/// anybody who does not keep absences, and the page says so when it does.
class AbsenceYearRunScreen extends StatefulWidget {
  const AbsenceYearRunScreen({super.key});

  @override
  State<AbsenceYearRunScreen> createState() => _AbsenceYearRunScreenState();
}

class _AbsenceYearRunScreenState extends State<AbsenceYearRunScreen> {
  late final AbsenceRepository _repository = context.read<AbsenceRepository>();
  late final PagedCubit<AbsenceMissingNotice> _missing =
      PagedCubit<AbsenceMissingNotice>(
        (page, size) => _repository.missingNotices(page: page, size: size),
        keyOf: (row) => row.key,
      );
  late final PagedCubit<AbsenceProposal> _proposals =
      PagedCubit<AbsenceProposal>(
        (page, size) => _repository.proposals(page: page, size: size),
        keyOf: (row) => row.id,
      );
  AbsenceYearRun? _run;
  List<AbsenceType> _types = const [];
  String? _errorKey;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_missing.close());
    unawaited(_proposals.close());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _errorKey = null);
    try {
      final answers = await Future.wait([
        _repository.yearRun(),
        _repository.types(includeInactive: true),
      ]);
      if (!mounted) return;
      setState(() {
        _run = answers[0] as AbsenceYearRun;
        _types = answers[1] as List<AbsenceType>;
      });
      unawaited(_missing.load());
      unawaited(_proposals.load());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _errorKey = failure.message);
    }
  }

  String _typeName(String typeId) {
    final type = _types
        .where((candidate) => candidate.id == typeId)
        .firstOrNull;
    return type == null ? '' : absenceTypeName(context, type);
  }

  Future<void> _send(AbsenceMissingNotice missing) async {
    setState(() => _busy.add(missing.key));
    try {
      await _repository.sendNotice(
        userId: missing.userId,
        typeId: missing.typeId,
        year: missing.year,
      );
      if (!mounted) return;
      showGlassToast(context, context.t('absence.yearRun.sent'));
      unawaited(_missing.load());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t(failure.message));
    } finally {
      if (mounted) setState(() => _busy.remove(missing.key));
    }
  }

  Future<void> _decide(AbsenceProposal proposal, {required bool lapse}) async {
    final decided = await showGlassModal<bool>(
      context,
      width: 460,
      builder: (_) => RepositoryProvider.value(
        value: _repository,
        child: _DecisionForm(
          proposal: proposal,
          typeName: _typeName(proposal.typeId),
          lapse: lapse,
        ),
      ),
    );
    if (decided != true || !mounted) return;
    unawaited(_proposals.load());
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) => PageChrome(
    contentMax: Breakpoints.mediumMax,
    title: context.t('absence.yearRun.pageTitle'),
    child: _body(context),
  );

  Widget _body(BuildContext context) {
    final run = _run;
    if (_errorKey != null && run == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: HiveEmptyState(
            title: context.t('absence.yearRun.pageTitle'),
            message: context.t(_errorKey!),
            action: OutlinedButton(
              onPressed: () => unawaited(_load()),
              child: Text(context.t('common.retry')),
            ),
          ),
        ),
      );
    }
    if (run == null) return const Center(child: HiveLoader());
    final padding = context.pagePadding;
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: context.topGutter,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical &&
              notification.metrics.extentAfter < 600) {
            unawaited(_missing.loadMore());
            unawaited(_proposals.loadMore());
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: padding.copyWith(bottom: 12),
              sliver: SliverToBoxAdapter(
                child: Text(
                  context.t('absence.yearRun.intro'),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.inkSoft,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: horizontal.copyWith(bottom: 20),
              sliver: SliverToBoxAdapter(child: AbsenceYearRunCard(run: run)),
            ),
            ..._section(
              context,
              horizontal: horizontal,
              icon: LucideIcons.gavel,
              titleKey: 'absence.yearRun.proposalsTitle',
              hintKey: 'absence.yearRun.proposalsHint',
            ),
            BlocBuilder<
              PagedCubit<AbsenceProposal>,
              PagedState<AbsenceProposal>
            >(
              bloc: _proposals,
              builder: (context, state) => _list(
                horizontal: horizontal,
                state: state,
                emptyKey: 'absence.yearRun.proposalsEmpty',
                row: (proposal) => AbsenceProposalRow(
                  proposal: proposal,
                  typeName: _typeName(proposal.typeId),
                  onConfirm: () => unawaited(_decide(proposal, lapse: true)),
                  onDismiss: () => unawaited(_decide(proposal, lapse: false)),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            ..._section(
              context,
              horizontal: horizontal,
              icon: LucideIcons.mailWarning,
              titleKey: 'absence.yearRun.missingTitle',
              hintKey: 'absence.yearRun.missingHint',
            ),
            BlocBuilder<
              PagedCubit<AbsenceMissingNotice>,
              PagedState<AbsenceMissingNotice>
            >(
              bloc: _missing,
              builder: (context, state) => _list(
                horizontal: horizontal,
                state: state,
                emptyKey: 'absence.yearRun.missingEmpty',
                row: (missing) => AbsenceMissingRow(
                  missing: missing,
                  typeName: _typeName(missing.typeId),
                  sending: _busy.contains(missing.key),
                  onSend: () => unawaited(_send(missing)),
                ),
              ),
            ),
            SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(
    BuildContext context, {
    required EdgeInsets horizontal,
    required IconData icon,
    required String titleKey,
    required String hintKey,
  }) => [
    SliverPadding(
      padding: horizontal.copyWith(bottom: 8),
      sliver: SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: AppColors.inkSoft),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(titleKey),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    context.t(hintKey),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ];

  /// One of the two lists as a card of rows, lazily, with its empty state.
  Widget _list<T>({
    required EdgeInsets horizontal,
    required PagedState<T> state,
    required String emptyKey,
    required Widget Function(T row) row,
  }) {
    if (!state.hasData) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: HiveLoader(size: 28)),
        ),
      );
    }
    if (state.items.isEmpty) {
      return SliverPadding(
        padding: horizontal,
        sliver: SliverToBoxAdapter(
          child: _Frame(
            child: HiveEmptyState(
              title: context.t(emptyKey),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            ),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: horizontal,
      sliver: SliverList.builder(
        itemCount: state.items.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.items.length) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: HiveLoader(size: 24)),
            );
          }
          return ReportCardEdge(
            top: index == 0,
            last: index == state.items.length - 1,
            child: row(state.items[index]),
          );
        },
      ),
    );
  }
}

/// A plain card around a list of rows.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.hairline),
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// The reason a keeper gives for confirming or dismissing a proposed lapse.
/// Required either way: each decision is about one person's claim.
class _DecisionForm extends StatefulWidget {
  const _DecisionForm({
    required this.proposal,
    required this.typeName,
    required this.lapse,
  });

  final AbsenceProposal proposal;
  final String typeName;
  final bool lapse;

  @override
  State<_DecisionForm> createState() => _DecisionFormState();
}

class _DecisionFormState extends State<_DecisionForm> {
  /// Mirrors `TimeOffProposal.REASON_MAX`.
  static const int _reasonMax = 1000;

  final _reason = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      showGlassErrorToast(context, context.t('error.timeOff.reasonRequired'));
      return;
    }
    setState(() => _saving = true);
    final repository = context.read<AbsenceRepository>();
    try {
      if (widget.lapse) {
        await repository.confirmProposal(widget.proposal.id, reason);
      } else {
        await repository.dismissProposal(widget.proposal.id, reason);
      }
      if (!mounted) return;
      showGlassToast(
        context,
        context.t(
          widget.lapse
              ? 'absence.yearRun.confirmed'
              : 'absence.yearRun.dismissed',
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.gavel,
        title: context.t('absence.yearRun.decisionTitle'),
        subtitle: [
          widget.proposal.name ?? '',
          context.t(
            'absence.yearRun.proposalLine',
            variables: {
              'type': widget.typeName,
              'year': '${widget.proposal.year}',
              'days': daysLabel(context, widget.proposal.milliDays),
            },
          ),
        ].where((part) => part.isNotEmpty).join(' · '),
        subtitleMaxLines: 3,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
        child: TextField(
          controller: _reason,
          autofocus: true,
          maxLength: _reasonMax,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.t('absence.yearRun.reason'),
            helperText: context.t('absence.yearRun.reasonHint'),
            helperMaxLines: 2,
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t(
          widget.lapse ? 'absence.yearRun.confirm' : 'absence.yearRun.dismiss',
        ),
        confirmColor: widget.lapse ? AppColors.danger : null,
        busy: _saving,
        onConfirm: _saving ? null : _save,
      ),
    ],
  );
}
