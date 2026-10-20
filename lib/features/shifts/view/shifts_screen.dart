import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/repositories/shift_repository.dart';
import '../../shell/page_chrome.dart';
import '../bloc/shift_actions_cubit.dart';
import '../bloc/shift_planning_cubit.dart';
import '../shift_views.dart';
import 'my_shifts_view.dart';
import 'shift_calendar_view.dart';
import 'shift_event_screen.dart';
import 'shift_events_view.dart';

export '../shift_views.dart' show ShiftsView;
export 'shift_calendar_view.dart' show ShiftCalendarQuery;

/// The shift planning module's page (HIN-27, helper surfaces HIN-44).
///
/// The three views keep their own addresses and are held in one
/// [IndexedStack], like the time module: a view is built when first asked
/// for and kept behind the others, so a scrolled list stays where it was.
/// One event (`/shifts/events/:id`) is a sub-page of its own.
class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({
    super.key,
    this.view = ShiftsView.mine,
    this.eventId,
    this.shiftId,
    this.calendarQuery = const ShiftCalendarQuery(),
  });

  /// Which view the address names.
  final ShiftsView view;

  /// The event at `/shifts/events/:id`, null on the three views.
  final String? eventId;

  /// The shift of [eventId] whose sheet opens over the event
  /// (`/shifts/events/:id?shift=`).
  final String? shiftId;

  /// What `/shifts/calendar?project=&span=&date=` asks for.
  final ShiftCalendarQuery calendarQuery;

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  late final ShiftActionsCubit _actions = ShiftActionsCubit(
    context.read<ShiftRepository>(),
  );
  late final ShiftPlanningCubit _planning = ShiftPlanningCubit(
    context.read<ShiftRepository>(),
  );
  final Set<ShiftsView> _opened = {};

  @override
  void initState() {
    super.initState();
    _opened.add(widget.view);
  }

  @override
  void didUpdateWidget(ShiftsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _opened.add(widget.view);
  }

  @override
  void dispose() {
    unawaited(_actions.close());
    unawaited(_planning.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventId = widget.eventId;
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _actions),
        BlocProvider.value(value: _planning),
      ],
      child: eventId != null
          ? ShiftEventScreen(eventId: eventId, shiftId: widget.shiftId)
          : IndexedStack(
              index: ShiftsView.values.indexOf(widget.view),
              sizing: StackFit.expand,
              children: [
                for (final view in ShiftsView.values)
                  if (_opened.contains(view))
                    _Branch(visible: view == widget.view, child: _view(view))
                  else
                    const SizedBox.shrink(),
              ],
            ),
    );
  }

  Widget _view(ShiftsView view) => switch (view) {
    ShiftsView.mine => const MyShiftsPage(),
    ShiftsView.calendar => ShiftCalendarPage(query: widget.calendarQuery),
    ShiftsView.events => const ShiftEventsPage(),
  };
}

/// One view kept built behind the others: its chrome held back and its
/// tickers stopped while it is not the one on screen.
class _Branch extends StatelessWidget {
  const _Branch({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: visible,
    child: PageChromeVisibility(visible: visible, child: child),
  );
}
