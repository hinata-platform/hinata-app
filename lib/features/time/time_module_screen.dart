/// The extended time module as one page with five views (HIN-60).
///
/// Each view keeps its own address — `/time`, `/time/calendar`,
/// `/time/timesheet`, `/time/absences`, `/time/approvals` — so every one of
/// them is a link somebody can send and come back to. What they no longer keep
/// is a page of their own: the router hands all five to this widget under one
/// key, so switching swaps the branch on screen instead of building a new page.
///
/// That is the difference a reader feels. Before, every switch tore the view
/// down and read it back from the server: a list that had been scrolled
/// started at the top again, a month the reader had paged to came back on
/// today, and the spinner ran on a page that had been on screen a second ago.
/// Now a view is built when it is first asked for and kept behind the others,
/// the way the approvals page already keeps its two lists.
library;

import 'package:flutter/material.dart';

import '../shell/page_chrome.dart';
import '../timesheet/timesheet_screen.dart';
import 'absences_screen.dart';
import 'approvals_screen.dart';
import 'time_calendar_screen.dart';
import 'time_screen.dart';
import 'time_views.dart';

class TimeModuleScreen extends StatefulWidget {
  const TimeModuleScreen({super.key, required this.view, this.scope});

  /// The view the address names.
  final TimeView view;

  /// The list `/time/absences` opens on — see [TimeAbsencesScreen.scope].
  final String? scope;

  @override
  State<TimeModuleScreen> createState() => _TimeModuleScreenState();
}

class _TimeModuleScreenState extends State<TimeModuleScreen> {
  /// The views that have been asked for, and are therefore built.
  ///
  /// A module the reader only ever uses for its calendar must not also hold a
  /// timesheet, an inbox and two lists it never showed — each of them would
  /// read from the server to fill a page nobody opened.
  final Set<TimeView> _opened = {};

  @override
  void initState() {
    super.initState();
    _opened.add(widget.view);
  }

  @override
  void didUpdateWidget(TimeModuleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Before the build that follows, so the branch is there to be shown.
    _opened.add(widget.view);
  }

  @override
  Widget build(BuildContext context) {
    const views = TimeView.values;
    return IndexedStack(
      index: views.indexOf(widget.view),
      sizing: StackFit.expand,
      children: [
        for (final view in views)
          if (_opened.contains(view)) _branch(view) else const SizedBox.shrink(),
      ],
    );
  }

  /// One view, told whether it is the one on screen.
  ///
  /// A branch behind the others goes on building, which would otherwise mean
  /// its chrome in the shell's bar ([PageChromeVisibility]) and its animations
  /// on the raster thread ([TickerMode]) while nobody is looking at it.
  Widget _branch(TimeView view) {
    final visible = view == widget.view;
    return TickerMode(
      enabled: visible,
      child: PageChromeVisibility(visible: visible, child: _view(view)),
    );
  }

  Widget _view(TimeView view) => switch (view) {
    TimeView.list => const TimeScreen(),
    TimeView.calendar => const TimeCalendarScreen(),
    // The same grid the base route draws, told that it belongs to the module:
    // paged rows, and a cell of your own that can be typed into.
    TimeView.timesheet => const TimesheetScreen(moduleView: true),
    // Keyed by the scope, because that one is read once when the page is
    // built: a notification about somebody else's request has to open the
    // inbox even when the absences were already on screen.
    TimeView.absences => TimeAbsencesScreen(
      key: ValueKey('absences-${widget.scope ?? ''}'),
      scope: widget.scope,
    ),
    // Reachable even while approvals are switched off, and deliberately: the
    // route answers with what is there, which is then nothing. Gating it here
    // would turn a link somebody was sent into a not-found page on the day an
    // administrator toggles the policy — and the page itself says honestly that
    // there is nothing to decide.
    TimeView.approvals => const ApprovalsScreen(),
  };
}
