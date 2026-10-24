import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/blocs/auth_bloc.dart';
import '../../../core/blocs/paged_cubit.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_case_models.dart';
import '../../../core/repositories/moderation_repository.dart';
import '../../../core/repositories/user_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_filter_bar.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/glass_scope_row.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../shell/page_chrome.dart';
import '../../../core/widgets/read_on_trigger.dart';
import '../../../core/widgets/soft_card.dart';
import '../case/case_detail_cubit.dart';
import '../case/case_view.dart';
import 'case_row.dart';
import 'moderation_cases_cubit.dart';
import 'moderation_summary_cubit.dart';
import 'moderation_summary_scope.dart';
import '../moderation_locations.dart';

export '../moderation_locations.dart'
    show caseViewOf, moderationLocation, suspensionsLocation;

/// The moderators' page (HIN-174): the open, appealed and done cases, urgent
/// first and then the oldest, and one case beside the list on a wide window
/// or as a page of its own on a phone.
///
/// One route for list and case, so the lists and where they were scrolled to
/// stay while cases are opened one after the other.
class ModerationScreen extends StatelessWidget {
  const ModerationScreen({super.key, this.view = CaseView.open, this.caseId});

  final CaseView view;
  final String? caseId;

  @override
  Widget build(BuildContext context) => ModerationSummaryScope(
    child: _ModerationPage(view: view, caseId: caseId),
  );
}

class _ModerationPage extends StatefulWidget {
  const _ModerationPage({required this.view, required this.caseId});

  final CaseView view;
  final String? caseId;

  @override
  State<_ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends State<_ModerationPage> {
  /// List and case side by side from here on.
  static const double _split = 980;
  static const double _listWidth = 420;

  late final ModerationRepository _moderation = context
      .read<ModerationRepository>();
  final Map<CaseView, ModerationCasesCubit> _lists = {};

  /// The names every case of the page names, looked up once; the reader's own
  /// is known from the start.
  late final KnownNames _names = KnownNames({
    if (context.read<AuthBloc>().state.user case final me?)
      me.id: me.displayName,
  });

  /// The bar's pills, kept while their view and numbers stay: the shell
  /// re-publishes its bar for every new widget it is handed.
  _ScopeRow? _scopes;

  ModerationCasesCubit _list(CaseView view) => _lists.putIfAbsent(
    view,
    () => ModerationCasesCubit(_moderation, view)..load(),
  );

  @override
  void dispose() {
    for (final list in _lists.values) {
      unawaited(list.close());
    }
    super.dispose();
  }

  void _openView(CaseView view) => context.go(moderationLocation(view: view));

  void _openCase(String id) =>
      context.go(moderationLocation(view: widget.view, caseId: id));

  void _backToList() => context.go(moderationLocation(view: widget.view));

  void _openMore(Rect? anchor) => unawaited(_more(anchor));

  /// A step moved case [summary]. Its row shows how it stands now while the
  /// case belongs to the list; otherwise it leaves the list, the numbers are
  /// read again, and the other lists read afresh once shown.
  void _caseChanged(CaseSummary summary) {
    final list = _list(widget.view);
    if (_belongsTo(summary, widget.view)) {
      list.replaceItem(summary);
      return;
    }
    list.removeItem(summary.id);
    unawaited(context.read<ModerationSummaryCubit>().refresh());
    for (final view in [..._lists.keys]) {
      if (view != widget.view) unawaited(_lists.remove(view)!.close());
    }
  }

  /// Whether [summary] is one of [view]'s cases, as the server lists them.
  static bool _belongsTo(CaseSummary summary, CaseView view) => switch (view) {
    CaseView.open => summary.state.undecided,
    CaseView.appeal => summary.state == CaseState.appeal,
    CaseView.done => !summary.state.undecided,
  };

  _ScopeRow _scopeRow(int? open, int? appeals) {
    final kept = _scopes;
    if (kept != null &&
        kept.view == widget.view &&
        kept.open == open &&
        kept.appeals == appeals) {
      return kept;
    }
    return _scopes = _ScopeRow(
      view: widget.view,
      open: open,
      appeals: appeals,
      onSelected: _openView,
    );
  }

  Future<void> _more(Rect? anchor) async {
    if (anchor == null) return;
    final choice = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor,
      value: '',
      items: [
        GlassMenuItem(
          value: 'suspensions',
          label: context.t('moderation.suspension.pageTitle'),
          leading: const Icon(LucideIcons.userX, size: 16),
        ),
      ],
    );
    if (choice == 'suspensions' && mounted) context.go(suspensionsLocation);
  }

