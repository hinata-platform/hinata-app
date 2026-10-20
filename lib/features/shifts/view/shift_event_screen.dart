import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/glass_switch_chip.dart';
import '../../../core/widgets/hive_empty_state.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart' show GhostButton;
import '../../../core/widgets/soft_card.dart';
import '../../shell/page_chrome.dart';
import '../../sprint/modals/glass_modal.dart'
    show anchorRectOfContext, showGlassConfirm;
import '../bloc/shift_event_cubit.dart';
import '../bloc/shift_planning_cubit.dart';
import '../shift_views.dart';
import '../widgets/shift_editor.dart';
import '../widgets/shift_event_editor.dart';
import '../widgets/series_scope_dialog.dart';
import '../widgets/shift_plan_actions.dart';
import '../widgets/shift_plan_export.dart';
import '../shift_texts.dart';
import '../widgets/coverage_hex.dart';
import '../widgets/shift_actions.dart';
import '../widgets/shift_row.dart';
import '../widgets/shift_sheet.dart';
import '../widgets/shift_status_badge.dart';
import '../widgets/waitlist_chips.dart';

/// `/shifts/events/:id`: provides the event's cubit.
class ShiftEventScreen extends StatelessWidget {
  const ShiftEventScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) =>
        ShiftEventCubit(context.read<ShiftRepository>(), eventId)..load(),
    child: const ShiftEventView(),
  );
}

/// One event for the helper (HIN-44): the head with the places taken, the
/// "Nur unterbesetzt" filter, and the shifts by day, each with exactly one
/// thing to do. Wide: head 38 %, list 62 %.
class ShiftEventView extends StatelessWidget {
  const ShiftEventView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ShiftEventCubit>().state;
    final detail = state.detail;
    final compact = context.isCompact;
    final canPlan = detail?.summary.canPlan ?? false;
    return PageChrome(
      title: detail?.summary.title ?? context.t('shifts.event.title'),
      actions: detail == null
          ? const []
          : [
              // Everybody who sees the event may take its plan out (HIN-163);
              // the rest of "Mehr" is the planner's.
              PageAction(
                icon: LucideIcons.ellipsis,
                label: context.t('shifts.plan.event.menu'),
                onTap: (anchor) =>
                    unawaited(_eventMenu(context, detail, anchor)),
              ),
              if (canPlan && !detail.summary.cancelled)
                PageAction(
                  icon: LucideIcons.plus,
                  label: context.t('shifts.plan.addShift'),
                  primary: true,
                  onTap: (_) => unawaited(_addShift(context, detail)),
                ),
            ],
      child: detail == null
          ? state.loading || state.errorKey == null
                ? const Center(child: HiveLoader())
                : ListView(
                    padding: context.pagePadding,
                    children: [
                      HiveEmptyState(
                        title: context.t('shifts.loadFailed'),
                        message: context.t(state.errorKey!),
                        action: GhostButton(
                          label: context.t('common.retry'),
                          icon: LucideIcons.refreshCw,
                          onPressed: () =>
                              unawaited(context.read<ShiftEventCubit>().load()),
                        ),
                      ),
                    ],
                  )
          : compact
          ? _Phone(state: state, detail: detail)
          : _Wide(state: state, detail: detail),
    );
  }
}

Future<void> _addShift(BuildContext context, ShiftEventDetail detail) async {
  final cubit = context.read<ShiftEventCubit>();
  final saved = await showShiftEditor(context, event: detail.summary);
  if (saved) unawaited(cubit.load());
}

enum _EventMenu {
  /// Nothing is current: the menu offers actions, it is not a choice, so no row
  /// carries a check.
  none,
  export,
  edit,
  cancel,
  delete,
}

