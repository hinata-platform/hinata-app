/// The requests somebody made, and the ones they have to decide (HIN-117).
///
/// Two lists on one page rather than two pages, because they are the same row
/// read from two sides and the difference is one rule on the server — the shape
/// the timesheet approvals settled in HIN-88. Everybody has the first. The
/// second is empty for whoever decides nothing, and an empty inbox is an honest
/// answer rather than a hidden feature.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/auth_bloc.dart';
import '../../core/blocs/paged_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/absence_models.dart';
import '../../core/models/absence_request_models.dart';
import '../../core/repositories/absence_repository.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_loader.dart';
import '../../core/widgets/soft_card.dart';
import '../shell/page_chrome.dart';
import '../sprint/modals/glass_modal.dart';
import 'absence_labels.dart';
import 'absence_request_sheet.dart';

class AbsenceRequestsScreen extends StatefulWidget {
  const AbsenceRequestsScreen({super.key, this.inbox = false});

  /// Which of the two lists the page opens on. A notification about somebody
  /// else's request links to the inbox, and landing on one's own list instead
  /// would make the reader look for what they were told about.
  final bool inbox;

  @override
  State<AbsenceRequestsScreen> createState() => _AbsenceRequestsScreenState();
}

class _AbsenceRequestsScreenState extends State<AbsenceRequestsScreen> {
  /// The reader's own requests.
  static const _mine = 'mine';

  /// The ones waiting for their decision.
  static const _inbox = 'inbox';

  final _scroll = ScrollController();
  late final PagedCubit<AbsenceRequest> _requests;

  late String _scope = widget.inbox ? _inbox : _mine;

  /// The catalogue, for the icon and the colour of a row. The server sends the
  /// key and the system key with every request, which is enough to name one —
  /// this only makes it look like the rest of the module.
  List<AbsenceType> _types = const [];
  AbsenceBalances? _balances;

  String? get _meId => context.read<AuthBloc>().state.user?.id;

  @override
  void initState() {
    super.initState();
    _requests = PagedCubit<AbsenceRequest>(
      (page, size) => _scope == _inbox
          ? context.read<AbsenceRepository>().inbox(page: page, size: size)
          : context.read<AbsenceRepository>().myRequests(page: page, size: size),
      pageSize: 25,
      keyOf: (request) => request.id,
    );
    _scroll.addListener(_onScroll);
    unawaited(_loadCatalogue());
    unawaited(_requests.load());
  }

