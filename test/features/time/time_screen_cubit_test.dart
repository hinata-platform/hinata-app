import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/time/time_screen_cubit.dart';

import '../../support/recording_fake.dart';

/// The time list reads its entries, hints, markings and labels, and removes an
/// entry, through this cubit: each call reaches the repository as asked and
/// comes back as it answered.
void main() {
  const entry = WorkItem(id: 'e1', durationMinutes: 30, activityType: 'WORK');
  const alpha = Project(id: 'p1', key: 'ALP', name: 'Alpha');
  final from = DateTime(2026, 9, 1);
  final to = DateTime(2026, 9, 30);

  late FakeTimeRepository time;
  late FakeAvailabilityRepository availability;
  late FakeProjectRepository projects;
  late TimeScreenCubit cubit;

  setUp(() {
    time = FakeTimeRepository();
    availability = FakeAvailabilityRepository();
    projects = FakeProjectRepository();
    cubit = TimeScreenCubit(time, availability, projects);
    addTearDown(cubit.close);
  });

  test('reads a page of entries with the filter', () async {
    time.answer(#entries, (items: [entry], total: 1));
    const filter = TimeEntryFilter(projectId: 'p1');

    final page = await cubit.entries(filter: filter, page: 1, size: 50);

    expect(page.items, [entry]);
    expect(
      time.calls.single,
      invoked(#entries, named: {#filter: filter, #page: 1, #size: 50}),
    );
  });

  test('reads the hints and markings of a window', () async {
    final hint = TimeHint(kind: 'LATE_ENTRY', date: from);
    final capacity = Capacity(from: from, to: to);
    time.answer(#hints, [hint]);
    availability.answer(#capacity, capacity);

    expect(await cubit.hints(from, to), [hint]);
    expect(await cubit.capacity(from, to), capacity);
    expect(time.calls.single, invoked(#hints, positional: [from, to]));
    expect(
      availability.calls.single,
      invoked(#capacity, positional: [from, to]),
    );
  });

  test('names the projects and removes the entry asked about', () async {
    projects.answer(#resolveProjects, [alpha]);
    time.answer<void>(#delete, null);

    expect(await cubit.resolveProjects(['p1']), [alpha]);
    await cubit.delete('e1');
    expect(
      projects.calls.single,
      invoked(
        #resolveProjects,
        positional: [
          ['p1'],
        ],
      ),
    );
    expect(time.calls.single, invoked(#delete, positional: ['e1']));
  });

  test('passes a failure through', () async {
    time.fail(#entries, failure);
    time.fail(#hints, failure);
    time.fail(#delete, failure);
    availability.fail(#capacity, failure);
    projects.fail(#resolveProjects, failure);

    await expectLater(
      () => cubit.entries(filter: const TimeEntryFilter(), page: 0, size: 50),
      throwsFailure,
    );
    await expectLater(() => cubit.hints(from, to), throwsFailure);
    await expectLater(() => cubit.capacity(from, to), throwsFailure);
    await expectLater(() => cubit.resolveProjects(['p1']), throwsFailure);
    await expectLater(() => cubit.delete('e1'), throwsFailure);
  });
}
