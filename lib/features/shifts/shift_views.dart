import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shell/shell_nav.dart' show shiftsRoute;

/// The three views of the shift planning module, one per route under
/// `/shifts`, switched by the scope pills (wide) or the docked pill (phone).
enum ShiftsView {
  /// `/shifts`: the shifts of the person reading.
  mine(shiftsRoute, 'shifts.view.mine', LucideIcons.userRound),

  /// `/shifts/calendar`: week and month (HIN-160).
  calendar(
    '$shiftsRoute/calendar',
    'shifts.view.calendar',
    LucideIcons.calendarDays,
  ),

  /// `/shifts/events`: the events being planned.
  events('$shiftsRoute/events', 'shifts.view.events', LucideIcons.partyPopper);

  const ShiftsView(this.route, this.labelKey, this.icon);

  final String route;
  final String labelKey;
  final IconData icon;

  static ShiftsView? byName(String? name) {
    for (final view in values) {
      if (view.name == name) return view;
    }
    return null;
  }
}
