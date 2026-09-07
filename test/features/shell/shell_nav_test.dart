import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/shell/shell_nav.dart';

/// The five answers the shell gives about a location — which entries exist,
/// which one is lit, whether the page is a sub-page, what it is called and where
/// its back button leads — now depend on a platform flag, and they have to agree
/// with each other in *both* of its states.
///
/// The failure this guards against is not a crash. Miss one of the five and you
/// get an entry that highlights nothing, or a sub-page bar with no title: both
/// render perfectly, on one layout, on one route, for one value of the flag.
///
/// The collision is the sharp edge. `/timesheet` starts with `/time`, so the
/// prefix test the shell uses everywhere else answers "yes" to the wrong
/// question in both directions.
void main() {
  group('with the module off — nothing moves', () {
    const off = false;

    test('the timesheet keeps its entry, and there is no time entry', () {
      final routes = secondaryDestinations(
        advancedTime: off,
      ).map((d) => d.route);
      expect(routes, contains('/timesheet'));
      expect(routes, isNot(contains('/time')));
    });

    test('the More sheet shows the same entry', () {
      final routes = moreSheetDestinations(
        advancedTime: off,
      ).map((d) => d.route);
      expect(routes, contains('/timesheet'));
      expect(routes, isNot(contains('/time')));
    });

    test('it is still called "Stundenzettel"', () {
      expect(timeDestination(advancedTime: off).labelKey, 'nav.timesheet');
    });

    test('the timesheet entry lights up on the timesheet', () {
      expect(isNavActive('/timesheet', '/timesheet', advancedTime: off), isTrue);
    });

    test('the timesheet is a top-level page, not a sub-page', () {
      expect(subPageTitleKey('/timesheet', advancedTime: off), isNull);
    });

    test('a deep link to /time says so, and offers a way out', () {
      // The route exists (the flag can be switched on at any moment), so it
      // renders inside the shell — which then owes it a title and a back route
      // rather than a blank page under the brand mark.
      expect(subPageTitleKey('/time', advancedTime: off), 'notFound.title');
      expect(subPageBackRoute('/time', advancedTime: off), '/dashboard');
    });

    test('and it lights up no entry at all', () {
      for (final destination in secondaryDestinations(advancedTime: off)) {
        expect(
          isNavActive('/time', destination.route, advancedTime: off),
          isFalse,
          reason: destination.route,
        );
      }
    });
  });

  group('with the module on — one entry becomes the module', () {
    const on = true;

    test('the entry is /time and the timesheet is no longer one', () {
      final routes = secondaryDestinations(
        advancedTime: on,
      ).map((d) => d.route);
      expect(routes, contains('/time'));
      expect(routes, isNot(contains('/timesheet')));
    });

    test('the More sheet follows', () {
      final routes = moreSheetDestinations(advancedTime: on).map((d) => d.route);
      expect(routes, contains('/time'));
      expect(routes, isNot(contains('/timesheet')));
    });

    test('and it is called "Zeit"', () {
      expect(timeDestination(advancedTime: on).labelKey, 'nav.time');
    });

    test('it keeps its place in the list', () {
      // Same slot in both states — the entry changes name, not position.
      int slot(bool flag) => secondaryDestinations(
        advancedTime: flag,
      ).indexWhere((d) => d.route == timeDestination(advancedTime: flag).route);
      expect(slot(on), slot(!on));
    });

    test('the module entry lights up on its own pages', () {
      expect(isNavActive('/time', '/time', advancedTime: on), isTrue);
      expect(isNavActive('/time/entries', '/time', advancedTime: on), isTrue);
    });

    test('and stays lit on the timesheet, which is now one of them', () {
      expect(isNavActive('/timesheet', '/time', advancedTime: on), isTrue);
    });

    test('the timesheet becomes a sub-page of the module', () {
      expect(subPageTitleKey('/timesheet', advancedTime: on), 'nav.timesheet');
      expect(subPageBackRoute('/timesheet', advancedTime: on), '/time');
    });

    test('the module itself is a top-level page', () {
      expect(subPageTitleKey('/time', advancedTime: on), isNull);
    });
  });

  group('the /time — /timesheet prefix collision', () {
    test('the timesheet never lights up the module entry by accident', () {
      // The bug a plain `startsWith` produces: with the module off there is no
      // module, so nothing may claim /timesheet on its behalf.
      expect(isNavActive('/timesheet', '/time', advancedTime: false), isFalse);
    });

    test('and /time never lights up the timesheet entry', () {
      expect(isNavActive('/time', '/timesheet', advancedTime: false), isFalse);
      expect(isNavActive('/time', '/timesheet', advancedTime: true), isFalse);
    });

    test('no other route is caught by either', () {
      for (final location in const ['/timeline', '/timers', '/timezone']) {
        expect(isNavActive(location, '/time', advancedTime: true), isFalse);
        expect(isNavActive(location, '/timesheet', advancedTime: false), isFalse);
      }
    });
  });

  group('everything else is unchanged by the flag', () {
    for (final advancedTime in const [false, true]) {
      test('with the flag ${advancedTime ? 'on' : 'off'}', () {
        expect(isNavActive('/boards/abc', '/board', advancedTime: advancedTime), isTrue);
        expect(
          isNavActive('/projects/p1/boards', '/projects', advancedTime: advancedTime),
          isTrue,
        );
        expect(subPageTitleKey('/admin', advancedTime: advancedTime), 'admin.title');
        expect(subPageTitleKey('/dashboard', advancedTime: advancedTime), isNull);
        expect(subPageBackRoute('/issues/HIN-1', advancedTime: advancedTime), '/issues');
        expect(subPageBackRoute('/nowhere', advancedTime: advancedTime), '/dashboard');
      });
    }

    test('the primary destinations and bottom tabs never move', () {
      expect(primaryDestinations.map((d) => d.route), [
        '/dashboard',
        '/teams',
        '/projects',
        '/issues',
        '/board',
      ]);
      expect(bottomTabs.map((d) => d.route), [
        '/dashboard',
        '/issues',
        '/board',
        '/more',
      ]);
    });
  });
}