/// The event's "Mehr": export its plan; for a planner also change it, call it
/// off, delete it.
Future<void> _eventMenu(
  BuildContext context,
  ShiftEventDetail detail,
  Rect? anchor,
) async {
  final cubit = context.read<ShiftEventCubit>();
  final summary = detail.summary;
  final canPlan = summary.canPlan;
  final rect = anchor ?? anchorRectOfContext(context) ?? Rect.zero;
  final picked = await showGlassMenu<_EventMenu>(
    context: context,
    anchorRect: rect,
    value: _EventMenu.none,
    width: 280,
    items: [
      GlassMenuItem(
        value: _EventMenu.export,
        label: context.t('shifts.export.menu'),
        leading: Icon(LucideIcons.fileDown, size: 16, color: AppColors.inkSoft),
      ),
      if (canPlan) ...[
        GlassMenuItem(
          value: _EventMenu.edit,
          label: context.t('shifts.plan.event.edit'),
          leading: Icon(
            LucideIcons.squarePen,
            size: 16,
            color: AppColors.inkSoft,
          ),
        ),
        if (!detail.summary.cancelled)
          GlassMenuItem(
            value: _EventMenu.cancel,
            label: context.t('shifts.plan.event.cancel'),
            leading: Icon(LucideIcons.ban, size: 16, color: AppColors.inkSoft),
          ),
        GlassMenuItem(
          value: _EventMenu.delete,
          label: context.t('shifts.plan.event.delete'),
          leading: const Icon(
            LucideIcons.trash2,
            size: 16,
            color: AppColors.danger,
          ),
        ),
      ],
    ],
  );
  if (picked == null || !context.mounted) return;
  switch (picked) {
    case _EventMenu.none:
      return;
    case _EventMenu.export:
      await exportShiftPlan(context, summary, anchor: anchor);
    case _EventMenu.edit:
      final saved = await showShiftEventEditor(context, existing: detail);
      if (saved?.event case final event?) cubit.applyEvent(event);
    case _EventMenu.cancel:
      final ShiftScope? scope;
      if (summary.inSeries) {
        // The scope dialog is the confirmation: one question, not two.
        scope = await askSeriesScope(
          context,
          write: SeriesWrite.cancel,
          day: summary.startsLocal,
          recurrenceLabel: summary.recurrenceLabel,
        );
        if (scope == null || !context.mounted) return;
      } else {
        scope = null;
        final sure = await showGlassConfirm(
          context,
          icon: LucideIcons.ban,
          title: context.t('shifts.plan.event.cancelTitle'),
          message: context.t('shifts.plan.event.cancelMessage'),
          confirmLabel: context.t('shifts.plan.event.cancel'),
          confirmIcon: LucideIcons.ban,
          destructive: true,
        );
        if (sure != true || !context.mounted) return;
      }
      final outcome = await context.read<ShiftPlanningCubit>().cancelEvent(
        summary.id,
        scope: scope,
      );
      if (!context.mounted) return;
      announcePlanOutcome(context, outcome);
      if (outcome.event case final event?) cubit.applyEvent(event);
    case _EventMenu.delete:
      final ShiftScope? scope;
      if (summary.inSeries) {
        scope = await askSeriesScope(
          context,
          write: SeriesWrite.delete,
          day: summary.startsLocal,
          recurrenceLabel: summary.recurrenceLabel,
        );
        if (scope == null || !context.mounted) return;
      } else {
        scope = null;
        final sure = await showGlassConfirm(
          context,
          icon: LucideIcons.trash2,
          title: context.t('shifts.plan.event.deleteTitle'),
          message: context.t('shifts.plan.event.deleteMessage'),
          confirmLabel: context.t('shifts.plan.delete'),
          confirmIcon: LucideIcons.trash2,
          destructive: true,
        );
        if (sure != true || !context.mounted) return;
      }
      final outcome = await context.read<ShiftPlanningCubit>().deleteEvent(
        summary.id,
        scope: scope,
      );
      if (!context.mounted) return;
      announcePlanOutcome(context, outcome);
      if (outcome.ok) context.go(ShiftsView.events.route);
  }
}

class _Phone extends StatelessWidget {
  const _Phone({required this.state, required this.detail});

  final ShiftEventState state;
  final ShiftEventDetail detail;

  @override
  Widget build(BuildContext context) {
    final rows = _rows(context, state, detail, stacked: true);
    return RefreshIndicator(
      onRefresh: () => context.read<ShiftEventCubit>().load(),
      child: ListView.builder(
        padding: context.pagePadding,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rows.length + 2,
        itemBuilder: (context, index) => switch (index) {
          0 => _Head(state: state, detail: detail),
          1 => const SizedBox(height: 24),
          _ => rows[index - 2],
        },
      ),
    );
  }
}

