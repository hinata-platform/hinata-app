import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/auth_bloc.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/shift_repository.dart';
import 'package:hinata/features/shifts/bloc/my_shifts_snapshot_cubit.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:hinata/core/router/shift_routes.dart';
import 'package:hinata/features/shell/not_found_screen.dart';
import 'package:hinata/features/shifts/view/shifts_screen.dart';

import '../../features/shifts/shift_fakes.dart';
import '../../support/timer_surface_fakes.dart' show MemoryStorage;

/// HIN-49: the shift planning routes exist for the client only while
/// `shift_planning` is on. With it off a deep link lands on the not-found page
/// *inside* the shell, and switching the flag swaps the page without a restart.
///
/// The router here is the module's own route list under a stand-in shell, the
/// way the real router mounts it; the shell is a marker so the test can see the
/// page sits inside it. The repository is a recording fake: with the flag off
/// it must never be asked, which is what "no request to a gated prefix" means.
void main() {
  late GoRouter router;
  late ValueNotifier<bool> flag;
  late FakeShiftRepository repo;

  setUp(() {
    HydratedBloc.storage = MemoryStorage();
    repo = FakeShiftRepository();
  });

  Future<void> pumpAt(
    WidgetTester tester,
    String location, {
    bool enabled = false,
  }) async {
    flag = ValueNotifier(enabled);
    addTearDown(flag.dispose);
    router = GoRouter(
      initialLocation: location,
      refreshListenable: flag,
      routes: [
        ShellRoute(
          builder: (_, _, child) =>
              KeyedSubtree(key: const ValueKey('shell'), child: child),
          routes: shiftRoutes(
            (state, child) =>
                NoTransitionPage<void>(key: state.pageKey, child: child),
            enabled: () => flag.value,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    final snapshot = MyShiftsSnapshotCubit(storageId: 'shifts#routes');
    addTearDown(snapshot.close);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ShiftRepository>.value(value: repo),
          RepositoryProvider<ProjectRepository>.value(value: _NoProjects()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>(create: (_) => FakeAuthBloc()),
            BlocProvider<MyShiftsSnapshotCubit>.value(value: snapshot),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await _settle(tester);
  }

  Finder inShell(Finder finder) => find.descendant(
    of: find.byKey(const ValueKey('shell')),
    matching: finder,
  );

  for (final location in const [
    '/shifts',
    '/shifts/calendar',
    '/shifts/events',
    '/shifts/events/e1',
  ]) {
    testWidgets('flag off: a deep link to $location is the shell not-found', (
      tester,
    ) async {
      await pumpAt(tester, location);

      final notFound = inShell(find.byType(NotFoundScreen));
      expect(notFound, findsOneWidget);
      expect(tester.widget<NotFoundScreen>(notFound).standalone, isFalse);
      expect(find.byType(ShiftsScreen), findsNothing);
      expect(tester.takeException(), isNull);
      expect(repo.calls, isEmpty);
    });
  }

  testWidgets('the flag is read when the page is built, not at startup', (
    tester,
  ) async {
    // The route table is fixed when the router is made; the flag is not. An
    // admin switching the module on mid-session opens it on the next visit,
    // and switching it off closes it the same way, without a restart.
    await pumpAt(tester, '/shifts');
    expect(find.byType(NotFoundScreen), findsOneWidget);

    flag.value = true;
    router.go('/shifts/calendar');
    await _settle(tester);
    expect(inShell(find.byType(ShiftsScreen)), findsOneWidget);
    expect(find.byType(NotFoundScreen), findsNothing);

    flag.value = false;
    router.go('/shifts/events');
    await _settle(tester);
    expect(find.byType(NotFoundScreen), findsOneWidget);
    expect(find.byType(ShiftsScreen), findsNothing);
  });

  testWidgets('flag on: each address names its view', (tester) async {
    await pumpAt(tester, '/shifts/events/e0', enabled: true);

    for (final (location, view, eventId) in const [
      ('/shifts', ShiftsView.mine, null),
      ('/shifts/calendar', ShiftsView.calendar, null),
      ('/shifts/events', ShiftsView.events, null),
      ('/shifts/events/e1', ShiftsView.events, 'e1'),
    ]) {
      router.go(location);
      await _settle(tester);
      final screen = tester.widget<ShiftsScreen>(find.byType(ShiftsScreen));
      expect(screen.view, view, reason: location);
      expect(screen.eventId, eventId, reason: location);
    }
    // Each view read what it shows, and nothing else.
    expect(repo.calls, containsAll(['event:e0', 'myShifts:0', 'next']));
  });

  test('the gate itself, without a router', () {
    final off = shiftsPage(enabled: false);
    expect(off, isA<NotFoundScreen>());
    expect((off as NotFoundScreen).standalone, isFalse);
    expect(shiftsPage(enabled: true), isA<ShiftsScreen>());
  });
}

/// Pumps a few frames: the views draw a looping loader, so they never settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The calendar names a project only for an address narrowed to one; none of
/// these is.
class _NoProjects extends Fake implements ProjectRepository {}
