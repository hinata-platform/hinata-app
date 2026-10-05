/// The extended time module as one page with six views (HIN-60).
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

import 'dart:async';

import 'package:flutter/material.dart';

import '../shell/page_chrome.dart';
import '../timesheet/timesheet_screen.dart';
import 'absences_screen.dart';
import 'approvals_screen.dart';
import 'reports/time_reports_screen.dart';
import 'time_calendar_screen.dart';
import 'time_screen.dart';
import 'time_views.dart';

class TimeModuleScreen extends StatefulWidget {
  const TimeModuleScreen({super.key, required this.view, this.scope});

  /// The view the address names.
  final TimeView view;

  /// The list `/time/absences` opens on — see [TimeAbsencesScreen.scope] —
  /// or the report `/time/reports` opens: `shared:<token>`, `saved:<id>`.
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

  /// The scope each view was last opened with. The address carries only the
  /// visible view's; handing it to the others too would rebuild the reports
  /// behind the absences as a report link named "team", and the absences
  /// behind the reports as a list named after a report.
  final Map<TimeView, String?> _scopes = {};

  @override
  void initState() {
    super.initState();
    _opened.add(widget.view);
    _scopes[widget.view] = widget.scope;
  }

  @override
  void didUpdateWidget(TimeModuleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Before the build that follows, so the branch is there to be shown.
    _opened.add(widget.view);
    _scopes[widget.view] = widget.scope;
  }

  @override
  Widget build(BuildContext context) {
    const views = TimeView.values;
    return IndexedStack(
      index: views.indexOf(widget.view),
      sizing: StackFit.expand,
      children: [
        for (final view in views)
          if (_opened.contains(view))
            _branch(view)
          else
            const SizedBox.shrink(),
      ],
    );
  }

  /// One view, told whether it is the one on screen.
  Widget _branch(TimeView view) =>
      TimeViewBranch(visible: view == widget.view, child: _view(view));

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
      key: ValueKey('absences-${_scopes[view] ?? ''}'),
      scope: _scopes[view],
    ),
    // Keyed by the link, read once when the page is built: a report opened from
    // a mail or a shared link has to open even when the reports were already
    // on screen.
    TimeView.reports => TimeReportsScreen(
      key: ValueKey('reports-${_scopes[view] ?? ''}'),
      link: _scopes[view],
    ),
    // Reachable even while approvals are switched off, and deliberately: the
    // route answers with what is there, which is then nothing. Gating it here
    // would turn a link somebody was sent into a not-found page on the day an
    // administrator toggles the policy — and the page itself says honestly that
    // there is nothing to decide.
    TimeView.approvals => const ApprovalsScreen(),
  };
}

/// One view of the module, kept built behind the others while it is not the
/// one on screen.
///
/// A branch behind the others goes on building, which would otherwise mean
/// its chrome in the shell's bar ([PageChromeVisibility]) and its animations
/// on the raster thread ([TickerMode]) while nobody is looking at it.
///
/// Its tickers stop a moment after it is hidden, not at once. A tooltip is
/// painted in the app's overlay, above the stack, but animated by the widget
/// it belongs to: clicking a switcher chip hid the branch while the chip's
/// tooltip was fading out, the fade froze, and the tooltip stayed burnt in
/// over the next view. The grace lets that fade finish.
class TimeViewBranch extends StatefulWidget {
  const TimeViewBranch({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  /// Longer than any fade a tooltip or a pressed state runs when its view is
  /// left.
  static const grace = Duration(milliseconds: 300);

  @override
  State<TimeViewBranch> createState() => _TimeViewBranchState();
}

class _TimeViewBranchState extends State<TimeViewBranch> {
  late bool _ticking = widget.visible;
  Timer? _stop;

  @override
  void didUpdateWidget(TimeViewBranch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible) {
      _stop?.cancel();
      _ticking = true;
    } else if (oldWidget.visible) {
      _stop?.cancel();
      _stop = Timer(TimeViewBranch.grace, () {
        if (mounted) setState(() => _ticking = false);
      });
    }
  }

  @override
  void dispose() {
    _stop?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: _ticking,
    child: PageChromeVisibility(visible: widget.visible, child: widget.child),
  );
}
