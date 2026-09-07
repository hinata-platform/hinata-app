import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/router/app_router.dart' show timeModulePage;
import 'package:hinata/core/widgets/hive_empty_state.dart';
import 'package:hinata/features/shell/not_found_screen.dart';
import 'package:hinata/features/time/time_screen.dart';

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

    test('with the module on, it is the module', () {
      // Stage 3 replaced the placeholder: `/time` is now the module's own
      // list, and the timesheet keeps its own route underneath it.
      expect(timeModulePage(advancedTime: true), isA<TimeScreen>());
    });
  });
}
