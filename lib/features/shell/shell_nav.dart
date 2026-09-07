import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The shell's navigation model: which destinations exist, which entry the
/// current location belongs to, and what a route that is *not* a destination
/// calls itself.
///
/// It lives here, apart from the widgets, because it is the part that has to
/// agree with itself. The same location is asked about from five places — the
/// desktop rail, the compact "More" sheet, the active-tab index, the app bar's
/// title, and the back button's fallback — and a location that only four of
/// them recognise produces exactly the bugs you cannot see in a screenshot: an
/// entry that highlights nothing, a sub-page whose bar has no title, a back
/// button that jumps somewhere unrelated.
///
/// Since HIN-83 those answers also depend on a platform flag, which doubles the
/// number of ways they can disagree — so they are pure functions with the flag
/// as a parameter, and they are tested.
class NavDestination {
  const NavDestination(this.route, this.labelKey, this.icon);

  final String route;
  final String labelKey;
  final IconData icon;
}

const primaryDestinations = [
  NavDestination('/dashboard', 'nav.dashboard', LucideIcons.layoutDashboard),
  NavDestination('/teams', 'nav.teams', LucideIcons.usersRound),
  NavDestination('/projects', 'nav.projects', LucideIcons.folder),
  NavDestination('/issues', 'nav.issues', LucideIcons.circleCheckBig),
  NavDestination('/board', 'nav.board', LucideIcons.squareKanban),
];

const bottomTabs = [
  NavDestination('/dashboard', 'nav.dashboard', LucideIcons.layoutDashboard),
  NavDestination('/issues', 'nav.issues', LucideIcons.circleCheckBig),
  NavDestination('/board', 'nav.board', LucideIcons.squareKanban),
  NavDestination('/more', 'nav.more', LucideIcons.layoutGrid),
];

/// The one entry the extended time-tracking module moves.
///
/// With the flag off this is the timesheet, exactly where and what it has always
/// been. With it on, the same slot becomes the module's own entry — a wider name
/// for a wider page, because the timesheet is then one of several things in it.
NavDestination timeDestination({required bool advancedTime}) => advancedTime
    ? const NavDestination('/time', 'nav.time', LucideIcons.timer)
    : const NavDestination('/timesheet', 'nav.timesheet', LucideIcons.table);

/// The desktop rail's second group ("PLAN").
List<NavDestination> secondaryDestinations({required bool advancedTime}) => [
  const NavDestination('/watched', 'nav.watched', LucideIcons.eye),
  const NavDestination('/gantt', 'nav.gantt', LucideIcons.chartColumnStacked),
  timeDestination(advancedTime: advancedTime),
  const NavDestination('/reports', 'nav.reports', LucideIcons.chartLine),
  const NavDestination('/knowledge', 'nav.knowledge', LucideIcons.bookOpen),
];

/// Everything the compact layout keeps behind the "More" sheet.
///
/// Notifications are deliberately absent — they live in the always-visible top
/// bar bell, so they need no entry here.
List<NavDestination> moreSheetDestinations({required bool advancedTime}) => [
  const NavDestination('/projects', 'nav.projects', LucideIcons.folder),
  const NavDestination('/teams', 'nav.teams', LucideIcons.usersRound),
  const NavDestination('/watched', 'nav.watched', LucideIcons.eye),
  const NavDestination('/gantt', 'nav.gantt', LucideIcons.chartColumnStacked),
  timeDestination(advancedTime: advancedTime),
  const NavDestination('/reports', 'nav.reports', LucideIcons.chartLine),
  const NavDestination('/knowledge', 'nav.knowledge', LucideIcons.bookOpen),
];

/// Every destination that can be on screen right now, in nav order — the list
/// the compact app bar searches to name the page it is sitting above.
List<NavDestination> allDestinations({required bool advancedTime}) => [
  ...primaryDestinations,
  ...secondaryDestinations(advancedTime: advancedTime),
];

/// Whether the nav entry for [navRoute] should read as active at [location].
///
/// `/boards/:id` → the Board entry, `/projects/:id/*` → Projects, and so on:
/// a detail page keeps its section lit.
bool isNavActive(
  String location,
  String navRoute, {
  required bool advancedTime,
}) {
  if (navRoute == '/board') {
    return location.startsWith('/board') || location.startsWith('/boards/');
  }
  if (navRoute == '/projects') {
    return location.startsWith('/projects');
  }
  if (navRoute == '/teams') {
    return location.startsWith('/teams');
  }
  // `/timesheet` starts with `/time`, so a plain prefix test cannot tell these
  // two entries apart — and which of them owns the other is exactly what the
  // flag decides. With the module on, the timesheet is one of its pages and
  // keeps the module's entry lit; with it off there is no module at all, and a
  // stray `/time` belongs to no entry rather than lighting up the timesheet.
  if (navRoute == '/time') {
    return advancedTime &&
        (location == '/time' ||
            location.startsWith('/time/') ||
            location == '/timesheet');
  }
  if (navRoute == '/timesheet') {
    return !advancedTime && location == '/timesheet';
  }
  return location.startsWith(navRoute);
}

/// Fallback title key for a sub-page route, or null when [location] is a
/// primary nav destination (dashboard, projects, issues, board, …).
///
/// A "sub-page" shows a back button and its own title instead of the brand mark.
/// The key here is only the fallback; pages with a dynamic title (an issue, an
/// article, a board) override it through `PageChrome`.
String? subPageTitleKey(String location, {required bool advancedTime}) {
  if (location == '/admin') return 'admin.title';
  if (location.startsWith('/admin/users')) return 'admin.users';
  if (location == '/notifications') return 'nav.notifications';
  if (location == '/weekly-summary') return 'weeklySummary.title';
  if (location == '/settings') return 'nav.settings';
  // The two ends of the flag. With the module on, the plain timesheet is one of
  // its pages: it loses its own nav entry and needs a title plus a way back to
  // the module. With the module off, `/time` is a route that leads nowhere, and
  // a bar that says so beats an empty page under the brand mark.
  if (location == '/timesheet') return advancedTime ? 'nav.timesheet' : null;
  if (location == '/time') return advancedTime ? null : 'notFound.title';
  if (location.startsWith('/issues/')) return 'nav.issues';
  if (location.startsWith('/knowledge/')) return 'nav.knowledge';
  if (location.startsWith('/boards/')) return 'nav.board';
  if (location.startsWith('/projects/')) return 'board.boards';
  if (location.startsWith('/teams/')) return 'nav.teams';
  return null;
}

/// Parent route to fall back to when a sub-page cannot simply pop — opened by a
/// deep link, with nothing on the navigation stack behind it.
String subPageBackRoute(String location, {required bool advancedTime}) {
  if (location.startsWith('/admin/users')) return '/admin';
  if (location == '/admin') return '/settings';
  // Only while the module exists; without it there is nowhere else to be.
  if (location == '/timesheet' && advancedTime) return '/time';
  if (location.startsWith('/issues/')) return '/issues';
  if (location.startsWith('/knowledge/')) return '/knowledge';
  if (location.startsWith('/boards/')) return '/board';
  if (location.startsWith('/projects/')) return '/projects';
  if (location.startsWith('/teams/')) return '/teams';
  return '/dashboard';
}
