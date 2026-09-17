import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/core/blocs/app_config_bloc.dart';
import 'package:hinata/features/account/availability_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../absences/absence_test_support.dart';

/// Settings → Working hours and absences (HIN-91): the pattern editor and the
/// list of absences, empty and filled.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(WidgetTester tester, _FakeAvailability repository) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1200, 1400)),
        child: MaterialApp(
          home: Scaffold(
            // The section now carries the absence balances at the top, and
            // those ask the server metadata whether the module exists. Off
            // here, so this test keeps testing the hours and the absences.
            body: BlocProvider<AppConfigBloc>.value(
              value: FakeAppConfig(absenceManagement: false),
              child: RepositoryProvider<AvailabilityRepository>.value(
                value: repository,
                child: const SingleChildScrollView(
                  child: AvailabilitySection(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ButtonStyleButton saveButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('availability.pattern.save'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );

  testWidgets('without hours of their own a person sees the default, and '
      'there is nothing to save yet', (tester) async {
    await pump(tester, _FakeAvailability());

    expect(find.text('availability.pattern.usingDefault'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);
  });

  testWidgets('a step on a weekday is saved as seven days, Monday first', (
    tester,
  ) async {
    final repository = _FakeAvailability();
    await pump(tester, repository);

    // The first plus is Monday's: the pattern comes before the absences.
    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('availability.pattern.save'));
    await tester.pump();
    // Past the toast, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 6));

    expect(repository.saved, [510, 480, 480, 480, 480, 0, 0]);
  });

  testWidgets('no absences is a sentence, not a blank', (tester) async {
    await pump(tester, _FakeAvailability());

    expect(find.text('availability.timeOff.empty'), findsOneWidget);
    expect(find.text('availability.timeOff.emptyMessage'), findsOneWidget);
  });

  testWidgets('an absence shows its type and its note', (tester) async {
    await pump(
      tester,
      _FakeAvailability(
        absences: [
          TimeOff(
            id: 'a1',
            userId: 'me',
            type: TimeOffType.vacation,
            from: DateTime(2026, 12, 21),
            to: DateTime(2026, 12, 23),
            note: 'Familie',
          ),
        ],
      ),
    );

    expect(find.text('availability.timeOff.empty'), findsNothing);
    expect(find.text('availability.type.vacation'), findsOneWidget);
    expect(find.text('Familie'), findsOneWidget);
  });
}

class _FakeAvailability implements AvailabilityRepository {
  _FakeAvailability({this.absences = const []});

  final List<TimeOff> absences;

  /// The minutes of the last pattern saved.
  List<int>? saved;

  @override
  Future<WorkingSchedule> schedule() async => const WorkingSchedule(
    userId: 'me',
    defaultMinutesPerWeekday: [480, 480, 480, 480, 480, 0, 0],
  );

  @override
  Future<PageResult<HolidayCalendar>> calendars({
    int page = 0,
    int size = 50,
  }) async => (
    items: const [
      HolidayCalendar(id: 'de', name: 'Deutschland', defaultCalendar: true),
    ],
    total: 1,
  );

  @override
  Future<PageResult<TimeOff>> timeOff({
    DateTime? from,
    int page = 0,
    int size = 50,
  }) async => (items: absences, total: absences.length);

  @override
  Future<WorkingPattern?> saveSchedule({
    DateTime? validFrom,
    required List<int> minutesPerWeekday,
    String? holidayCalendarId,
  }) async {
    saved = minutesPerWeekday;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
