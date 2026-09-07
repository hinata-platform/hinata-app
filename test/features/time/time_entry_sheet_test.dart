import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/time_entry_sheet.dart';

/// The editor decides what reaches the server. Two things matter here and
/// nothing else does: that a draft which cannot be an entry is refused before a
/// request is made, and that the two modes send the shape they claim to — a
/// duration or an interval, never both, because the server would then have to
/// pick a winner.
void main() {
  late _FakeTimeRepository repository;

  setUp(() => repository = _FakeTimeRepository());

  Future<void> open(
    WidgetTester tester, {
    WorkItem? entry,
    Size size = const Size(900, 1200),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<TimeRepository>.value(value: repository),
          RepositoryProvider<ProjectRepository>.value(
            value: _FakeProjectRepository(),
          ),
          RepositoryProvider<IssueRepository>.value(
            value: _FakeIssueRepository(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showTimeEntrySheet(context, entry: entry),
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
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();
  }

  testWidgets('a new entry opens in duration mode and sends a duration', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '1h 30m · 90m · 1:30'),
      '2h 15m',
    );
    await save(tester);

    expect(repository.created, hasLength(1));
    final draft = repository.created.single;
    expect(draft.durationMinutes, 135);
    expect(draft.date, isNotNull);
    // Never both: an interval alongside a duration would leave the server to
    // decide which one the entry is.
    expect(draft.startedAt, isNull);
    expect(draft.endedAt, isNull);
  });

  testWidgets(
    'a duration that is not a duration is refused before the request',
    (tester) async {
      await open(tester);

      await tester.enterText(
        find.widgetWithText(TextField, '1h 30m · 90m · 1:30'),
        'about an hour',
      );
      await save(tester);

      expect(repository.created, isEmpty);
      expect(find.text('time.error.duration'), findsOneWidget);
    },
  );

  testWidgets('more than a day is refused with its own reason', (tester) async {
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '1h 30m · 90m · 1:30'),
      '25h',
    );
    await save(tester);

    expect(repository.created, isEmpty);
    expect(find.text('time.error.tooLong'), findsOneWidget);
  });

  testWidgets('switching to start-and-end sends the interval and no duration', (
    tester,
  ) async {
    await open(tester);

    await tester.tap(find.text('time.entry.modeInterval'));
    await tester.pumpAndSettle();
    await save(tester);

    expect(repository.created, hasLength(1));
    final draft = repository.created.single;
    expect(draft.startedAt, isNotNull);
    expect(draft.endedAt, isNotNull);
    expect(draft.durationMinutes, isNull);
    // The day comes from the start, so sending one as well would be a second
    // opinion about the same fact.
    expect(draft.date, isNull);
  });

  testWidgets('an existing interval entry opens in interval mode', (
    tester,
  ) async {
    final start = DateTime.now().subtract(const Duration(hours: 3));
    await open(
      tester,
      entry: WorkItem(
        id: 'w1',
        durationMinutes: 60,
        activityType: 'Development',
        description: 'from a timer',
        date: DateTime.now(),
        startedAt: start,
        endedAt: start.add(const Duration(hours: 1)),
      ),
    );

    // The mode a stopped timer left is the mode it is corrected in.
    expect(find.text('time.entry.start'), findsOneWidget);
    expect(find.text('time.entry.end'), findsOneWidget);
    expect(find.text('from a timer'), findsOneWidget);
  });

  testWidgets('editing an entry does not strip the tags it is not editing', (
    tester,
  ) async {
    // The server reads a present tag list as an instruction and an empty one as
    // "remove them all". This form does not edit tags, so it must not mention
    // them — sending the default empty list wiped the tags off every entry that
    // was edited, silently, for the one field nothing on screen shows you
    // losing.
    await open(
      tester,
      entry: WorkItem(
        id: 'w1',
        durationMinutes: 60,
        activityType: 'Development',
        description: 'from a timer',
        date: DateTime.now(),
        tags: const ['focus', 'deep work'],
      ),
    );

    await save(tester);

    expect(
      repository.updated.single.$2.toPatchJson().containsKey('tags'),
      isFalse,
    );
  });

  testWidgets(
    'the placement field is not offered on an entry that cannot move',
    (tester) async {
      // PATCH /time/entries/{id} carries no project or issue. A field shown here
      // would close the sheet, report success and change nothing.
      await open(
        tester,
        entry: WorkItem(
          id: 'w1',
          durationMinutes: 60,
          activityType: 'Development',
          date: DateTime.now(),
        ),
      );

      expect(find.text('time.entry.placement'), findsNothing);
      await save(tester);
      expect(repository.updated.single.$2.projectId, isNull);
      expect(repository.updated.single.$2.issueId, isNull);
    },
  );

  testWidgets('a new entry still offers it', (tester) async {
    await open(tester);

    expect(find.text('time.entry.placement'), findsOneWidget);
  });

  testWidgets('an existing duration entry opens in duration mode and updates', (
    tester,
  ) async {
    await open(
      tester,
      entry: WorkItem(
        id: 'w1',
        durationMinutes: 45,
        activityType: 'Testing',
        description: 'read the spec',
        date: DateTime.now(),
      ),
    );

    // The field is primed with what the entry says, in the notation it accepts.
    expect(find.widgetWithText(TextField, '45m'), findsOneWidget);

    await save(tester);

    expect(repository.created, isEmpty);
    expect(repository.updated, hasLength(1));
    expect(repository.updated.single.$1, 'w1');
    expect(repository.updated.single.$2.durationMinutes, 45);
  });
}

class _FakeTimeRepository implements TimeRepository {
  final List<TimeEntryDraft> created = [];
  final List<(String, TimeEntryDraft)> updated = [];

  SavedTimeEntry _saved() => const SavedTimeEntry(
    entry: WorkItem(id: 'w1', durationMinutes: 60, activityType: 'Development'),
  );

  @override
  Future<SavedTimeEntry> create(TimeEntryDraft draft) async {
    created.add(draft);
    return _saved();
  }

  @override
  Future<SavedTimeEntry> update(String id, TimeEntryDraft draft) async {
    updated.add((id, draft));
    return _saved();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> resolveProjects(List<String> ids) async => const [];

  @override
  Future<({List<Project> projects, int total})> searchProjects({
    String? query,
    int page = 0,
    int size = 25,
    bool archived = false,
  }) async => (projects: const <Project>[], total: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeIssueRepository implements IssueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
