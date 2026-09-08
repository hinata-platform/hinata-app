import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/features/time/time_views.dart';

/// The menu under the app bar's title — where a phone keeps the switching that
/// a wide window shows as chips.
///
/// The rows render as i18n *keys* here, which is fine: what this is about is
/// which route it goes to and what it hands back, not what the words say.
void main() {
  const spans = {'week': 'time.calendar.week', 'month': 'time.calendar.month'};

  late List<String> visited;
  Object? answered;
  late Rect? anchor;

  setUp(() {
    visited = [];
    answered = null;
    anchor = const Rect.fromLTWH(20, 60, 90, 22);
  });

  Widget host(TimeView current) {
    Widget page(BuildContext context, String route) {
      visited.add(route);
      return Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                answered = await showTimeViewMenu<String>(
                  context,
                  anchor: anchor,
                  current: current,
                  extras: [
                    for (final entry in spans.entries)
                      TimeMenuExtra(
                        value: entry.key,
                        label: entry.value,
                        icon: Icons.calendar_today,
                        selected: entry.key == 'week',
                        first: entry.key == 'week',
                      ),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
    }

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: GoRouter(
        routes: [
          for (final view in TimeView.values)
            GoRoute(
              path: view.route,
              builder: (context, _) => page(context, view.route),
            ),
        ],
        initialLocation: current.route,
      ),
    );
  }

  testWidgets('it offers the three views and the page\'s own rows', (
    tester,
  ) async {
    await tester.pumpWidget(host(TimeView.calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    for (final view in TimeView.values) {
      expect(find.text(view.labelKey), findsOneWidget);
    }
    expect(find.text('time.calendar.week'), findsOneWidget);
    expect(find.text('time.calendar.month'), findsOneWidget);
  });

  testWidgets('picking the view you are on navigates nowhere', (tester) async {
    // Going anyway would rebuild the page and throw away the month it is
    // showing — and the calendar's month is state the router knows nothing
    // about.
    await tester.pumpWidget(host(TimeView.calendar));
    await tester.pumpAndSettle();
    final before = visited.length;

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.view.calendar'));
    await tester.pumpAndSettle();

    expect(visited.length, before);
    expect(answered, isNull);
  });

  testWidgets('picking another view goes to it, and answers nothing', (
    tester,
  ) async {
    await tester.pumpWidget(host(TimeView.calendar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.view.timesheet'));
    await tester.pumpAndSettle();

    expect(visited.last, TimeView.timesheet.route);
    expect(answered, isNull, reason: 'the menu did the navigating itself');
  });

  testWidgets('one of the page\'s own rows comes straight back, typed', (
    tester,
  ) async {
    await tester.pumpWidget(host(TimeView.calendar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('time.calendar.month'));
    await tester.pumpAndSettle();

    expect(answered, 'month');
  });

  testWidgets('with nothing to anchor to, nothing opens', (tester) async {
    // Null means the title is not on screen to measure. A popover pinned to the
    // top-left corner of the display is not a better answer than none.
    anchor = null;
    await tester.pumpWidget(host(TimeView.calendar));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('time.view.timesheet'), findsNothing);
    expect(answered, isNull);
  });
}
