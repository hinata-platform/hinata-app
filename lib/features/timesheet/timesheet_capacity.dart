import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/my_absences_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/availability_models.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_widgets.dart' show fmtDuration;
import '../../core/widgets/soft_card.dart';
import '../absences/absence_actions.dart';
import '../time/day_marks.dart' show formatDaySpan, timeOffIcon;

/// The reader's own capacity for the window the timesheet shows, beside what
/// they booked in it: "32 h of 40 h" (HIN-91).
///
/// Only on the reader's own view. Set against somebody else's rows, or against
/// everybody's, the two figures would describe two different people. And never a
/// target: nothing about the grid changes when the booked hours fall short of it
/// or go past it.
class TimesheetCapacityLine extends StatefulWidget {
  const TimesheetCapacityLine({
    super.key,
    required this.from,
    required this.to,
    required this.bookedMinutes,
  });

  final DateTime from;
  final DateTime to;
  final int bookedMinutes;

  @override
  State<TimesheetCapacityLine> createState() => _TimesheetCapacityLineState();
}

class _TimesheetCapacityLineState extends State<TimesheetCapacityLine> {
  Capacity? _capacity;

  /// Counts reads, so an answer for a window the reader has already left is
  /// dropped rather than drawn over the new one.
  int _read = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TimesheetCapacityLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.from != widget.from || oldWidget.to != widget.to) _load();
  }

  Future<void> _load() async {
    final read = ++_read;
    try {
      final capacity = await context.read<AvailabilityRepository>().capacity(
        widget.from,
        widget.to,
      );
      if (mounted && read == _read) setState(() => _capacity = capacity);
    } on ApiFailure {
      // Planning information: without it the timesheet is complete.
      if (mounted && read == _read) setState(() => _capacity = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capacity = _capacity;
    if (capacity == null) return const SizedBox.shrink();
    final waiting = [
      for (final request in context.watch<MyAbsencesCubit>().state.pending)
        if (!request.to.isBefore(widget.from) &&
            !request.from.isAfter(widget.to))
          request,
    ];
    return BlocListener<MyAbsencesCubit, MyAbsencesState>(
      // An absence of the reader's changed: the capacity it takes away and
      // the chips below are read again.
      listenWhen: (before, after) => before.revision != after.revision,
      listener: (context, state) => _load(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line(context, capacity),
          // The absences behind the figure, and the ones still waiting: the
          // timesheet is where a week is looked at as a whole, and "why is my
          // capacity short" was answered nowhere on it.
          if (capacity.absences.isNotEmpty || waiting.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final absence in capacity.absences)
                  _AbsenceChip(
                    icon: timeOffIcon(absence.type),
                    label:
                        '${context.t(absence.type.labelKey)} · '
                        '${formatDaySpan(context, absence.from, absence.to)}',
                    onTap: () =>
                        unawaited(openAbsence(context, absence: absence)),
                  ),
                for (final request in waiting)
                  _AbsenceChip(
                    icon: LucideIcons.hourglass,
                    label:
                        '${context.t('absence.calendar.requested')} · '
                        '${formatDaySpan(context, request.from, request.to)}',
                    accent: true,
                    onTap: () =>
                        unawaited(openAbsence(context, request: request)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(BuildContext context, Capacity capacity) {
    return Tooltip(
      message: context.t('availability.capacity.hint'),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        // The figures may take most of a phone's width, never all of it: the
        // label shrinks first, and neither pushes past the card.
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Icon(
                LucideIcons.calendarClock,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.t('availability.capacity.title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
                child: Text(
                  context.t(
                    'availability.capacity.ofTotal',
                    variables: {
                      'booked': fmtDuration(context, widget.bookedMinutes),
                      'capacity': fmtDuration(
                        context,
                        capacity.capacityMinutes,
                      ),
                    },
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One absence in the window, as a chip that opens it.
class _AbsenceChip extends StatelessWidget {
  const _AbsenceChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A request still waiting: the accent the calendar hatches it in.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ? AppColors.accentStrong : AppColors.textSecondary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: accent
                ? AppColors.accentStrong.withValues(alpha: 0.10)
                : AppColors.recess,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: accent
                  ? AppColors.accentStrong.withValues(alpha: 0.28)
                  : AppColors.hairline2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: tint),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
