import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/features/organization/holidays/holidays_screen.dart';
import 'package:hinata/features/shell/page_chrome.dart';

/// Admin → Holidays (HIN-91): an instance without calendars, and a calendar
/// whose import is still running.
///
/// While a calendar imports the page reads the calendars again every two
/// seconds, so these tests pump frames instead of settling, and take the page
/// down before the next read is due.
void main() {
  Future<void> pump(WidgetTester tester, _FakeAvailability repository) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: PageChromeScope(
              controller: PageChromeController(),
              child: RepositoryProvider<AvailabilityRepository>.value(
                value: repository,
                child: const OrgHolidaysScreen(),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    );
    // The calendars, then the holidays of the first one.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('without calendars the page says so and offers the first one', (
    tester,
  ) async {
    await pump(tester, _FakeAvailability());

    expect(find.text('availability.admin.noCalendars'), findsOneWidget);
    expect(find.text('availability.admin.newCalendar'), findsOneWidget);
  });

  testWidgets('a calendar that is importing says so on its card', (
    tester,
  ) async {
    await pump(
      tester,
      _FakeAvailability(
        kept: const [
          HolidayCalendar(
            id: 'by',
            name: 'Bayern',
            hasFeed: true,
            feedHost: 'feiertage.example',
            importState: 'RUNNING',
          ),
        ],
      ),
    );

    expect(find.text('Bayern'), findsOneWidget);
    expect(find.text('availability.admin.importing'), findsOneWidget);

    // Gone before the next read is due, which takes its timer with it.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'a calendar that follows a region says so, and that the platform set it',
    (tester) async {
      await pump(
        tester,
        _FakeAvailability(
          kept: const [
            HolidayCalendar(
              id: 'de',
              name: 'Gesetzliche Feiertage',
              defaultCalendar: true,
              hasFeed: false,
              rules: 'DE-BY',
              rulesName: 'Bayern, Deutschland',
              platformDefault: true,
            ),
          ],
        ),
      );

      expect(find.text('availability.admin.rulesFrom'), findsOneWidget);
      expect(find.text('availability.admin.rulesAuto'), findsOneWidget);
      expect(find.text('availability.admin.platformBadge'), findsOneWidget);
      expect(find.byTooltip('availability.admin.refillYear'), findsOneWidget);
    },
  );
}

class _FakeAvailability implements AvailabilityRepository {
  _FakeAvailability({this.kept = const []});

  /// The calendars the instance keeps.
  final List<HolidayCalendar> kept;

  @override
  Future<PageResult<HolidayCalendar>> calendars({
    int page = 0,
    int size = 50,
  }) async => (items: kept, total: kept.length);

  @override
  Future<List<Holiday>> holidays(String calendarId, {int? year}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
