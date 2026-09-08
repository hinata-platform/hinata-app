import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/theme_cubit.dart';
import '../time/time_commands.dart';

/// What the ⌘K palette can *do*, as opposed to what it can find.
///
/// A list a feature contributes to, rather than a literal inside the palette's
/// controller. The controller's list was private and had no way to know about
/// the time module — which is how it came to be missing `/timesheet` — and the
/// only way to add a command was to edit a file that has nothing to do with the
/// feature the command belongs to.
///
/// The palette turns these into its own rows; nothing here knows what a row
/// looks like.
@immutable
class PaletteCommand {
  const PaletteCommand({
    required this.id,
    required this.labelKey,
    required this.icon,
    this.route,
    this.onSelect,
    this.keywords = '',
    this.hint,
    this.closesOnSelect = true,
  }) : assert(
         route != null || onSelect != null,
         'A command either goes somewhere or does something.',
       );

  /// A command that only navigates somewhere. The overwhelming majority, and
  /// the reason the list can be `const`: a closure is not a constant, and one
  /// per destination would be seven closures that all say `context.go`.
  const PaletteCommand.route({
    required this.id,
    required this.labelKey,
    required this.icon,
    required String this.route,
    this.keywords = '',
    this.hint,
  }) : onSelect = null,
       closesOnSelect = true;

  final String id;
  final String labelKey;
  final IconData icon;

  /// Extra words that should find it, in English and lower case — a reader
  /// searching "pomodoro" should land on the focus mode whatever it is called
  /// in their language. The localized label is added to these by the palette.
  final String keywords;

  /// A key hint shown on the row, where one exists.
  final String? hint;

  /// Whether choosing it dismisses the palette. False for a toggle somebody may
  /// want to press twice.
  final bool closesOnSelect;

  /// Where it goes, for a navigation command; null for one that acts.
  final String? route;

  /// What it does, for one that acts; null for one that only navigates.
  final void Function(BuildContext context)? onSelect;

  void invoke(BuildContext context) {
    final route = this.route;
    if (route != null) {
      context.go(route);
      return;
    }
    onSelect!(context);
  }
}

/// Everything on offer right now.
///
/// [advancedTime] gates the module's own commands: a server that does not
/// offer it must not list five commands that all lead to a not-found page.
List<PaletteCommand> paletteCommands({required bool advancedTime}) => [
  ...kNavigationCommands,
  ...kAppCommands,
  if (advancedTime) ...kTimeCommands,
];

/// Going somewhere. The app's primary destinations, in the order the rail has
/// them.
const List<PaletteCommand> kNavigationCommands = [
  PaletteCommand.route(
    id: 'nav.dashboard',
    labelKey: 'search.cmd.dashboard',
    icon: LucideIcons.layoutDashboard,
    route: '/dashboard',
    keywords: 'navigate jump home',
  ),
  PaletteCommand.route(
    id: 'nav.projects',
    labelKey: 'search.cmd.projects',
    icon: LucideIcons.squareKanban,
    route: '/projects',
    keywords: 'navigate jump',
  ),
  PaletteCommand.route(
    id: 'nav.issues',
    labelKey: 'search.cmd.issues',
    icon: LucideIcons.circleCheck,
    route: '/issues',
    keywords: 'navigate jump tickets',
  ),
  PaletteCommand.route(
    id: 'nav.board',
    labelKey: 'search.cmd.board',
    icon: LucideIcons.columns3,
    route: '/board',
    keywords: 'navigate jump kanban',
  ),
  PaletteCommand.route(
    id: 'nav.timeline',
    labelKey: 'search.cmd.timeline',
    icon: LucideIcons.chartColumnStacked,
    route: '/gantt',
    keywords: 'navigate jump gantt',
  ),
  PaletteCommand.route(
    id: 'nav.reports',
    labelKey: 'search.cmd.reports',
    icon: LucideIcons.chartLine,
    route: '/reports',
    keywords: 'navigate jump',
  ),
  PaletteCommand.route(
    id: 'nav.knowledge',
    labelKey: 'search.cmd.knowledge',
    icon: LucideIcons.bookOpen,
    route: '/knowledge',
    keywords: 'navigate jump wiki docs',
  ),
];

/// Doing something, rather than going somewhere.
final List<PaletteCommand> kAppCommands = [
  const PaletteCommand.route(
    id: 'app.newIssue',
    labelKey: 'search.cmd.newIssue',
    icon: LucideIcons.plus,
    route: '/board',
    keywords: 'new issue create add task bug',
    hint: 'C',
  ),
  PaletteCommand(
    id: 'app.theme',
    labelKey: 'search.cmd.toggleTheme',
    icon: LucideIcons.sunMoon,
    keywords: 'theme dark light appearance mode',
    closesOnSelect: false,
    onSelect: (context) {
      final cubit = context.read<ThemeCubit>();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      cubit.setMode(isDark ? ThemeMode.light : ThemeMode.dark);
    },
  ),
];