class _Wide extends StatelessWidget {
  const _Wide({required this.state, required this.detail});

  final ShiftEventState state;
  final ShiftEventDetail detail;

  @override
  Widget build(BuildContext context) {
    final rows = _rows(context, state, detail, stacked: false);
    final pad = context.pagePadding;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 38,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad.left, pad.top, 0, pad.bottom),
            child: _Head(state: state, detail: detail),
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          flex: 62,
          child: RefreshIndicator(
            onRefresh: () => context.read<ShiftEventCubit>().load(),
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(0, pad.top, pad.right, pad.bottom),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: rows.length,
              itemBuilder: (context, index) => rows[index],
            ),
          ),
        ),
      ],
    );
  }
}

/// The rows of the list: a header per day, a row per shift, gaps between;
/// or a note when the filter or the event leaves nothing.
List<Widget> _rows(
  BuildContext context,
  ShiftEventState state,
  ShiftEventDetail detail, {
  required bool stacked,
}) {
  final shifts = state.visibleShifts;
  if (shifts.isEmpty) {
    return [
      HiveEmptyState(
        title: context.t(
          detail.shifts.isEmpty
              ? 'shifts.event.noShifts'
              : 'shifts.event.noUnderstaffed',
        ),
      ),
    ];
  }
  final out = <Widget>[];
  DateTime? day;
  for (final shift in shifts) {
    final start = shift.startsLocal;
    final d = DateTime(start.year, start.month, start.day);
    if (day != d) {
      if (day != null) out.add(const SizedBox(height: 10));
      out.add(ShiftSectionLabel(dayLabel(context, d)));
      day = d;
    }
    out
      ..add(_EventShiftRow(shift: shift, detail: detail, stacked: stacked))
      ..add(const SizedBox(height: 10));
  }
  return out;
}

class _EventShiftRow extends StatelessWidget {
  const _EventShiftRow({
    required this.shift,
    required this.detail,
    required this.stacked,
  });

  final Shift shift;
  final ShiftEventDetail detail;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final offer = shiftOfferFor(
      shift,
      selfAssignable: summary.selfAssignable,
      eventCancelled: summary.cancelled,
    );
    final named = [
      for (final id in shift.assigneeIds)
        if (detail.users[id] != null) detail.users[id]!,
    ];
    void apply(Shift? after) {
      if (after != null && context.mounted) {
        context.read<ShiftEventCubit>().applyShift(after);
      }
    }

    // A planner has one thing to do with a row: put somebody on it. The
    // helper's own answer (confirm, give up) is in the sheet for them.
    final planning = summary.canPlan && !shift.cancelled && !summary.cancelled;
    // The caller's place, named by the server (`myAssignment`): the action
    // it asks for goes right on the row, "Austragen" included.
    final held = shift.mine && shift.myAssignmentId != null;
    final Widget? trailing = planning
        ? shift.coverage.state == CoverageState.full
              ? ShiftOfferView(
                  offer: const ShiftOffer(noteKey: 'shifts.offer.full'),
                  shift: shift,
                  onAction: (_) {},
                )
              : AssignButton(shift: shift, onDone: (o) => apply(o.shift))
        : shift.mine && !held
        ? ShiftStatusBadge(
            status: shift.myStatus ?? ShiftAssignmentStatus.unknown,
          )
        : offer.isEmpty
        ? null
        : ShiftOfferView(
            offer: offer,
            shift: shift,
            showSecondary: offer.primary == null,
            onAction: (action) => startShiftAction(
              context,
              action,
              shift: shift,
              then: (outcome) {
                if (outcome.ok) apply(outcome.shift);
              },
            ),
          );
    return ShiftRow(
      shift: shift,
      stacked: stacked,
      people: [for (final u in named) u.name],
      avatars: [for (final u in named) u.avatarUrl],
      trailing: trailing,
      // Who waits, behind the people on it; a planner gives a free place to
      // one of them from here (HIN-162).
      extra: planning && shift.waitingIds.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: WaitlistChips(
                shift: shift,
                users: detail.users,
                onAssign: (userId, name) => unawaited(
                  assignFromWaitlist(context, shift, userId, name).then((o) {
                    if (o != null && o.ok) apply(o.shift);
                  }),
                ),
              ),
            )
          : null,
      onTap: () => unawaited(
        showShiftSheet(
          context,
          shiftId: shift.id,
          anchorRect: anchorRectOfContext(context),
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.state, required this.detail});

