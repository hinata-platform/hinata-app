import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/router/app_router.dart'
    show timeFocusPage, timeModulePage;
import 'package:hinata/features/time/time_focus_screen.dart';
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/shell/not_found_screen.dart';
import 'package:hinata/features/time/time_module_screen.dart';
import 'package:hinata/features/time/time_views.dart';

/// A link that leads nowhere used to render an empty page under the brand mark,
/// which reads as a broken app. It now says what happened and offers the way
/// home — in two hosts: standalone for a path that matched no route at all, and
/// embedded for a route that exists but whose module this server does not offer.
///
/// Nothing here asserts on translated copy: widget tests render raw i18n keys.
void main() {
  Widget host(Widget child, {double width = 400}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  testWidgets('says what happened and offers a way out', (tester) async {
    await tester.pumpWidget(host(const NotFoundScreen(standalone: false)));
    await tester.pumpAndSettle();

    expect(find.byType(HiveEmptyState), findsOneWidget);
    expect(find.text('notFound.title'), findsOneWidget);
    expect(find.text('notFound.message'), findsOneWidget);
    expect(find.text('notFound.home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded, it brings no canvas of its own', (tester) async {
    // The shell already paints the canvas around it; a second Scaffold there
    // would stack another background over the ambient one.
    await tester.pumpWidget(host(const NotFoundScreen(standalone: false)));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(NotFoundScreen),
        matching: find.byType(Scaffold),
      ),
      findsNothing,
    );
  });

  testWidgets('standalone, it paints its own', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: NotFoundScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(NotFoundScreen),
        matching: find.byType(Scaffold),
      ),
      findsOneWidget,
    );
  });

  for (final width in <double>[320, 900]) {
    testWidgets('lays out without overflow at ${width}px', (tester) async {
      await tester.pumpWidget(
        host(const NotFoundScreen(standalone: false), width: width),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the way out goes home', (tester) async {
    final router = GoRouter(
      initialLocation: '/nowhere',
      routes: [
        GoRoute(path: '/nowhere', builder: (_, _) => const NotFoundScreen()),
        GoRoute(path: '/dashboard', builder: (_, _) => const Text('dashboard')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('notFound.home'));
    await tester.pumpAndSettle();

    expect(find.text('dashboard'), findsOneWidget);
  });

  group('the /time gate', () {
    test('with the module off, a deep link lands on not-found', () {
      final page = timeModulePage(advancedTime: false);
      expect(page, isA<NotFoundScreen>());
      // Embedded: the shell around it supplies the back button and the title.
      expect((page as NotFoundScreen).standalone, isFalse);
    });

    test('the focus route is gated too, and stands on its own', () {
      final off = timeFocusPage(advancedTime: false);
      expect(off, isA<NotFoundScreen>());
      // Standalone, unlike the module's other routes: the focus view is a
      // top-level route outside the shell, so there is no shell around the
      // not-found page either and it has to carry its own way home.
      expect((off as NotFoundScreen).standalone, isTrue);
      expect(timeFocusPage(advancedTime: true), isA<TimeFocusScreen>());
    });

    test('with the module on, it is the module', () {
      // Stage 3 replaced the placeholder: `/time` is now the module's own
      // list, and the timesheet keeps its own route underneath it.
      final page = timeModulePage(advancedTime: true);
      expect(page, isA<TimeModuleScreen>());
      expect((page as TimeModuleScreen).view, TimeView.list);
    });

    test('every route names its view on the one module page', () {
      // One page for all of them, carrying the view its address names: the
      // module keeps the views it has already built, so switching between
      // them no longer tears one down and reads the next back.
      for (final view in TimeView.values) {
        final page = timeModulePage(advancedTime: true, view: view);
        expect(page, isA<TimeModuleScreen>(), reason: view.route);
        expect((page as TimeModuleScreen).view, view, reason: view.route);
      }
      final absences = timeModulePage(
        advancedTime: true,
        view: TimeView.absences,
        scope: 'inbox',
      );
      expect((absences as TimeModuleScreen).scope, 'inbox');
    });

    test('with the module off, none of the three exists', () {
      for (final view in TimeView.values) {
        expect(
          timeModulePage(advancedTime: false, view: view),
          isA<NotFoundScreen>(),
          reason: view.route,
        );
      }
    });
  });
}
