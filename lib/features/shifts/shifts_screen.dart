import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/widgets/hive_empty_state.dart';
import '../../core/widgets/hive_widgets.dart' show PageHead;

/// The three views of the shift planning module, one per route under
/// `/shifts`. The pills that switch between them arrive with HIN-44.
enum ShiftsView {
  /// `/shifts`: the shifts of the person reading.
  mine,

  /// `/shifts/calendar`: week and month.
  calendar,

  /// `/shifts/events`: the events being planned.
  events,
}

/// The shift planning module's page (HIN-27).
///
/// Stage 0 (HIN-49) only switches the module on and off, so every route shows
/// the same empty state until the views are built. The routes, the nav entry
/// and the gate already stand, which is what this stage is about.
class ShiftsScreen extends StatelessWidget {
  const ShiftsScreen({super.key, this.view = ShiftsView.mine, this.eventId});

  /// Which view the address names.
  final ShiftsView view;

  /// The event at `/shifts/events/:id`, null on the three views.
  final String? eventId;

  @override
  Widget build(BuildContext context) {
    // A wide window draws no title for a top-level page, so the views name
    // themselves there. One event is a sub-page whose bar already does.
    final showHead = !context.isCompact && eventId == null;
    return ListView(
      padding: context.pagePadding,
      children: [
        if (showHead) ...[
          PageHead(title: context.t('nav.shifts')),
          const SizedBox(height: 14),
        ],
        HiveEmptyState(
          title: context.t('shifts.empty.title'),
          message: context.t('shifts.empty.message'),
        ),
      ],
    );
  }
}
