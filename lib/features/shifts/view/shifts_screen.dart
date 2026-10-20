import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/repositories/shift_repository.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/widgets/glass_filter_bar.dart' show kGlassDockRow;
import '../../../core/widgets/hive_empty_state.dart';
import '../../shell/page_chrome.dart';
import '../bloc/shift_actions_cubit.dart';
import '../shift_views.dart';
import '../widgets/shifts_head.dart';
import 'my_shifts_view.dart';
import 'shift_event_screen.dart';
import 'shift_events_view.dart';

export '../shift_views.dart' show ShiftsView;

/// The shift planning module's page (HIN-27, helper surfaces HIN-44).
///
/// The three views keep their own addresses and are held in one
/// [IndexedStack], like the time module: a view is built when first asked
/// for and kept behind the others, so a scrolled list stays where it was.
/// One event (`/shifts/events/:id`) is a sub-page of its own.
class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key, this.view = ShiftsView.mine, this.eventId});

  /// Which view the address names.
  final ShiftsView view;

  /// The event at `/shifts/events/:id`, null on the three views.
  final String? eventId;

  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  late final ShiftActionsCubit _actions = ShiftActionsCubit(
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventId = widget.eventId;
    return BlocProvider.value(
      value: _actions,
      child: eventId != null
          ? ShiftEventScreen(eventId: eventId)
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
    ShiftsView.calendar => const _CalendarPlaceholder(),
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

/// `/shifts/calendar` until the planner surfaces arrive (HIN-160): the
/// module's head and a plain note, so the address is never a dead end.
class _CalendarPlaceholder extends StatelessWidget {
  const _CalendarPlaceholder();

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final note = HiveEmptyState(
      title: context.t('shifts.calendar.soonTitle'),
      message: context.t('shifts.calendar.soonMessage'),
    );
    return PageChrome(
      bottom: compact ? const ShiftsDock(current: ShiftsView.calendar) : null,
      bottomHeight: compact ? kGlassDockRow : 0,
      child: compact
          ? ListView(padding: context.pagePadding, children: [note])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ShiftsHead(current: ShiftsView.calendar),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      context.pageGutter,
                      0,
                      context.pageGutter,
                      context.pageGutter + context.bottomGutter,
                    ),
                    children: [note],
                  ),
                ),
              ],
            ),
    );
  }
}
