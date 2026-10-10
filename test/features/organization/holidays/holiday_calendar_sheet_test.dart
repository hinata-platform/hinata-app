import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/features/organization/holidays/holiday_calendar_sheet.dart';
import 'package:hinata/features/organization/holidays/org_holidays_cubit.dart';

/// The calendar form sends what the chosen source means: switching away from
/// a feed or from rules removes it, and a region is needed to follow one.
void main() {
  Future<_FakeAvailability> open(
    WidgetTester tester,
    HolidayCalendar existing,
  ) async {
    final availability = _FakeAvailability();
    // Above the app, as in the app: the form opens on the root navigator.
    await tester.pumpWidget(
      RepositoryProvider<AvailabilityRepository>.value(
        value: availability,
        child: BlocProvider(
          create: (_) => OrgHolidaysCubit(availability),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showHolidayCalendarSheet(context, existing: existing),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return availability;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('common.save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('a feed calendar kept by hand drops its address', (tester) async {
    final availability = await open(
      tester,
      const HolidayCalendar(
        id: 'c',
        name: 'Feed',
        hasFeed: true,
        feedHost: 'calendar.google.com',
      ),
    );

    await tester.tap(find.text('availability.admin.sourceByHand'));
    await tester.pump();
    await save(tester);

    expect(availability.updates, ['icsUrl: rules:null']);
  });

  testWidgets('a calendar with rules kept by hand drops its rules', (
    tester,
  ) async {
    final availability = await open(
      tester,
      const HolidayCalendar(
        id: 'c',
        name: 'Bayern',
        hasFeed: false,
        rules: 'DE-BY',
        rulesName: 'Bayern, Deutschland',
      ),
    );

    await tester.tap(find.text('availability.admin.sourceByHand'));
    await tester.pump();
    await save(tester);

    expect(availability.updates, ['icsUrl:null rules:']);
  });

  testWidgets('following a region needs one', (tester) async {
    final availability = await open(
      tester,
      const HolidayCalendar(id: 'c', name: 'Hand', hasFeed: false),
    );

    await tester.tap(find.text('availability.admin.sourceRules'));
    await tester.pump();
    await save(tester);

    expect(availability.updates, isEmpty);
  });
}

class _FakeAvailability implements AvailabilityRepository {
  final updates = <String>[];

  @override
  Future<List<HolidayRegion>> regions(String languageCode) async => const [
    HolidayRegion(
      code: 'DE',
      name: 'Deutschland',
      subdivisions: [HolidayRegion(code: 'DE-BY', name: 'Bayern')],
    ),
  ];

  @override
  Future<HolidayCalendar> updateCalendar(
    String id, {
    String? name,
    String? region,
    String? icsUrl,
    String? rules,
    bool? defaultCalendar,
  }) async {
    updates.add('icsUrl:$icsUrl rules:$rules');
    return HolidayCalendar(id: id, name: name ?? '');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
