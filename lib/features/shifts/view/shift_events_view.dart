import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/models/work_models.dart' show Project;
import '../../../core/repositories/shift_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_filter_bar.dart'
    show GlassFilterPill, kGlassDockRow;
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart'
    show GhostButton, PrimaryButton;
import '../../../core/widgets/project_picker.dart';
import '../../shell/page_chrome.dart';
import '../bloc/shift_events_cubit.dart';
import '../bloc/shift_plannable_cubit.dart';
import '../widgets/shift_event_editor.dart';
import '../shift_views.dart';
import '../widgets/shift_event_card.dart';
import '../widgets/shift_row.dart' show ShiftSectionLabel;
import '../widgets/shifts_head.dart';

/// `/shifts/events`: provides the events list's cubit.
class ShiftEventsPage extends StatelessWidget {
  const ShiftEventsPage({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) =>
            ShiftEventsCubit(context.read<ShiftRepository>())..load(),
      ),
      BlocProvider(
        create: (_) =>
            ShiftPlannableCubit(context.read<ShiftRepository>())..load(),
      ),
    ],
    child: const ShiftEventsView(),
  );
}

/// The events of every visible project, or of one (HIN-44): each with its
/// cell of places taken, its staffing in words and the caller's own count.
class ShiftEventsView extends StatefulWidget {
  const ShiftEventsView({super.key});

  @override
  State<ShiftEventsView> createState() => _ShiftEventsViewState();
}

class _ShiftEventsViewState extends State<ShiftEventsView> {
  /// The project the list is narrowed to; null for all of them.
  Project? _project;

  Future<void> _pickProject(Rect? anchor) async {
    if (anchor == null) return;
    if (_project != null) {
      // Narrowed already: back to all, or another one.
      final choice = await showGlassMenu<String>(
        context: context,
        anchorRect: anchor,
        value: 'current',
        items: [
          GlassMenuItem(
            value: 'all',
            label: context.t('shifts.events.allProjects'),
            leading: Icon(
              LucideIcons.layers,
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
          GlassMenuItem(
            value: 'pick',
            label: context.t('shifts.events.pickProject'),
            leading: Icon(
              LucideIcons.folder,
              size: 16,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      );
      if (choice == null || !mounted) return;
      if (choice == 'all') return _apply(null);
    }
    if (!mounted) return;
    final picked = await showProjectPicker(
      context,
      anchorRect: anchor,
      selected: {if (_project != null) _project!.id},
      titleKey: 'shifts.events.pickProject',
      multi: false,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    await _apply(picked.first);
  }

  Future<void> _apply(Project? project) {
    setState(() => _project = project);
    return context.read<ShiftEventsCubit>().filter(project?.id);
  }

  Widget _projectPill() => GlassFilterPill(
    icon: LucideIcons.folder,
    label: _project?.name ?? context.t('shifts.events.allProjects'),
    active: _project != null,
    onTap: (anchor) => unawaited(_pickProject(anchor)),
  );

  /// A new event, in the project the list is narrowed to when there is one.
  Future<void> _newEvent() async {
    final plannable = context.read<ShiftPlannableCubit>().state;
    final project = _project;
    final saved = await showShiftEventEditor(
      context,
      projectId: project != null && plannable.contains(project.id)
          ? project.id
          : null,
      projectName: project?.name,
      plannable: plannable,
    );
    if (saved != null && mounted) {
      unawaited(
        context.push('${ShiftsView.events.route}/${saved.event.summary.id}'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final canPlan = context.select<ShiftPlannableCubit, bool>(
      (cubit) => cubit.state.isNotEmpty,
    );
    return PageChrome(
      actions: compact && canPlan
          ? [
              PageAction(
                icon: LucideIcons.plus,
                label: context.t('shifts.plan.addEvent'),
                primary: true,
                onTap: (_) => unawaited(_newEvent()),
              ),
            ]
          : const [],
      bottom: compact
          ? ShiftsDock(current: ShiftsView.events, filters: [_projectPill()])
          : null,
      bottomHeight: compact ? kGlassDockRow : 0,
      child: compact
          ? const _List(compact: true)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShiftsHead(
                  current: ShiftsView.events,
                  filters: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _projectPill(),
                      if (canPlan)
                        PrimaryButton(
                          label: context.t('shifts.plan.addEvent'),
                          icon: LucideIcons.plus,
                          onPressed: () => unawaited(_newEvent()),
                        ),
                    ],
                  ),
                ),
                const Expanded(child: _List(compact: false)),
              ],
            ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ShiftEventsCubit>().state;
    final padding = EdgeInsets.fromLTRB(
      context.pageGutter,
      compact ? context.pageGutter + context.topGutter : 4,
      context.pageGutter,
      context.pageGutter + context.bottomGutter,
    );
    if (!state.hasData && state.errorKey == null) {
      return const Center(child: HiveLoader());
    }
    if (!state.hasData) {
      return ListView(
        padding: padding,
        children: [
          HiveEmptyState(
            title: context.t('shifts.loadFailed'),
            message: context.t(state.errorKey!),
            action: GhostButton(
              label: context.t('common.retry'),
              icon: LucideIcons.refreshCw,
              onPressed: () =>
                  unawaited(context.read<ShiftEventsCubit>().load()),
            ),
          ),
        ],
      );
    }
    if (state.items.isEmpty) {
      return ListView(
        padding: padding,
        children: [
          HiveEmptyState(
            title: context.t('shifts.events.emptyTitle'),
            message: context.t('shifts.events.emptyMessage'),
          ),
        ],
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) {
          unawaited(context.read<ShiftEventsCubit>().loadMore());
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: () => context.read<ShiftEventsCubit>().load(),
        child: ListView.builder(
          padding: padding,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: state.items.length + 1 + (state.isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == 0) {
              return ShiftSectionLabel(context.t('shifts.events.upcoming'));
            }
            final i = index - 1;
            if (i >= state.items.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: HiveLoader(size: 26)),
              );
            }
            return _Card(event: state.items[i]);
          },
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.event});

  final ShiftEventSummary event;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      // A card reads as one card, not as a line across a desktop window.
      constraints: const BoxConstraints(maxWidth: 720),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ShiftEventCard(
          event: event,
          onTap: () => context.push('${ShiftsView.events.route}/${event.id}'),
        ),
      ),
    ),
  );
}
