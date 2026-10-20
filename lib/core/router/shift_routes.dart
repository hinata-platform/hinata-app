import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/shell/not_found_screen.dart';
import '../../features/shell/shell_nav.dart' show shiftsRoute;
import '../../features/shifts/view/shifts_screen.dart';
import 'board_routes.dart' show RoutePage;

/// The shift planning module's routes (HIN-27): the three views and one event.
///
/// They exist for the client only while `shift_planning` is on. The gate sits
/// in the page builder rather than in the route table, as it does for the
/// time module: go_router fixes the table at construction while the flag is a
/// runtime value an admin can flip mid-session, and the router's
/// refreshListenable already carries AppConfig. With the flag off a deep link
/// lands on the shell's not-found page, so the chrome around it stays right
/// and nothing on the page asks the server for a route that would answer 404.
///
/// Kept apart from the main route table so the module stays one folder plus
/// this file, and can leave again the same way.
List<RouteBase> shiftRoutes(
  RoutePage page, {
  required bool Function() enabled,
}) => [
  GoRoute(
    path: shiftsRoute,
    pageBuilder: (_, state) => page(state, shiftsPage(enabled: enabled())),
  ),
  GoRoute(
    path: '$shiftsRoute/calendar',
    pageBuilder: (_, state) =>
        page(state, shiftsPage(enabled: enabled(), view: ShiftsView.calendar)),
  ),
  GoRoute(
    path: '$shiftsRoute/events',
    pageBuilder: (_, state) =>
        page(state, shiftsPage(enabled: enabled(), view: ShiftsView.events)),
  ),
  GoRoute(
    path: '$shiftsRoute/events/:id',
    pageBuilder: (_, state) => page(
      state,
      shiftsPage(
        enabled: enabled(),
        view: ShiftsView.events,
        eventId: state.pathParameters['id'],
      ),
    ),
  ),
];

/// The page behind a shifts route, for a server whose shift planning is
/// ([enabled]) or is not switched on.
///
/// Named for the same reason as `timeModulePage`: the second branch is the
/// point of the gate, and `standalone: false` keeps the not-found page inside
/// the shell, where the back button and the title come from.
@visibleForTesting
Widget shiftsPage({
  required bool enabled,
  ShiftsView view = ShiftsView.mine,
  String? eventId,
}) {
  if (!enabled) return const NotFoundScreen(standalone: false);
  return ShiftsScreen(
    // Keyed by the event, so going from one event to another does not keep
    // the first one's state under the second one's address.
    key: eventId == null ? null : ValueKey('shift-event-$eventId'),
    view: view,
    eventId: eventId,
  );
}
