import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/shift_models.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/hive_loader.dart';
import '../../../core/widgets/hive_widgets.dart'
    show GhostButton, HiveAvatarStack;
import '../../sprint/modals/glass_modal.dart'
    show kGlassPopoverBreakpoint, showGlassAnchoredPopover, showGlassModal;
import '../bloc/shift_actions_cubit.dart';
import '../bloc/shift_sheet_cubit.dart';
import '../shift_texts.dart';
import 'coverage_hex.dart';
import 'shift_actions.dart';

/// Opens one shift (HIN-44): a sheet on a phone, a popover at [anchorRect] on
/// a wide window, a card in the middle when there is nothing to hang it off.
///
/// [assignment] is the caller's place when the opener already knows it ("Meine
/// Schichten" does); otherwise the detail answer says. [onOpenEvent] is the
/// way to the event's page, left out on that page itself.
Future<void> showShiftSheet(
  BuildContext context, {
  required String shiftId,
  Rect? anchorRect,
  ShiftAssignmentRef? assignment,
  VoidCallback? onOpenEvent,
}) {
  // A root-navigator route: hand the repository and the actions across.
  final repository = context.read<ShiftRepository>();
  final actions = context.read<ShiftActionsCubit>();
  Widget body(BuildContext _) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) =>
            ShiftSheetCubit(repository, shiftId, assignment: assignment)
              ..load(),
      ),
      BlocProvider.value(value: actions),
    ],
    child: ShiftSheetBody(onOpenEvent: onOpenEvent),
  );
  final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
  if (wide && anchorRect != null) {
    return showGlassAnchoredPopover<void>(
      context,
      anchorRect: anchorRect,
      width: 400,
      minHeight: 320,
      maxHeight: 600,
      builder: body,
    );
  }
  return showGlassModal<void>(
    context,
    width: 440,
    adaptive: !wide,
    builder: body,
  );
}

/// The sheet's content, from [ShiftSheetCubit]: title and cell, event and day,
/// time with its length, place, who is missing, the people as chips with the
/// free places beside them, and the one action the state asks for.
class ShiftSheetBody extends StatelessWidget {
  const ShiftSheetBody({super.key, this.onOpenEvent});

  final VoidCallback? onOpenEvent;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShiftSheetCubit, ShiftSheetState>(
      builder: (context, state) {
        final detail = state.detail;
        if (detail == null) {
          return SizedBox(
            height: 220,
            child: Center(
              child: state.loading
                  ? const HiveLoader(size: 32)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.t(state.errorKey ?? 'errors.unexpected'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.inkSoft),
                        ),
                        const SizedBox(height: 12),
                        GhostButton(
                          label: context.t('common.retry'),
                          icon: LucideIcons.refreshCw,
                          onPressed: () =>
                              unawaited(context.read<ShiftSheetCubit>().load()),
                        ),
                      ],
                    ),
            ),
          );
        }
        return _Content(
          detail: detail,
          assignment: state.assignment,
          onOpenEvent: onOpenEvent,
        );
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.detail,
    required this.assignment,
    required this.onOpenEvent,
  });

  final ShiftDetail detail;
  final ShiftAssignmentRef? assignment;
  final VoidCallback? onOpenEvent;

  @override
  Widget build(BuildContext context) {
    final shift = detail.shift;
    final coverage = shift.coverage;
    final event = detail.event;
    final held = (assignment?.status.active ?? false) ? assignment : null;
    final offer = shiftOfferFor(
      shift,
      status: held?.status,
      selfAssignable: event.selfAssignable,
      eventCancelled: event.cancelled,
    );
    final people = [
      for (final id in shift.assigneeIds)
        if (detail.users[id] != null) detail.users[id]!,
    ];
    // Free places to show as chips: up to the need, at most a handful.
    final free = coverage.missing.clamp(0, 6);
    final zone = zoneHint(context, shift, event.timezone);
    final onOpenEvent = this.onOpenEvent;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    shift.title,
                    style: TextStyle(
                      fontFamily: AppTheme.fontBrand,
                      fontSize: AppType.heading,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CoverageHex(
                coverage: coverage,
                size: 34,
                showFigure: false,
                animate: true,
              ),
              IconButton(
                tooltip: context.t('common.close'),
                icon: const Icon(LucideIcons.x, size: 18),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${event.title} · ${dayLabel(context, shift.startsLocal)}',
              style: TextStyle(
                fontSize: AppType.body,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _InfoLine(
            icon: LucideIcons.clock,
            text:
                '${spanLabel(context, shift.startsLocal, shift.endsLocal)} '
                '(${durationLabel(context, shift.duration)})',
          ),
          if (event.location != null)
            _InfoLine(icon: LucideIcons.mapPin, text: event.location!),
          if (zone != null) _InfoLine(icon: LucideIcons.globe, text: zone),
          _InfoLine(
            icon: LucideIcons.users,
            text:
                '${coverageFigure(context, coverage)} · '
                '${coverageWords(context, coverage)}',
          ),
          if (people.isNotEmpty || free > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final person in people) _PersonChip(person: person),
                for (var i = 0; i < free; i++) const _FreeChip(),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!offer.isEmpty)
                  ShiftOfferView(
                    offer: offer,
                    shift: shift,
                    onAction: (action) => startShiftAction(
                      context,
                      action,
                      shift: shift,
                      assignmentId: held?.id,
                      then: (outcome) {
                        if (!outcome.ok || !context.mounted) return;
                        final sheet = context.read<ShiftSheetCubit>();
                        final after = outcome.shift;
                        sheet.adoptAssignment(
                          after == null ||
                                  !after.mine ||
                                  after.myAssignmentId == null
                              ? null
                              : ShiftAssignmentRef(
                                  id: after.myAssignmentId!,
                                  status:
                                      after.myStatus ??
                                      ShiftAssignmentStatus.confirmed,
                                ),
                        );
                        unawaited(sheet.load());
                      },
                    ),
                  ),
                if (onOpenEvent != null)
                  GhostButton(
                    label: context.t('shifts.action.toEvent'),
                    icon: LucideIcons.arrowRight,
                    onPressed: () {
                      Navigator.of(context).maybePop();
                      onOpenEvent();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, right: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: ExcludeSemantics(
            child: Icon(icon, size: 16, color: AppColors.inkFaint),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: AppType.body, color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _PersonChip extends StatelessWidget {
  const _PersonChip({required this.person});

  final ShiftUser person;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
    decoration: BoxDecoration(
      color: AppColors.recess,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: HiveAvatarStack(
            names: [person.name],
            imageUrls: [person.avatarUrl],
            size: 24,
            max: 1,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            person.name,
            style: TextStyle(fontSize: AppType.label, color: AppColors.ink),
          ),
        ),
      ],
    ),
  );
}

class _FreeChip extends StatelessWidget {
  const _FreeChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.warningBar),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.circleDashed, size: 16, color: AppColors.warningInk),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            context.t('shifts.sheet.freeSpot'),
            style: TextStyle(
              fontSize: AppType.label,
              color: AppColors.warningInk,
            ),
          ),
        ),
      ],
    ),
  );
}
