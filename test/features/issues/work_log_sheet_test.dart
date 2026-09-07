import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/features/issues/work_log_sheet.dart';

/// The one sheet logs new time and corrects old — what it must get right in
/// edit mode is the payload: the entry's own values on screen, and only the
/// fields the reader changed on the wire.
void main() {
  late _FakeIssueRepository repository;

  final existing = WorkItem(
    id: 'w1',
    userId: 'u1',
    durationMinutes: 150,
    activityType: 'Testing',
    date: DateTime(2026, 9, 1),
    description: 'Regression run',
  );

  setUp(() => repository = _FakeIssueRepository());

  /// Hosts a button that opens the sheet, so the sheet has a route to pop.
  Widget host(WorkItem? entry, void Function(Object?) onClosed) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RepositoryProvider<IssueRepository>.value(
      value: repository,
      child: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                onClosed(
                  await showWorkLogSheet(context, 'i1', existing: entry),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(
    WidgetTester tester,
    WorkItem? entry,
    List<Object?> results,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(entry, results.add));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  List<TextFormField> fields(WidgetTester tester) =>
      tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();

  testWidgets('edit mode shows the entry as it is', (tester) async {
    final results = <Object?>[];
    await open(tester, existing, results);

    expect(find.text('time.editEntry'), findsOneWidget);
    expect(find.text('issues.logTime'), findsNothing);
    final inputs = fields(tester);
    expect(inputs[0].controller!.text, '2', reason: 'hours');
    expect(inputs[1].controller!.text, '30', reason: 'minutes');
    expect(inputs[2].controller!.text, 'Regression run', reason: 'note');
    // The dropdown holds the entry's activity (its label falls back to the
    // canonical value when no bundle is loaded).
    expect(find.text('Testing'), findsWidgets);
  });

  testWidgets('saving patches only what changed', (tester) async {
    final results = <Object?>[];
    await open(tester, existing, results);

    await tester.enterText(find.byType(TextFormField).at(1), '45');
    await tester.enterText(find.byType(TextFormField).at(2), 'Regression run ');
    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();

    expect(repository.posts, isEmpty);
    expect(repository.patches, hasLength(1));
    final patch = repository.patches.single;
    expect(patch.id, 'w1');
    expect(patch.minutes, 165);
    expect(patch.activityType, isNull, reason: 'unchanged fields stay home');
    expect(patch.description, isNull, reason: 'trailing whitespace is no edit');
    expect(patch.date, isNull);
    // The patched entry travels back, so a list can update the one row it
    // changed instead of paging from the top again.
    expect(results.single, isA<WorkItem>());
    expect((results.single as WorkItem).durationMinutes, 165);
  });

  testWidgets('nothing changed means nothing written', (tester) async {
    final results = <Object?>[];
    await open(tester, existing, results);

    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();

    expect(repository.patches, isEmpty);
    expect(results, [false]);
  });

  testWidgets('a cleared note travels as an empty description', (tester) async {
    final results = <Object?>[];
    await open(tester, existing, results);

    await tester.enterText(find.byType(TextFormField).at(2), '');
    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();

    expect(repository.patches.single.description, '');
  });

  testWidgets('logging new time still posts', (tester) async {
    final results = <Object?>[];
    await open(tester, null, results);

    expect(find.text('issues.logTime'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '0');
    await tester.enterText(find.byType(TextFormField).at(1), '20');
    await tester.tap(find.text('common.save'));
    await tester.pumpAndSettle();

    expect(repository.patches, isEmpty);
    expect(repository.posts.single.minutes, 20);
    expect(results, [true]);
  });
}

typedef _Patch = ({
  String id,
  int? minutes,
  String? activityType,
  String? description,
  DateTime? date,
});

class _FakeIssueRepository implements IssueRepository {
  final List<({String issueId, int minutes})> posts = [];
  final List<_Patch> patches = [];

  @override
  Future<WorkItem> addWorkItem(
    String issueId, {
    required int minutes,
    String? activityType,
    String? description,
    DateTime? date,
  }) async {
    posts.add((issueId: issueId, minutes: minutes));
    return WorkItem(
      id: 'new',
      userId: 'u1',
      durationMinutes: minutes,
      activityType: activityType ?? 'Development',
      date: date,
      description: description,
    );
  }

  @override
  Future<WorkItem> updateWorkItem(
    String id, {
    int? minutes,
    String? activityType,
    String? description,
    DateTime? date,
  }) async {
    patches.add((
      id: id,
      minutes: minutes,
      activityType: activityType,
      description: description,
      date: date,
    ));
    return WorkItem(
      id: id,
      userId: 'u1',
      durationMinutes: minutes ?? 0,
      activityType: activityType ?? 'Development',
      date: date,
      description: description,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