  @override
  void dispose() {
    _scroll.dispose();
    unawaited(_requests.close());
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      unawaited(_requests.loadMore());
    }
  }

  /// The two answers that do not depend on the list, side by side.
  Future<void> _loadCatalogue() async {
    final repository = context.read<AbsenceRepository>();
    try {
      final results = await Future.wait([
        repository.types(),
        repository.balances(),
      ]);
      if (!mounted) return;
      setState(() {
        _types = results[0] as List<AbsenceType>;
        _balances = results[1] as AbsenceBalances;
      });
    } on ApiFailure {
      // The list is the page; a catalogue that would not load costs the rows
      // their icon and nothing else.
    }
  }

  void _switchScope(String scope) {
    if (_scope == scope) return;
    setState(() => _scope = scope);
    unawaited(_requests.load());
  }

  AbsenceType? _typeOf(AbsenceRequest request) =>
      _types.where((type) => type.id == request.typeId).firstOrNull;

  Future<void> _ask() async {
    final filed = await showAbsenceRequestSheet(
      context,
      types: _types,
      balances: _balances,
    );
    if (filed != null && mounted) unawaited(_reload());
  }

  Future<void> _reportSick() async {
    final reported = await showSickReportSheet(context, types: _types);
    if (reported != null && mounted) unawaited(_reload());
  }

  Future<void> _reload() async {
    await _requests.load();
    if (mounted) unawaited(_loadCatalogue());
  }

  /// Runs one decision and refreshes what it changed.
  ///
  /// Every one of them can fail for a reason the person has to read — a request
  /// somebody else decided a second earlier, a balance that will not cover it —
  /// so the message is the server's own and never a sentence made up here.
  Future<void> _act(Future<AbsenceRequest> Function() step, String doneKey) async {
    try {
      await step();
      if (!mounted) return;
      showGlassToast(context, context.t(doneKey));
      unawaited(_reload());
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  Future<void> _approve(AbsenceRequest request) => _act(
    () => context.read<AbsenceRepository>().approve(request.id),
    'absence.request.approved',
  );

  Future<void> _reject(AbsenceRequest request) async {
    final reason = await showAbsenceReasonSheet(
      context,
      titleKey: 'absence.request.rejectTitle',
      // § 7 Abs. 1 BUrlG allows a refusal only for urgent operational reasons
      // or somebody else's prior claim. An empty field is not one of those, so
      // the sheet will not send one and the server will not take one.
      required: true,
    );
    if (reason == null || !mounted) return;
    await _act(
      () => context.read<AbsenceRepository>().reject(request.id, note: reason),
      'absence.request.rejected',
    );
  }

  Future<void> _withdraw(AbsenceRequest request) => _act(
    () => context.read<AbsenceRepository>().withdraw(request.id),
    'absence.request.withdrawn',
  );

  Future<void> _cancel(AbsenceRequest request) async {
    final reason = await showAbsenceReasonSheet(
      context,
      titleKey: 'absence.request.cancelTitle',
      required: false,
    );
    if (reason == null || !mounted) return;
    await _act(
      () => context.read<AbsenceRepository>().cancel(
        request.id,
        note: reason.isEmpty ? null : reason,
      ),
      'absence.request.cancelled',
    );
  }

  @override
  Widget build(BuildContext context) {
    final on = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.absenceManagement ?? false,
    );
    return PageChrome(
      contentMax: Breakpoints.mediumMax,
      title: context.t('absence.request.pageTitle'),
      actions: on
          ? [
              PageAction(
                icon: LucideIcons.calendarPlus,
                label: context.t('absence.request.ask'),
                primary: true,
                onTap: (_) => unawaited(_ask()),
              ),
              PageAction(
                icon: LucideIcons.thermometer,
                label: context.t('absence.sick.report'),
                onTap: (_) => unawaited(_reportSick()),
              ),
            ]
          : const [],
      child: on ? _body(context) : _off(context),
    );
  }

  /// What the page says on a server that does not offer the module.
  ///
  /// A deep link into a feature this instance has switched off has to land
  /// somewhere that says so, rather than on a spinner that never stops.
  Widget _off(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: HiveEmptyState(
        title: context.t('absence.request.pageTitle'),
        message: context.t('absence.request.moduleOff'),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    final padding = context.pagePadding;
    return BlocProvider.value(
      value: _requests,
      child: BlocBuilder<PagedCubit<AbsenceRequest>, PagedState<AbsenceRequest>>(
        builder: (context, state) => RefreshIndicator(
          onRefresh: _reload,
          edgeOffset: context.topGutter,
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverPadding(
                padding: padding.copyWith(bottom: 12),
                sliver: SliverToBoxAdapter(
                  // Scrollable rather than a plain row: two pills and a long
                  // label in one of the nine languages is wider than a phone,
                  // and a row that overflows hides the half nobody can reach.
                  child: SizedBox(
                    height: kGlassControlHeight,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _pills(),
                    ),
                  ),
                ),
              ),
              ..._rows(context, state, padding),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _pills() => [
    for (final (scope, icon) in const [
      (_mine, LucideIcons.user),
      (_inbox, LucideIcons.inbox),
    ]) ...[
      if (scope != _mine) const SizedBox(width: 8),
      GlassScopePill(
        icon: icon,
        label: context.t('absence.request.scope.$scope'),
        active: _scope == scope,
        onTap: () => _switchScope(scope),
      ),
    ],
  ];

  List<Widget> _rows(
    BuildContext context,
    PagedState<AbsenceRequest> state,
    EdgeInsets padding,
  ) {
    final horizontal = padding.copyWith(top: 0, bottom: 0);
    if (state.isLoading && state.items.isEmpty) {
      return [
        SliverPadding(
          padding: horizontal.copyWith(bottom: padding.bottom),
          sliver: const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: HiveLoader()),
            ),
          ),
        ),
      ];
    }
    if (state.errorKey != null && state.items.isEmpty) {
      return [
        SliverPadding(
          padding: horizontal.copyWith(bottom: padding.bottom),
          sliver: SliverToBoxAdapter(
            child: HiveEmptyState(
              title: context.t('absence.request.pageTitle'),
              message: context.t(state.errorKey!),
              action: OutlinedButton(
                onPressed: () => unawaited(_reload()),
                child: Text(context.t('common.retry')),
              ),
            ),
          ),
        ),
      ];
    }
    if (state.items.isEmpty) {
      return [
        SliverPadding(
          padding: horizontal.copyWith(bottom: padding.bottom),
          sliver: SliverToBoxAdapter(
            child: HiveEmptyState(
              title: context.t('absence.request.empty.$_scope'),
              message: context.t('absence.request.emptyMessage.$_scope'),
              action: _scope == _mine
                  ? FilledButton.icon(
                      onPressed: () => unawaited(_ask()),
                      icon: const Icon(LucideIcons.calendarPlus, size: 16),
                      label: Text(context.t('absence.request.ask')),
                    )
                  : null,
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: horizontal,
        sliver: SliverList.builder(
          itemCount: state.items.length,
          itemBuilder: (context, index) {
            final request = state.items[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AbsenceRequestCard(
                request: request,
                type: _typeOf(request),
                inbox: _scope == _inbox,
                isMine: request.userId == _meId,
                onApprove: () => unawaited(_approve(request)),
                onReject: () => unawaited(_reject(request)),
                onWithdraw: () => unawaited(_withdraw(request)),
                onCancel: () => unawaited(_cancel(request)),
              ),
            );
          },
        ),
      ),
      SliverPadding(
        padding: horizontal.copyWith(bottom: padding.bottom),
        sliver: SliverToBoxAdapter(
          child: state.isLoading
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: HiveLoader(size: 26)),
                )
              : const SizedBox(height: 8),
        ),
      ),
    ];
  }
}

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

  @override
  Widget build(BuildContext context) {
    final name = typeName(context, request, type);
    final decidable = inbox && !isMine && request.status.open;
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: () => unawaited(showAbsenceRequestHistory(context, request, type)),
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
              _StatusChip(status: request.status),
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
            _Note(
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

  bool get _canWithdraw => !inbox && request.status.open;

  /// Cancelling one's own is offered while all of it is still ahead. Once a day
  /// of it is behind the person it takes a keeper, and the server says so — the
  /// button is hidden here rather than offered and refused.
  bool get _canCancel =>
      !inbox &&
      request.status == AbsenceRequestStatus.approved &&
      request.from.isAfter(DateUtils.dateOnly(DateTime.now()));

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
        _Note(icon: icon, tint: tint, text: text),
      ],
    ];
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.tint, required this.text});

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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AbsenceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final tint = switch (status) {
      AbsenceRequestStatus.submitted => AppColors.accentStrong,
      AbsenceRequestStatus.approved => AppColors.success,
      AbsenceRequestStatus.rejected => AppColors.danger,
      AbsenceRequestStatus.withdrawn ||
      AbsenceRequestStatus.cancelled => AppColors.inkFaint,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        context.t(status.labelKey),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: tint,
        ),
      ),
    );
  }
}