  Widget _caseScope(String caseId, Widget child) => _CaseScope(
    key: ValueKey(caseId),
    caseId: caseId,
    names: _names,
    onChanged: _caseChanged,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    // Read here, above the shell's bar the pills are drawn in: the bar is no
    // child of this page and finds no summary of its own.
    final (open, appeals) = context.select(
      (ModerationSummaryCubit cubit) =>
          (cubit.state?.open, cubit.state?.appeals),
    );
    final scopes = _scopeRow(open, appeals);
    // A tear-off, so the action equals the last one and the bar stays.
    final more = PageAction(
      icon: LucideIcons.ellipsis,
      label: context.t('moderation.queue.more'),
      onTap: _openMore,
    );
    return BlocProvider.value(
      value: _list(widget.view),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= _split;
          final caseId = widget.caseId;
          if (!split && caseId != null) {
            return PageChrome(
              title: context.t('moderation.queue.title'),
              onBack: _backToList,
              child: _caseScope(
                caseId,
                CaseDetailView(padding: context.pagePadding),
              ),
            );
          }
          if (!split) {
            return PageChrome(
              title: context.t('moderation.queue.title'),
              actions: [more],
              bottom: scopes,
              bottomHeight: kGlassDockRow,
              child: _CaseList(
                view: widget.view,
                selected: null,
                padding: context.pagePadding,
                onOpen: _openCase,
              ),
            );
          }
          return PageChrome(
            title: context.t('moderation.queue.title'),
            actions: [more],
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                context.pageGutter,
                18 + context.topGutter,
                context.pageGutter,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WideHead(scopes: scopes),
                  const SizedBox(height: 18),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: _listWidth,
                          child: _CaseList(
                            view: widget.view,
                            selected: caseId,
                            padding: EdgeInsets.only(
                              bottom: context.bottomGutter + 24,
                            ),
                            onOpen: _openCase,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: caseId == null
                              ? const _NoCaseChosen()
                              : SoftCard(
                                  padding: EdgeInsets.zero,
                                  child: _caseScope(
                                    caseId,
                                    const CaseDetailView(
                                      padding: EdgeInsets.fromLTRB(
                                        24,
                                        22,
                                        24,
                                        24,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One case's cubit, read on open; [onChanged] runs with the case's row after
/// each step moved it.
class _CaseScope extends StatelessWidget {
  const _CaseScope({
    super.key,
    required this.caseId,
    required this.names,
    required this.onChanged,
    required this.child,
  });

  final String caseId;
  final KnownNames names;
  final ValueChanged<CaseSummary> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => CaseDetailCubit(
      context.read<ModerationRepository>(),
      context.read<UserRepository>(),
      caseId,
      names: names,
    )..load(),
    child: BlocListener<CaseDetailCubit, CaseDetailState>(
      listenWhen: (previous, current) =>
          previous.detail != null &&
          current.detail != null &&
          previous.detail!.summary.rev != current.detail!.summary.rev,
      listener: (_, state) => onChanged(state.detail!.summary),
      child: child,
    ),
  );
}

/// The three lists as pills, with the numbers of [open] and appealed cases.
class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.view,
    required this.open,
    required this.appeals,
    required this.onSelected,
  });

  final CaseView view;
  final int? open;
  final int? appeals;
  final ValueChanged<CaseView> onSelected;

  @override
  Widget build(BuildContext context) {
    String label(String key, int? count) {
      final word = context.t('moderation.queue.view.$key');
      return count == null || count == 0
          ? word
          : context.t(
              'moderation.queue.viewCount',
              variables: {'label': word, 'count': '$count'},
            );
    }

    return GlassScopeRow(
      scopes: [
        (
          key: CaseView.open.name,
          icon: LucideIcons.inbox,
          label: label('open', open),
        ),
        (
          key: CaseView.appeal.name,
          icon: LucideIcons.rotateCcw,
          label: label('appeal', appeals),
        ),
        (
          key: CaseView.done.name,
          icon: LucideIcons.archive,
          label: label('done', null),
        ),
      ],
      active: view.name,
      onSelected: (key) => onSelected(caseViewOf(key)),
    );
  }
}

class _WideHead extends StatelessWidget {
  const _WideHead({required this.scopes});

  final Widget scopes;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 18,
    runSpacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    alignment: WrapAlignment.spaceBetween,
    children: [
      Wrap(
        spacing: 18,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.t('moderation.queue.title'),
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: AppType.hero,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: AppColors.ink,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              context.t('moderation.queue.target'),
              style: TextStyle(
                fontSize: AppType.label,
                color: AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
      scopes,
    ],
  );
}

class _NoCaseChosen extends StatelessWidget {
  const _NoCaseChosen();

  @override
  Widget build(BuildContext context) => HiveEmptyState(
    title: context.t('moderation.queue.chooseTitle'),
    message: context.t('moderation.queue.chooseMessage'),
  );
}

/// The cases of one view, read on as the reader scrolls.
class _CaseList extends StatelessWidget {
  const _CaseList({
    required this.view,
    required this.selected,
    required this.padding,
    required this.onOpen,
  });

  final CaseView view;
  final String? selected;
  final EdgeInsets padding;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ModerationCasesCubit, PagedState<CaseSummary>>(
        builder: (context, state) {
          final cubit = context.read<ModerationCasesCubit>();
          if (!state.hasData && state.isLoading) {
            return const Center(child: HiveLoader());
          }
          if (!state.hasData && state.errorKey != null) {
            return HiveEmptyState(
              title: context.t('moderation.queue.failedTitle'),
              message: context.t('moderation.queue.failedMessage'),
              action: OutlinedButton(
                onPressed: () => unawaited(cubit.load()),
                child: Text(context.t('common.retry')),
              ),
            );
          }
          if (state.hasData && state.items.isEmpty) {
            return RefreshIndicator(
              onRefresh: cubit.load,
              child: ListView(
                padding: padding,
                children: [
                  HiveEmptyState(
                    title: context.t('moderation.queue.empty.${view.name}'),
                    message: context.t(
                      'moderation.queue.emptyMessage.${view.name}',
                    ),
                  ),
                ],
              ),
            );
          }
          final now = DateTime.now();
          final me = context.select<AuthBloc, String?>(
            (bloc) => bloc.state.user?.id,
          );
          return RefreshIndicator(
            onRefresh: cubit.load,
            child: ListView.builder(
              // Where the list was scrolled to survives a case opened on a
              // phone, which takes the list's place until Back.
              key: PageStorageKey('moderation-${view.name}'),
              padding: padding,
              itemCount: state.items.length + 1,
              itemBuilder: (context, index) {
                if (index == state.items.length) {
                  return state.hasMore
                      ? ReadOnTrigger(
                          count: state.items.length,
                          loading: state.isLoadingMore,
                          onReadOn: () => unawaited(cubit.loadMore()),
                        )
                      : const SizedBox.shrink();
                }
                final summary = state.items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CaseRow(
                    summary: summary,
                    now: now,
                    meId: me,
                    selected: summary.id == selected,
                    onTap: () => onOpen(summary.id),
                  ),
                );
              },
            ),
          );
        },
      );
}
