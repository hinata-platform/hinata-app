import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/account/availability_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Settings → Working hours (HIN-91): the pattern editor, and the way to the
/// absences, which live in the time module since HIN-117.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Future<void> pump(WidgetTester tester, _FakeAvailability repository) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(child: AvailabilitySection()),
          ),
        ),
        GoRoute(
          path: '/time/absences',
          builder: (_, _) => const Text('absences view'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: RepositoryProvider<AvailabilityRepository>.value(
          value: repository,
          child: MaterialApp.router(routerConfig: router),
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

    // The first plus is Monday's.
    await tester.tap(find.byIcon(LucideIcons.plus).first);
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('availability.pattern.save'));
    await tester.pump();
    // Past the toast, so no timer outlives the test.
    await tester.pump(const Duration(seconds: 6));

    expect(repository.saved, [510, 480, 480, 480, 480, 0, 0]);
  });

  testWidgets('the absences are one tap away, in the time module', (
    tester,
  ) async {
    await pump(tester, _FakeAvailability());

    await tester.ensureVisible(find.text('availability.timeOff.movedHint'));
    await tester.tap(find.text('availability.timeOff.movedHint'));
    await tester.pumpAndSettle();

    expect(find.text('absences view'), findsOneWidget);
  });
}

class _FakeAvailability implements AvailabilityRepository {
  _FakeAvailability();

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