  final ShiftEventState state;
  final ShiftEventDetail detail;

  @override
  Widget build(BuildContext context) {
    final summary = detail.summary;
    final compact = context.isCompact;
    final coverage = summary.coverage;
    final understaffed = summary.shiftsUnderstaffed > 0;
    final zone = detail.shifts.isEmpty
        ? null
        : zoneHint(context, detail.shifts.first, summary.timezone);
    final where = [
      eventSpanLabel(context, summary.startsLocal, summary.endsLocal),
      if (summary.location != null) summary.location!,
    ].join(' · ');
    final series = seriesLine(
      context,
      seriesId: summary.seriesId,
      recurrenceLabel: summary.recurrenceLabel,
      detached: summary.detached,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            summary.title,
            style: TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: compact ? AppType.display : AppType.hero,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppColors.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          where,
          style: TextStyle(fontSize: AppType.body, color: AppColors.inkSoft),
        ),
        if (series != null) ...[
          const SizedBox(height: 8),
          _Line(
            icon: LucideIcons.repeat,
            text: series,
            color: AppColors.inkSoft,
          ),
        ],
        if (summary.cancelled) ...[
          const SizedBox(height: 10),
          _Line(
            icon: LucideIcons.ban,
            text: context.t('shifts.event.cancelled'),
            color: AppColors.danger,
          ),
        ],
        const SizedBox(height: 16),
        SoftCard(
          padding: const EdgeInsets.all(16),
          // The cell is decorative; the sentence beside it is the figure.
          child: MergeSemantics(
            child: Row(
              children: [
                HoneyCell(
                  fill: coverage.fill,
                  label: '${summary.placesTaken} / ${summary.placesRequired}',
                  size: 52,
                  warning: understaffed,
                  animate: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t(
                          'shifts.event.placesTaken',
                          variables: {
                            'taken': summary.placesTaken,
                            'required': summary.placesRequired,
                          },
                        ),
                        style: TextStyle(
                          fontSize: AppType.title,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      _Line(
                        icon: understaffed
                            ? LucideIcons.triangleAlert
                            : LucideIcons.check,
                        text: eventStaffingLabel(
                          context,
                          summary.shiftsUnderstaffed,
                        ),
                        color: understaffed
                            ? AppColors.warningInk
                            : AppColors.successInk,
                        bold: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Line(
          icon: summary.selfAssignable
              ? LucideIcons.doorOpen
              : LucideIcons.doorClosed,
          text: context.t(
            summary.selfAssignable
                ? 'shifts.event.selfAssignOpen'
                : 'shifts.event.plannersOnly',
          ),
          color: AppColors.inkSoft,
        ),
        if (zone != null) ...[
          const SizedBox(height: 8),
          _Line(icon: LucideIcons.globe, text: zone, color: AppColors.inkSoft),
        ],
        const SizedBox(height: 12),
        // The chip sits in its own flat bar: a chip alone has no surface while
        // it is off, and its padding then reads as an indent against the lines
        // above. The label keeps to one line; on a phone at twice the text
        // size it would run past the edge, so there the bar shrinks to fit.
        LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: GlassSwitchBar(
              inline: true,
              maxWidth: constraints.maxWidth,
              chips: [
                GlassSwitchChip(
                  label: context.t('shifts.event.onlyUnderstaffed'),
                  icon: LucideIcons.filter,
                  active: state.understaffedOnly,
                  onTap: () =>
                      context.read<ShiftEventCubit>().toggleUnderstaffed(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.text,
    required this.color,
    this.bold = false,
  });

  final IconData icon;
  final String text;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: ExcludeSemantics(child: Icon(icon, size: 15, color: color)),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppType.label,
            color: color,
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    ],
  );
}
