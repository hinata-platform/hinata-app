import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/availability_models.dart';
import '../../core/repositories/availability_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_widgets.dart' show fmtDuration;
import '../../core/widgets/soft_card.dart';

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
