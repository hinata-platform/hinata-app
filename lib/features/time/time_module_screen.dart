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

class _TimeModuleScreenState extends State<TimeModuleScreen>
    with SingleTickerProviderStateMixin {
  /// The views that have been asked for, and are therefore built.
  ///
  /// A module the reader only ever uses for its calendar must not also hold a
  /// timesheet, an inbox and two lists it never showed — each of them would
  /// read from the server to fill a page nobody opened.
  final Set<TimeView> _opened = {};

  /// The view being left, kept on screen until it has faded out.
  TimeView? _leaving;

  /// Drives the hand-over, and rests at its end.
  ///
  /// The view arriving is painted over the one it replaces and dissolves in
  /// over it; the one underneath keeps its opacity until it is covered. That
  /// is one animated layer rather than two, and no moment in the middle where
  /// both are half transparent and the canvas shows through.
  late final AnimationController _switch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  )..addStatusListener((status) {
    if (status == AnimationStatus.completed && _leaving != null) {
      setState(() => _leaving = null);
    }
  });

  late final Animation<double> _arrive = CurvedAnimation(
    parent: _switch,
    curve: Curves.easeOutCubic,
  );

  /// A hand's breadth of movement, no more: the view arrives rather than flies
  /// in. A fractional offset costs no layer — it is an offset on the paint.
  late final Animation<Offset> _rise =
      Tween<Offset>(begin: const Offset(0, 0.012), end: Offset.zero).animate(
        CurvedAnimation(parent: _switch, curve: Curves.easeOutCubic),
      );

  static const Animation<double> _opaque = AlwaysStoppedAnimation(1);
  static const Animation<Offset> _still = AlwaysStoppedAnimation(Offset.zero);

  @override
  void initState() {
    super.initState();
    _opened.add(widget.view);
  }

  @override
  void dispose() {
    _switch.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TimeModuleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Before the build that follows, so the branch is there to be shown.
    _opened.add(widget.view);
    if (oldWidget.view == widget.view) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _leaving = null;
      _switch.value = 1;
      return;
    }
    _leaving = oldWidget.view;
    _switch.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      // The view on screen is painted last, so the one arriving dissolves in
      // over the one it replaces rather than under it. The branches are keyed,
      // so putting them in a different order does not rebuild any of them.
      for (final view in TimeView.values)
        if (view != widget.view) _branch(view),
      _branch(widget.view),
    ],
  );

  /// One view, in the same wrappers whatever it is doing.
  ///
  /// The chain never changes shape — only what it is told — because a branch
  /// whose wrappers changed would be built again from nothing, and keeping
  /// what it has is the whole point of holding it here.
  ///
  /// A branch behind the others goes on building, which would otherwise mean
  /// its chrome in the shell's bar ([PageChromeVisibility]) and its animations
  /// on the raster thread ([TickerMode]) while nobody is looking at it. While
  /// the two trade places both are drawn; before and after, exactly one is,
  /// and [FadeTransition] at full opacity draws without a layer of its own.
  Widget _branch(TimeView view) {
    final current = view == widget.view;
    final shown = current || view == _leaving;
    return Offstage(
      key: ValueKey(view),
      offstage: !shown,
      child: !_opened.contains(view)
          ? const SizedBox.shrink()
          : IgnorePointer(
              // The view on its way out must not answer a tap meant for the
              // one arriving over it.
              ignoring: !current,
              child: TickerMode(
                enabled: current,
                child: FadeTransition(
                  opacity: current ? _arrive : _opaque,
                  child: SlideTransition(
                    position: current ? _rise : _still,
                    child: PageChromeVisibility(
                      visible: current,
                      child: _view(view),
                    ),
                  ),
                ),
              ),
            ),
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
