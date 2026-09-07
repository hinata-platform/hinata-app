import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/features/issues/work_items_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The timeline's entries answer two questions per row — whose time is this,
/// and may I touch it — and the "all entries" sheet has to keep answering them
/// past the first page. Nothing here asserts on translated copy: widget tests
/// render raw i18n keys.
void main() {
  WorkItem item(
    String id, {
    String? userId = 'u1',
    String source = WorkItem.sourceApp,
    int minutes = 90,
    String? description,
  }) => WorkItem(
    id: id,
    userId: userId,
    durationMinutes: minutes,
    activityType: 'Development',
    date: DateTime(2026, 9, 4),
    description: description ?? 'note $id',
    source: source,
  );

  String? nameFor(String id) =>
      const {'u1': 'Ada Lovelace', 'u2': 'Linus Pauling'}[id];
  String? avatarFor(String id) => null;

  Widget host(Widget child, {IssueRepository? repository}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: RepositoryProvider<IssueRepository>.value(
        value: repository ?? _FakeIssueRepository(const []),
        child: Center(child: SizedBox(width: 420, child: child)),
      ),
    ),
  );

  Widget row(WorkItem entry, WorkItemAccess access) => WorkItemRow(
    item: entry,
    access: access,
    nameFor: nameFor,
    avatarFor: avatarFor,
    onEdit: (_) {},
    onDelete: (_) {},
  );

  group('entry menu', () {
    testWidgets('my own entry can be edited and deleted', (tester) async {
      await tester.pumpWidget(
        host(row(item('w1'), const WorkItemAccess(meId: 'u1'))),
      );
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();

      expect(find.text('common.edit'), findsOneWidget);
      expect(find.text('common.delete'), findsOneWidget);
    });

    testWidgets('someone else\'s entry has no menu for a plain member', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(row(item('w1', userId: 'u2'), const WorkItemAccess(meId: 'u1'))),
      );
      expect(find.byIcon(LucideIcons.ellipsis), findsNothing);
    });

    testWidgets('a colleague\'s hours show, their name and note do not', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          row(
            item('w1', userId: 'u2', description: 'rewrote the parser'),
            const WorkItemAccess(meId: 'u1'),
          ),
        ),
      );

      // The work is visible — that is what the card is for. (An untranslated
      // bundle falls the activity back to its raw value, which is what a
      // widget test sees.)
      expect(find.textContaining('Development'), findsOneWidget);
      // Who did it, and what they wrote about it, is not: a per-person reading
      // of a colleague's day is a policy, not a default.
      expect(find.textContaining('Linus Pauling'), findsNothing);
      expect(find.textContaining('rewrote the parser'), findsNothing);
      expect(find.byIcon(LucideIcons.user), findsOneWidget);
    });

    testWidgets('a lead sees the name and the note on the same entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          row(
            item('w1', userId: 'u2', description: 'rewrote the parser'),
            const WorkItemAccess(meId: 'u1', managesProject: true),
          ),
        ),
      );

      expect(find.textContaining('Linus Pauling'), findsOneWidget);
      expect(find.textContaining('rewrote the parser'), findsOneWidget);
    });

    testWidgets('your own entry always names you', (tester) async {
      await tester.pumpWidget(
        host(
          row(
            item('w1', userId: 'u1', description: 'my own note'),
            const WorkItemAccess(meId: 'u1'),
          ),
        ),
      );

      expect(find.textContaining('my own note'), findsOneWidget);
    });

    testWidgets('a lead may delete but not edit someone else\'s entry', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          row(
            item('w1', userId: 'u2'),
            const WorkItemAccess(meId: 'u1', managesProject: true),
          ),
        ),
      );
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();

      expect(find.text('common.delete'), findsOneWidget);
      expect(find.text('common.edit'), findsNothing);
    });

    testWidgets('choosing an action reports the entry', (tester) async {
      WorkItem? edited;
      WorkItem? deleted;
      await tester.pumpWidget(
        host(
          WorkItemRow(
            item: item('w1'),
            access: const WorkItemAccess(meId: 'u1'),
            nameFor: nameFor,
            avatarFor: avatarFor,
            onEdit: (e) => edited = e,
            onDelete: (e) => deleted = e,
          ),
        ),
      );
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('common.edit'));
      await tester.pumpAndSettle();
      expect(edited?.id, 'w1');
      expect(deleted, isNull);

      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      await tester.tap(find.text('common.delete'));
      await tester.pumpAndSettle();
      expect(deleted?.id, 'w1');
    });
  });

  group('who the entry belongs to', () {
    testWidgets('the pre-2.0 remainder is labelled, not attributed', (
      tester,
    ) async {
      final legacy = item('w1', userId: null, source: WorkItem.sourceLegacy);
      await tester.pumpWidget(
        host(row(legacy, const WorkItemAccess(meId: 'u1'))),
      );
      expect(find.textContaining('time.legacySource'), findsOneWidget);
      expect(find.byIcon(LucideIcons.gitCommitHorizontal), findsOneWidget);
      // Nobody owns it, so a plain member cannot touch it …
      expect(find.byIcon(LucideIcons.ellipsis), findsNothing);
    });

    testWidgets('… but a lead may remove it', (tester) async {
      final legacy = item('w1', userId: null, source: WorkItem.sourceLegacy);
      await tester.pumpWidget(
        host(
          row(legacy, const WorkItemAccess(meId: 'u1', managesProject: true)),
        ),
      );
      await tester.tap(find.byIcon(LucideIcons.ellipsis));
      await tester.pumpAndSettle();
      expect(find.text('common.delete'), findsOneWidget);
      expect(find.text('common.edit'), findsNothing);
    });

    testWidgets('an id the directory no longer knows reads as deleted', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          row(
            item('w1', userId: 'ghost'),
            // A closed account's entry is by definition not the reader's own,
            // so a lead is who sees it named at all.
            const WorkItemAccess(meId: 'u1', managesProject: true),
          ),
        ),
      );
      expect(find.textContaining('time.deletedUser'), findsOneWidget);
      expect(find.textContaining('ghost'), findsNothing);
      expect(find.byIcon(LucideIcons.userX), findsOneWidget);
    });
  });

  group('WorkItemList', () {
    testWidgets('shows the head of the list and the door to all of it', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        host(
          WorkItemList(
            items: [for (var i = 0; i < 10; i++) item('w$i')],
            total: 37,
            limit: 3,
            access: const WorkItemAccess(meId: 'u1'),
            nameFor: nameFor,
            avatarFor: avatarFor,
            onEdit: (_) {},
            onDelete: (_) {},
            onShowAll: () => opened++,
          ),
        ),
      );
      expect(find.byType(WorkItemRow), findsNWidgets(3));
      // Raw key: the count travels as an interpolation variable.
      expect(find.text('time.allEntries'), findsOneWidget);

      await tester.tap(find.text('time.allEntries'));
      expect(opened, 1);
    });

    testWidgets('an issue without entries has no button', (tester) async {
      await tester.pumpWidget(
        host(
          WorkItemList(
            items: const [],
            total: 0,
            access: const WorkItemAccess(meId: 'u1'),
            nameFor: nameFor,
            avatarFor: avatarFor,
            onEdit: (_) {},
            onDelete: (_) {},
            onShowAll: () {},
          ),
        ),
      );
      expect(find.text('time.allEntries'), findsNothing);
    });
  });

  group('AllWorkItemsSheet', () {
    const issue = Issue(
      id: 'i1',
      projectId: 'p1',
      readableId: 'HIN-1',
      title: 'One',
      state: 'Open',
      spentMinutes: 450,
    );

    testWidgets('pages the server as the reader scrolls', (tester) async {
      final repository = _FakeIssueRepository([
        for (var i = 0; i < 5; i++) item('w$i'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepositoryProvider<IssueRepository>.value(
              value: repository,
              child: Center(
                child: SizedBox(
                  width: 480,
                  // Short enough that a page of two entries already overflows:
                  // a list that fits its box has nothing to scroll, and
                  // scrolling is the whole subject here. In the sheet the
                  // reader actually sees, a page is fifty rows.
                  height: 170,
                  child: AllWorkItemsSheet(
                    issue: issue,
                    access: const WorkItemAccess(meId: 'u1'),
                    nameFor: nameFor,
                    avatarFor: avatarFor,
                    onChanged: () {},
                    pageSize: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.pagesAsked, [0]);
      expect(find.byType(WorkItemRow), findsNWidgets(2));

      // Nearing the bottom pulls the next page. A single gesture can pull more
      // than one: appending rows leaves the reader at the bottom of a longer
      // list, which is still a request for what comes after — so what is
      // asserted is that pages arrive in order, each exactly once.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(repository.pagesAsked, contains(1));
      expect(
        repository.pagesAsked,
        orderedEquals(repository.pagesAsked.toSet()),
      );

      // Scrolling on until the server's total is reached.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(repository.pagesAsked, [0, 1, 2]);
      expect(find.byType(WorkItemRow, skipOffstage: false), findsNWidgets(5));

      // Everything is loaded: one more scroll asks for nothing.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(repository.pagesAsked, [0, 1, 2]);
    });

    testWidgets('says so when there is nothing to page', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: RepositoryProvider<IssueRepository>.value(
              value: _FakeIssueRepository(const []),
              child: Center(
                child: SizedBox(
                  width: 480,
                  height: 260,
                  child: AllWorkItemsSheet(
                    issue: issue,
                    access: const WorkItemAccess(meId: 'u1'),
                    nameFor: nameFor,
                    avatarFor: avatarFor,
                    onChanged: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('time.noEntries'), findsOneWidget);
      expect(find.byType(WorkItemRow), findsNothing);
    });
  });
}

/// Answers the paged route from a fixed list, remembering which pages were
/// asked for.
class _FakeIssueRepository implements IssueRepository {
  _FakeIssueRepository(this.items);

  final List<WorkItem> items;
  final List<int> pagesAsked = [];

  @override
  Future<({List<WorkItem> items, int total})> workItemsPage(
    String issueId, {
    int page = 0,
    int size = 50,
  }) async {
    pagesAsked.add(page);
    final start = page * size;
    final slice = start >= items.length
        ? const <WorkItem>[]
        : items.sublist(start, (start + size).clamp(0, items.length));
    return (items: slice, total: items.length);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
