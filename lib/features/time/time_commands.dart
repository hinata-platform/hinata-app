import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../search/command_registry.dart';
import 'time_entry_sheet.dart';
import 'time_shortcuts.dart' show toggleTimer;

/// What the time module contributes to the ⌘K palette.
///
/// Listed only while the module is switched on — see [paletteCommands]. Five
/// commands rather than three: the two pages were missing from the palette
/// entirely, which is why somebody looking for the timesheet had to know it was
/// under the Time entry rather than being able to ask for it by name.
final List<PaletteCommand> kTimeCommands = [
  const PaletteCommand(
    id: 'time.toggle',
    labelKey: 'search.cmd.toggleTimer',
    icon: LucideIcons.timer,
    keywords: 'timer start stop track clock',
    closesOnSelect: false,
    onSelect: toggleTimer,
  ),
  PaletteCommand(
    id: 'time.newEntry',
    labelKey: 'search.cmd.logTime',
    icon: LucideIcons.clockPlus,
    keywords: 'time log entry worklog hours record',
    onSelect: (context) => unawaited(showTimeEntrySheet(context)),
  ),
  const PaletteCommand.route(
    id: 'time.focus',
    labelKey: 'search.cmd.focusMode',
    icon: LucideIcons.crosshair,
    route: '/time/focus',
    keywords: 'focus pomodoro concentrate deep work',
  ),
  const PaletteCommand.route(
    id: 'time.list',
    labelKey: 'search.cmd.time',
    icon: LucideIcons.list,
    route: '/time',
    keywords: 'time entries hours worklog',
  ),
  const PaletteCommand.route(
    id: 'time.timesheet',
    labelKey: 'search.cmd.timesheet',
    icon: LucideIcons.table,
    route: '/time/timesheet',
    keywords: 'timesheet grid week hours',
  ),
];
