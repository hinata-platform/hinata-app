import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/availability_models.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/time_privacy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/availability_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/time_screen_cubit.dart';

import 'recording_repository.dart';

/// The time list reads its entries, hints, markings and labels, and removes an
/// entry, through this cubit: each call reaches the repository as asked and
/// comes back as it answered.
void main() {
  const entry = WorkItem(id: 'e1', durationMinutes: 30, activityType: 'WORK');
  const alpha = Project(id: 'p1', key: 'ALP', name: 'Alpha');
  final from = DateTime(2026, 9, 1);
  final to = DateTime(2026, 9, 30);

  late _FakeTime time;
  late _FakeAvailability availability;
  late _FakeProjects projects;
  late TimeScreenCubit cubit;

  setUp(() {
    time = _FakeTime();
    availability = _FakeAvailability();
    projects = _FakeProjects();
    cubit = TimeScreenCubit(time, availability, projects);
    addTearDown(cubit.close);
  });

  test('reads a page of entries with the filter', () async {
    time.answers[#entries] = Future.value((items: [entry], total: 1));
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
    time.answers[#hints] = Future.value([hint]);
    availability.answers[#capacity] = Future.value(capacity);

    expect(await cubit.hints(from, to), [hint]);
    expect(await cubit.capacity(from, to), capacity);
    expect(time.calls.single, invoked(#hints, positional: [from, to]));
    expect(
      availability.calls.single,
      invoked(#capacity, positional: [from, to]),
    );
  });

  test('names the projects and removes the entry asked about', () async {
    projects.answers[#resolveProjects] = Future.value([alpha]);
    time.answers[#delete] = Future<void>.value();

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

  test('passes a refusal through', () async {
    time.failure = refusal;
    availability.failure = refusal;
    projects.failure = refusal;

    await expectLater(
      () => cubit.entries(filter: const TimeEntryFilter(), page: 0, size: 50),
      throwsRefusal,
    );
    await expectLater(() => cubit.hints(from, to), throwsRefusal);
    await expectLater(() => cubit.capacity(from, to), throwsRefusal);
    await expectLater(() => cubit.resolveProjects(['p1']), throwsRefusal);
    await expectLater(() => cubit.delete('e1'), throwsRefusal);
  });
}

class _FakeTime with RecordingRepository implements TimeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeAvailability
    with RecordingRepository
    implements AvailabilityRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}

class _FakeProjects with RecordingRepository implements ProjectRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => record(invocation);
}
