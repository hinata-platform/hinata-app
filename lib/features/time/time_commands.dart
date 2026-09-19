import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../absences/absence_actions.dart';
import '../search/command_registry.dart';
import 'time_entry_sheet.dart';
import 'time_shortcuts.dart' show toggleTimer;

/// What the time module contributes to the ⌘K palette.
///
/// Listed only while the module is switched on — see [paletteCommands]. Every
/// page of the module is in here by name: somebody looking for the timesheet or
/// for their absences had to know which page they sit under before they could
/// find them.
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
    id: 'time.absences',
    labelKey: 'search.cmd.absences',
    icon: LucideIcons.calendarOff,
    route: '/time/absences',
    keywords: 'absence absences vacation leave sick holiday away off',
  ),
  PaletteCommand(
    id: 'time.askAbsence',
    labelKey: 'search.cmd.askAbsence',
    icon: LucideIcons.calendarPlus,
    keywords: 'absence request vacation leave holiday time off ask',
    onSelect: (context) => unawaited(askForAbsence(context)),
  ),
  const PaletteCommand.route(
    id: 'time.timesheet',
    labelKey: 'search.cmd.timesheet',
    icon: LucideIcons.table,
    route: '/time/timesheet',
    keywords: 'timesheet grid week hours',
  ),
];
