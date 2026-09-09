import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/time_policy_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/time_repository.dart';
import 'package:hinata/core/blocs/time_policy_cubit.dart';
import 'package:hinata/core/models/time_models.dart';
import 'package:hinata/features/time/tag_picker.dart';
import 'package:hinata/features/time/time_entry_history_sheet.dart';
import 'package:hinata/features/time/timesheet_cell_sheet.dart';

import 'fake_time_policy_cubit.dart';

/// The two surfaces stage 6 adds that nothing else covers: the tag picker, and
/// the history of one entry.
///
/// Both are about a rule being visible before it is enforced. The picker offers
/// "create it" only where the operator allows it — offering it and then
/// answering 403 teaches people to distrust the button rather than teaching them
/// the rule. The history exists because an audit trail only an administrator can
/// read is a covert one, so the person it is about has to be able to open it.
void main() {
  group('the tag picker', () {
    Future<List<String>?> open(
      WidgetTester tester, {
      required bool canCreate,
      List<TimeTag> catalogue = const [],
      List<String> selected = const [],
    }) async {
      List<String>? result;
      await tester.pumpWidget(
        RepositoryProvider<TimeRepository>.value(
          value: _FakeTagRepository(catalogue),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async => result = await showTimeTagPicker(
                      context,
                      selected: selected,
                      canCreate: canCreate,
                    ),
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
      return result;
    }

    testWidgets('a curated catalogue does not offer to coin a word', (
      tester,
    ) async {
      await open(tester, canCreate: false);

      await tester.enterText(find.byType(TextField), 'review');
      await tester.pumpAndSettle();

      expect(find.textContaining('time.tags.create'), findsNothing);
      // And it says why, rather than showing an empty list that reads as broken.
      expect(find.text('time.tags.noneCurated'), findsOneWidget);
    });

    testWidgets('an open catalogue offers the word that was typed', (
      tester,
    ) async {
      await open(tester, canCreate: true);

      await tester.enterText(find.byType(TextField), 'review');
      await tester.pumpAndSettle();

      expect(find.textContaining('time.tags.create'), findsOneWidget);
    });

    testWidgets('a word already in the catalogue is not offered twice', (
      tester,
    ) async {
      await open(
        tester,
        canCreate: true,
        catalogue: const [TimeTag(id: 't1', name: 'Meeting')],
      );

      // Typed in the other capitalisation, because the catalogue treats the two
      // as one word and a "create Meeting" row here would be a duplicate the
      // server refuses.
      await tester.enterText(find.byType(TextField), 'meeting');
      await tester.pumpAndSettle();

      expect(find.textContaining('time.tags.create'), findsNothing);
      expect(find.text('Meeting'), findsOneWidget);
    });

    testWidgets(
      'a tag on the entry that the catalogue does not list survives',
      (tester) async {
        // An entry written before the catalogue existed. Confirming the picker
        // must not silently drop a word it happens not to know.
        await open(tester, canCreate: true, selected: const ['legacy word']);

        expect(find.text('legacy word'), findsOneWidget);
      },
    );
  });

  group('the history of an entry', () {
    Future<void> open(
      WidgetTester tester, {
      required WorkItem entry,
      required List<TimeEntryHistoryEntry> rows,
    }) async {
      await tester.pumpWidget(
        RepositoryProvider<TimeRepository>.value(
          value: _FakeHistoryRepository(rows),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () =>
                        showTimeEntryHistorySheet(context, entry: entry),
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

    testWidgets('names who changed it and what moved', (tester) async {
      await open(
        tester,
        entry: WorkItem(
          id: 'w1',
          durationMinutes: 60,
          activityType: 'Development',
          createdAt: DateTime(2026, 9, 3, 9),
        ),
        rows: [
          TimeEntryHistoryEntry(
            id: 'a1',
            action: 'TIME_ENTRY_UPDATED',
            timestamp: DateTime(2026, 9, 4, 10),
            actorLabel: 'Alex Lead',
            metadata: const {'minutes': '45', 'workItem': 'w1'},
          ),
        ],
      );

      expect(find.text('audit.action.TIME_ENTRY_UPDATED'), findsOneWidget);
      expect(find.text('Alex Lead'), findsOneWidget);
      expect(
        find.textContaining('time.history.field.minutes: 45'),
        findsOneWidget,
      );
    });

    testWidgets('an entry nobody touched still says when it was filed', (
      tester,
    ) async {
      // The creation line comes off the entry itself, so an instance that has
      // not switched the creation event on still has a first line rather than
      // an empty sheet that reads as a failure.
      await open(
        tester,
        entry: WorkItem(
          id: 'w1',
          durationMinutes: 60,
          activityType: 'Development',
          createdAt: DateTime(2026, 9, 3, 9),
        ),
        rows: const [],
      );

      expect(find.textContaining('time.history.created'), findsOneWidget);
      expect(find.text('time.history.emptyTitle'), findsOneWidget);
    });

    testWidgets('no client address and no user agent reach this screen', (
      tester,
    ) async {
      // The audit record carries both; they belong to an investigation an
      // administrator runs, not to a sheet every colleague can open.
      await open(
        tester,
        entry: const WorkItem(
          id: 'w1',
          durationMinutes: 60,
          activityType: 'Development',
        ),
        rows: [
          TimeEntryHistoryEntry(
            id: 'a1',
            action: 'TIME_ENTRY_UPDATED',
            timestamp: DateTime(2026, 9, 4, 10),
            actorLabel: 'Alex Lead',
            metadata: const {'ip': '10.0.xx.xx', 'userAgent': 'Hinata/10.3.3'},
          ),
        ],
      );

      expect(find.textContaining('10.0.'), findsNothing);
      expect(find.textContaining('Hinata/'), findsNothing);
    });
  });

  group('the timesheet cell', () {
    Future<void> open(
      WidgetTester tester, {
      required TimePolicySnapshot policy,
      String? projectId = 'p1',
    }) async {
      final repository = _FakeCellRepository();
      await tester.pumpWidget(
        RepositoryProvider<TimeRepository>.value(
          value: repository,
          child: BlocProvider<TimePolicyCubit>.value(
            value: FakeTimePolicyCubit(policy, repository),
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () => showTimesheetCellSheet(
                        context,
                        day: DateTime(2026, 9, 3),
                        projectId: projectId,
                        projectLabel: 'Hinata',
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

    testWidgets('a frozen day offers no composer and no delete', (
      tester,
    ) async {
      await open(
        tester,
        policy: TimePolicySnapshot(lockBefore: DateTime(2026, 9, 10)),
      );

      expect(find.text('time.policy.locked'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, '1h 30m · 90m · 1:30'),
        findsNothing,
      );
    });

    testWidgets('a required field this cell cannot collect says which one', (
      tester,
    ) async {
      // A cell holds a duration and a description. An instance that demands a
      // tag on every entry has made this way of composing impossible, and saying
      // so beats a server refusal on a form with no field to fix.
      await open(tester, policy: const TimePolicySnapshot(requiredTag: true));

      expect(find.text('time.policy.needTag'), findsOneWidget);
    });

    testWidgets('an ordinary day still composes in two fields', (tester) async {
      await open(tester, policy: TimePolicySnapshot.none);

      expect(
        find.widgetWithText(TextField, '1h 30m · 90m · 1:30'),
        findsOneWidget,
      );
      expect(find.text('time.policy.locked'), findsNothing);
    });
  });

  group('the policy the app holds', () {
    test('starts on "nothing is required", which is a fresh instance', () {
      const policy = TimePolicySnapshot.none;

      expect(policy.requiresPlacement, isFalse);
      expect(policy.requiredDescription, isFalse);
      expect(policy.isLocked(DateTime(2020)), isFalse);
    });

    test('a lock is judged by the day, not by the hour it is read at', () {
      final policy = TimePolicySnapshot(lockBefore: DateTime(2026, 9, 10));

      expect(policy.isLocked(DateTime(2026, 9, 9, 23, 59)), isTrue);
      // The lock date itself is open: entries *before* it are frozen.
      expect(policy.isLocked(DateTime(2026, 9, 10, 0, 1)), isFalse);
      expect(policy.isLocked(null), isFalse);
    });

    test('an issue implies a project', () {
      const policy = TimePolicySnapshot(requiredIssue: true);

      expect(policy.requiresPlacement, isTrue);
    });
  });
}

class _FakeTagRepository implements TimeRepository {
  _FakeTagRepository(this.catalogue);

  final List<TimeTag> catalogue;

  @override
  Future<PageResult<TimeTag>> tags({
    String? query,
    int page = 0,
    int size = 50,
    bool withUsage = false,
  }) async {
    final matched = query == null
        ? catalogue
        : catalogue
              .where(
                (tag) => tag.name.toLowerCase().startsWith(query.toLowerCase()),
              )
              .toList();
    return (items: matched, total: matched.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeHistoryRepository implements TimeRepository {
  _FakeHistoryRepository(this.rows);

  final List<TimeEntryHistoryEntry> rows;

  @override
  Future<PageResult<TimeEntryHistoryEntry>> history(
    String id, {
    int page = 0,
    int size = 50,
  }) async => (
    items: page == 0 ? rows : const <TimeEntryHistoryEntry>[],
    total: rows.length,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeCellRepository implements TimeRepository {
  @override
  Future<PageResult<WorkItem>> entries({
    TimeEntryFilter filter = const TimeEntryFilter(),
    int page = 0,
    int size = 50,
  }) async => (items: const <WorkItem>[], total: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
