import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/blocs/timer_cubit.dart';
import '../../core/shortcuts/app_shortcuts.dart';
import 'time_entry_sheet.dart';

/// The time module's keyboard shortcuts, and the widget that owns them.
///
/// Registered app-wide rather than by a screen, because that is what they are
/// for: starting a timer without reaching for the mouse is worth least on the
/// page that already has a start button. They come and go with the module's
/// feature flag, so a server that does not offer it does not list keys that do
/// nothing.
///
/// Each borrows the label of the ⌘K command that does the same thing. They are
/// the same action reached two ways, and translating "start or stop the timer"
/// twice in nine languages is eighteen strings that have to be edited in pairs.
///
/// All three are ⇧ combinations on purpose — see [AppShortcut.allowInTextField].
/// Nothing types them, no editor claims them, and they therefore keep working
/// while somebody is writing a description, which is exactly when "stop the
/// timer" is most likely to be wanted.
final List<AppShortcut> kTimeShortcuts = [
  const AppShortcut(
    id: 'time.toggle',
    key: LogicalKeyboardKey.keyS,
    shift: true,
    allowInTextField: true,
    labelKey: 'search.cmd.toggleTimer',
    groupKey: 'shortcuts.group.time',
    onInvoke: toggleTimer,
  ),
  const AppShortcut(
    id: 'time.newEntry',
    key: LogicalKeyboardKey.keyE,
    shift: true,
    allowInTextField: true,
    labelKey: 'search.cmd.logTime',
    groupKey: 'shortcuts.group.time',
    // Held until the sheet closes; two stacked editors would be two half-filled
    // entries and two backdrop blurs.
    exclusive: true,
    onInvoke: showTimeEntrySheet,
  ),
  AppShortcut(
    id: 'time.focus',
    key: LogicalKeyboardKey.keyF,
    shift: true,
    allowInTextField: true,
    labelKey: 'search.cmd.focusMode',
    groupKey: 'shortcuts.group.time',
    onInvoke: (context) => context.go('/time/focus'),
  ),
];

/// Starts a timer, or ends the one that is running.
///
/// Public because the ⌘K palette offers the same thing by name — one behaviour
/// with two ways in, not two implementations of it.
///
/// One key for both, because it is one question — "am I working on this right
/// now" — and because a key that only starts is a key that leaves timers
/// running. What "ending" means for a break is [TimerCubit.end]'s business.
void toggleTimer(BuildContext context) {
  final cubit = context.read<TimerCubit>();
  // The entry, if there is one, is not this key's business: the toast that
  // reports a failure is app-wide, and the overlap advice belongs on the screen
  // where somebody was looking at the hours.
  unawaited(cubit.state.isRunning ? cubit.end() : cubit.start());
}

/// Registers [kTimeShortcuts] for as long as the module is switched on.
///
/// Watching the flag rather than reading it once: an administrator can switch
/// the module on while the app is running, and the keys have to start working
/// without a restart — the same rule the navigation already follows.
class TimeShortcuts extends StatelessWidget {
  const TimeShortcuts({super.key, required this.child, this.enabled = true});

  /// Whether the caller has a reason of its own to withhold them — a session
  /// that is not signed in. The module's own flag is read here.
  final bool enabled;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final moduleOn = context.select<AppConfigBloc, bool>(
      (bloc) => bloc.state.meta?.advancedTimeTracking ?? false,
    );
    // An empty list rather than a different tree: see the note in `app.dart`.
    // An administrator can switch the module on while the app is running, and
    // that must not re-inflate the router.
    return ScopedShortcuts(
      shortcuts: enabled && moduleOn ? kTimeShortcuts : const [],
      child: child,
    );
  }
}
