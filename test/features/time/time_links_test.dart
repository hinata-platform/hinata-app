import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/router/app_router.dart' show timeModulePage;
import 'package:hinata/features/time/time_module_screen.dart';
import 'package:hinata/features/time/time_views.dart';

/// HIN-165: search hits link into the time module with a query — a day, an
/// entry, a project, a request, a type. The route hands the whole query to the
/// module, which gives each view what it reads; the views' own tests check what
/// they do with it.
void main() {
  group('the day a link names', () {
    test('is a local midnight', () {
      expect(linkDay('2026-10-20'), DateTime(2026, 10, 20));
    });

    test('is nothing for anything that is not a day', () {
      expect(linkDay(null), isNull);
      expect(linkDay(''), isNull);
      expect(linkDay('2026-10-20T12:00:00Z'), isNull);
      expect(linkDay('20.10.2026'), isNull);
      expect(linkDay('tomorrow'), isNull);
    });
  });

  test('the module page carries the query to its views', () {
    final page = timeModulePage(
      advancedTime: true,
      view: TimeView.calendar,
      query: const {'date': '2026-10-20', 'entry': 'w1'},
    );

    expect(page, isA<TimeModuleScreen>());
    final module = page as TimeModuleScreen;
    expect(module.view, TimeView.calendar);
    expect(module.query, {'date': '2026-10-20', 'entry': 'w1'});
  });
}