/// The story of one request: every step, who took it, and what they wrote.
///
/// Art. 15 and R4: a person reads what was decided about them and why, in the
/// words the decision was given in.
Future<void> showAbsenceRequestHistory(
  BuildContext context,
  AbsenceRequest request,
  AbsenceType? type,
) => showGlassModal<void>(
  context,
  width: 460,
  builder: (sheetContext) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: absenceIcon(type?.icon),
        title: typeName(sheetContext, request, type),
        subtitle: [
          spanLabel(sheetContext, request.from, request.to),
          daysLabel(sheetContext, request.milliDays),
        ].join(' · '),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (request.history.isEmpty)
                HiveEmptyState(
                  title: sheetContext.t('absence.request.noHistory'),
                  card: false,
                )
              else
                for (final step in request.history.reversed)
                  _HistoryRow(step: step),
            ],
          ),
        ),
      ),
    ],
  ),
);

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.step});

  final AbsenceRequestEvent step;

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
                  to == null ? '—' : context.t(to.labelKey),
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
          if (step.note != null && step.note!.isNotEmpty) ...[
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
  builder: (sheetContext) => _ReasonForm(titleKey: titleKey, required: required),
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

/// "15 – 19 Jun 2026", or one date where both ends are the same day.
String spanLabel(BuildContext context, DateTime from, DateTime to) {
  final format = DateFormat.yMMMd(
    Localizations.localeOf(context).toLanguageTag(),
  );
  if (from == to) return format.format(from);
  return '${format.format(from)} – ${format.format(to)}';
}
