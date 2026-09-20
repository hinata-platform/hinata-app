/// The head of the Issues page on a wide window: the title, and under it the
/// tools as glass pills that stay where they are while the list scrolls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/widgets/glass_filter_bar.dart';
import 'package:hinata/features/issues/issues_screen.dart';
import 'package:hinata/features/shell/page_chrome.dart';

final _forty = [
  for (var i = 1; i <= 40; i++)
    Issue(
      id: 'i$i',
      projectId: 'p1',
      readableId: 'MOB-$i',
      title: 'Issue number $i',
      state: 'OPEN',
    ),
];

void main() {
  Future<void> open(
    WidgetTester tester, {
    required double width,
    List<Issue> issues = const [],
  }) async {
    tester.view
      ..physicalSize = Size(width, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chrome = PageChromeController();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IssueRepository>.value(
            value: _FakeIssueRepository(issues),
          ),
          RepositoryProvider<ProjectRepository>.value(
            value: _FakeProjectRepository(),
          ),
          RepositoryProvider<UserRepository>.value(
            value: _FakeUserRepository(),
          ),
        ],
        // A router above it, because PageChrome publishes into the shell by
        // asking GoRouterState where it is.
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/issues',
            routes: [
              GoRoute(
                path: '/issues',
                builder: (_, _) => PageChromeScope(
                  controller: chrome,
                  child: const Scaffold(body: IssuesScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Pumped by hand: the loaders spin for as long as they are on screen.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder pills() => find.descendant(
    of: find.byType(WideToolbar),
    matching: find.byType(GlassPill),
  );

  testWidgets('wears its tools as glass pills under the title', (tester) async {
    await open(tester, width: 1400);

    // Group, sort, filter, time range and the export.
    expect(pills(), findsNWidgets(5));
  });

  testWidgets('keeps its tools in place while the list scrolls', (
    tester,
  ) async {
    await open(tester, width: 1400, issues: _forty);
    final toolbar = tester.getTopLeft(find.byType(WideToolbar));
    final row = tester.getTopLeft(find.text('Issue number 10')).dy;

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      tester.getTopLeft(find.text('Issue number 10')).dy,
      lessThan(row - 300),
    );
    // Narrowing a long list starts at its tools, not at scrolling back up.
    expect(tester.getTopLeft(find.byType(WideToolbar)), toolbar);
  });

  testWidgets('wraps its tools on a narrow window instead of cutting them', (
    tester,
  ) async {
    // A desktop window dragged narrow, still too wide for the phone layout.
    // A single scrolling line hid the pills past its edge here.
    await open(tester, width: 700);

    expect(pills(), findsNWidgets(5));
    for (var i = 0; i < 5; i++) {
      final pill = tester.getRect(pills().at(i));
      expect(pill.left, greaterThanOrEqualTo(0));
      expect(pill.right, lessThanOrEqualTo(700));
    }
    expect(tester.takeException(), isNull);
  });
}

class _FakeIssueRepository implements IssueRepository {
  _FakeIssueRepository(this.all);

  final List<Issue> all;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #issues => Future<({List<Issue> issues, int total})>.value((
          issues: all,
          total: all.length,
        )),
        _ => throw UnimplementedError('${invocation.memberName} is not faked'),
      };
}

class _FakeProjectRepository implements ProjectRepository {
  @override
  Future<List<Project>> projects({bool archived = false, bool? template}) async => const [
    Project(id: 'p1', key: 'MOB', name: 'Mobile App'),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeUserRepository implements UserRepository {
  @override
  Future<List<DirectoryUser>> users() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
