import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/features/time/time_entry_sheet.dart';

import 'fake_time_policy_cubit.dart';

/// The editor decides what reaches the server. Two things matter here and
/// nothing else does: that a draft which cannot be an entry is refused before a
/// request is made, and that the two modes send the shape they claim to — a
/// duration or an interval, never both, because the server would then have to
/// pick a winner.
void main() {
  late _FakeTimeRepository repository;

  setUp(() => repository = _FakeTimeRepository());

  var deletions = 0;

  Future<void> open(
    WidgetTester tester, {
    WorkItem? entry,
    Size size = const Size(900, 1200),
    TimePolicySnapshot policy = TimePolicySnapshot.none,
  }) async {
    deletions = 0;
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
        child: BlocProvider<TimePolicyCubit>.value(
          value: FakeTimePolicyCubit(policy, repository),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showTimeEntrySheet(
                      context,
                      entry: entry,
                      onDeleted: () => deletions++,
                    ),
                    child: const Text('open'),
                  ),
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
    // The reporting day too, and the start's own day.
    //
    // It used to be omitted, on the reading that the day comes from the start
    // and sending it as well would be a second opinion. That is true of a
    // create, which the server derives — and false of an edit, which leaves a
    // field the patch does not mention alone. Moving an entry's hours from the
    // 10th to the 20th therefore left it filed on the 10th, where the month and
    // the timesheet went on counting it while the hour canvas — which draws a
    // block where its hours are — showed it on neither day.
    final start = draft.startedAt!;
    expect(draft.date, DateTime(start.year, start.month, start.day));
  });

  testWidgets('moving an interval moves the day it is filed under with it', (
    tester,
  ) async {
    // The one that mattered: the server keeps whatever `date` a patch does not
    // mention, so an edit that only moves the hours has to say where they went.
    final wasOn = DateTime(2026, 9, 10);
    await open(
      tester,
      entry: WorkItem(
        id: 'w1',
        durationMinutes: 120,
        activityType: 'Development',
        description: 'moved',
        date: wasOn,
        startedAt: DateTime(2026, 9, 10, 9),
        endedAt: DateTime(2026, 9, 10, 11),
      ),
    );
    await save(tester);

    expect(repository.updated, hasLength(1));
    final draft = repository.updated.single.$2;
    final start = draft.startedAt!;
    expect(
      draft.date,
      DateTime(start.year, start.month, start.day),
      reason: 'the filed day follows the hours it is filed for',
    );
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

  testWidgets('an edit that did not touch the tags does not mention them', (
    tester,
  ) async {
    // The server reads a present tag list as an instruction and an empty one as
    // "remove them all". The sheet now shows the field, but showing is not
    // editing: re-sending what was loaded reads as harmless and is not — on an
    // instance where only administrators may coin a word, an entry carrying a
    // label from before the catalogue existed would be refused, and its owner
    // told to fix a tag they never touched.
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

    // Shown — so nothing is lost silently — and not sent.
    expect(find.text('focus · deep work'), findsOneWidget);
    await save(tester);

    expect(
      repository.updated.single.$2.toPatchJson().containsKey('tags'),
      isFalse,
    );
  });

  testWidgets('a new entry always states its tags, touched or not', (
    tester,
  ) async {
    // A create has no "leave them alone": every field it omits is a field it
    // does not have.
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, '1h 30m · 90m · 1:30'),
      '30m',
    );
    await save(tester);

    expect(repository.created.single.tags, isEmpty);
  });

  testWidgets('a required field is marked, and the save waits for it', (
    tester,
  ) async {
    // Before the request, not after it. A rule only the server knows about is a
    // save that fails on a form that looked complete, and the person is left to
    // guess which of six fields the sentence was about.
    await open(
      tester,
      policy: const TimePolicySnapshot(requiredDescription: true),
    );

    expect(find.text('time.entry.description *'), findsOneWidget);
    await save(tester);
    expect(repository.created, isEmpty);
    expect(find.text('time.policy.needDescription'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'time.entry.description *'),
      'pairing on the parser',
    );
    await tester.pumpAndSettle();
    await save(tester);

    expect(repository.created.single.description, 'pairing on the parser');
  });

  testWidgets('a required tag is asked for on the field that carries it', (
    tester,
  ) async {
    await open(tester, policy: const TimePolicySnapshot(requiredTag: true));

    expect(find.text('time.entry.tags *'), findsOneWidget);
    await save(tester);

    expect(repository.created, isEmpty);
    expect(find.text('time.policy.needTag'), findsOneWidget);
  });

  testWidgets('a frozen day cannot be saved, and says why', (tester) async {
    // The one rule that cannot be met by typing: the editor still opens, so the
    // entry can be read, and the save is greyed out with the reason under it.
    await open(
      tester,
      policy: TimePolicySnapshot(lockBefore: DateTime(2026, 9, 10)),
      entry: WorkItem(
        id: 'w1',
        durationMinutes: 60,
        activityType: 'Development',
        description: 'closed month',
        date: DateTime(2026, 9, 3),
      ),
    );

    // The reason, not a bare "locked": the notice names why the day is shut and
    // what to do about it — one component for every freeze there is. The sheet
    // asks for the compact form, which drops the "who" line: vertical space is
    // the scarcest thing in a bottom sheet and the remedy already names them.
    expect(find.text('time.lock.reason.lockDate'), findsOneWidget);
    expect(find.text('time.lock.remedy.lockDate'), findsOneWidget);
    expect(find.text('time.lock.holder.lockDate'), findsNothing);
    // And the way back is offered rather than left to be guessed.
    expect(find.text('time.lock.request'), findsOneWidget);
    await save(tester);
    expect(repository.updated, isEmpty);
  });

  testWidgets('nothing is marked required while the policy demands nothing', (
    tester,
  ) async {
    // The safe direction to be wrong in, and the state of a fresh instance:
    // marking a field required that is not blocks a save the server would have
    // accepted, with no way for the person to find out why.
    await open(tester);

    expect(find.text('time.entry.description'), findsOneWidget);
    expect(find.text('time.entry.tags'), findsOneWidget);
    expect(find.textContaining('*'), findsNothing);
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

  group('deleting from the sheet', () {
    final entry = WorkItem(
      id: 'w1',
      durationMinutes: 45,
      activityType: 'Testing',
      date: DateTime.now(),
    );

    Finder trash() => find.widgetWithIcon(IconButton, LucideIcons.trash2);

    testWidgets('an existing entry can be removed here', (tester) async {
      // The calendar has no row menu: this sheet is the only way into a block,
      // so without this an entry opened from the grid could be corrected in
      // every way except undone.
      await open(tester, entry: entry);
      expect(trash(), findsOneWidget);

      await tester.tap(trash());
      await tester.pumpAndSettle();
      // It asks first — the same confirmation the list's row menu shows.
      await tester.tap(find.text('common.delete').last);
      await tester.pumpAndSettle();

      expect(repository.deleted, ['w1']);
      // The page behind is told, because the sheet resolves to null the way a
      // dismissal does and nothing else would make it reload.
      expect(deletions, 1);
      expect(find.text('time.entry.edit'), findsNothing, reason: 'and closes');
    });

    testWidgets('and on a phone, where it is a bottom sheet', (tester) async {
      // The header row is `[icon, title, actions, close]`; a second icon button
      // in it is the one shape that needs no room of its own. At 402 points the
      // title still has about half the row, and a layout that did not fit would
      // fail this test by overflowing rather than by looking wrong.
      await open(tester, entry: entry, size: const Size(402, 874));

      expect(trash(), findsOneWidget);
      expect(tester.widget<IconButton>(trash()).onPressed, isNotNull);
    });

    testWidgets('a new entry has nothing to remove', (tester) async {
      await open(tester);

      expect(trash(), findsNothing);
    });

    testWidgets('a frozen day refuses it before the confirmation', (
      tester,
    ) async {
      // `delete` goes through the server's `assertWritable` like every other
      // write, so offering it on a frozen day would be a button that asks a
      // question and then answers 403.
      await open(
        tester,
        entry: entry,
        policy: TimePolicySnapshot(
          lockBefore: DateTime.now().add(const Duration(days: 1)),
        ),
      );

      expect(trash(), findsOneWidget);
      expect(tester.widget<IconButton>(trash()).onPressed, isNull);
    });
  });
}

class _FakeTimeRepository implements TimeRepository {
  final List<TimeEntryDraft> created = [];
  final List<(String, TimeEntryDraft)> updated = [];
  final List<String> deleted = [];

  @override
  Future<void> delete(String id) async => deleted.add(id);

  @override
  Future<PageResult<TimeTag>> tags({
    String? query,
    int page = 0,
    int size = 50,
    bool withUsage = false,
  }) async => (items: const <TimeTag>[], total: 0);

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
