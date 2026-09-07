import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/glass_switch_chip.dart';

/// The extended time module's three ways of looking at the same hours.
///
/// Three routes rather than three tabs inside one, so each is a link somebody
/// can send and come back to — and so the shell's back button and title behave
/// the way they do everywhere else. `shell_nav` already treats anything under
/// `/time/` as the module, so all three keep the module's entry lit.
enum TimeView {
  list('/time', 'time.view.list', LucideIcons.list),
  calendar('/time/calendar', 'time.view.calendar', LucideIcons.calendarDays),
  timesheet('/time/timesheet', 'time.view.timesheet', LucideIcons.table);

  const TimeView(this.route, this.labelKey, this.icon);

  final String route;
  final String labelKey;
  final IconData icon;

  /// Which view a location belongs to. Anything unrecognised is the list, which
  /// is the module's front door.
  static TimeView of(String location) => values.firstWhere(
    (view) => view.route == location,
    orElse: () => TimeView.list,
  );
}

/// The switcher every page of the module wears.
///
/// A glass pill with one chip per view, the same control the Gantt chart uses
/// — on a phone it drops to icons and keeps the words in the tooltips, because
/// three labelled chips plus a date and a way back do not fit across a phone.
class TimeViewSwitcher extends StatelessWidget {
  const TimeViewSwitcher({super.key, required this.current});

  final TimeView current;

  @override
  Widget build(BuildContext context) {
    final iconOnly = context.isCompact;
    return ConstrainedBox(
      // Self-limiting, because it is handed to `PageHead.actions` and to a
      // docked row, neither of which bounds what it is given: three chips with
      // long words in them would push the page's title off its own head. Past
      // the ceiling the chips scroll inside the pill — the same shape the Gantt
      // switcher has.
      constraints: BoxConstraints(maxWidth: iconOnly ? 170 : 330),
      child: GlassFloatingSurface(
        radius: (iconOnly ? 44 : 42) / 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final view in TimeView.values) ...[
                  if (view != TimeView.values.first) const SizedBox(width: 2),
                  GlassSwitchChip(
                    label: context.t(view.labelKey),
                    icon: view.icon,
                    active: view == current,
                    iconOnly: iconOnly,
                    // Going rather than pushing: the three are one destination
                    // seen three ways, so stepping back from the calendar belongs
                    // outside the module, not on the list you came through.
                    onTap: view == current
                        ? () {}
                        : () => context.go(view.route),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
