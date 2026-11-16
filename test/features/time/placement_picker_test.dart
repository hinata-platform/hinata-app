import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/features/time/placement_picker.dart';

/// The project picker of an entry pages through the server as the reader
/// scrolls, and a page that fails stops the scrolling from asking again until
/// the reader does.
void main() {
  late _PagedProjects projects;

  setUp(() => projects = _PagedProjects());

  Future<void> open(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ProjectRepository>.value(value: projects),
          RepositoryProvider<IssueRepository>.value(value: _NoIssues()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showTimeProjectPicker(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // A loader that is still waiting never settles.
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    await tester.pumpAndSettle();
  }

  testWidgets('scrolling to the end asks for the next page and shows it', (
    tester,
  ) async {
    await open(tester);
    expect(projects.pages, [0]);
    expect(find.text('Project 1'), findsOneWidget);

    await scrollToEnd(tester);

    expect(projects.pages, [0, 1]);
    await scrollToEnd(tester);
    expect(find.text('Project 30'), findsOneWidget);
    // All of it is there: nothing more is asked for.
    expect(projects.pages, [0, 1]);
  });

  testWidgets('a page that fails is asked again only when the reader says so', (
    tester,
  ) async {
    projects.failPage = 1;
    await open(tester);

    await scrollToEnd(tester);
    expect(projects.pages, [0, 1]);
    expect(find.text('time.placement.loadAgain'), findsOneWidget);

    // Scrolling on does not hammer a server that just refused.
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    await scrollToEnd(tester);
    expect(projects.pages, [0, 1]);

    projects.failPage = null;
    await tester.tap(find.text('time.placement.loadAgain'));
    await tester.pumpAndSettle();
    expect(projects.pages, [0, 1, 1]);
    await scrollToEnd(tester);
    expect(find.text('Project 30'), findsOneWidget);
  });

  testWidgets('closing the picker while a page is on its way is not an error', (
    tester,
  ) async {
    final held = Completer<void>();
    projects.holdUntil = held.future;
    await open(tester, settle: false);

    // Dismissed before the server answered.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(projects.tokens.single!.isCancelled, isTrue);

    // The answer arrives anyway, to a cubit that is closed.
    held.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new search cancels the request it replaces', (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), 'Pro');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(projects.tokens.first!.isCancelled, isTrue);
    expect(projects.queries.last, 'Pro');
  });
}

class _PagedProjects implements ProjectRepository {
  static const total = 30;

  final List<int> pages = [];
  final List<String?> queries = [];
  final List<CancelToken?> tokens = [];
  int? failPage;

  /// Holds every answer back until this completes, the way a slow server does.
  Future<void>? holdUntil;

  @override
  Future<({List<Project> projects, int total})> searchProjects({
    String? query,
    int page = 0,
    int size = 25,
    bool archived = false,
    CancelToken? cancelToken,
  }) async {
    pages.add(page);
    queries.add(query);
    tokens.add(cancelToken);
    if (holdUntil case final held?) await held;
    if (page == failPage) throw ApiFailure('errors.test', statusCode: 500);
    final from = page * size;
    final to = (from + size).clamp(0, total);
    return (
      projects: [
        for (var i = from; i < to; i++)
          Project(id: 'p$i', key: 'P$i', name: 'Project ${i + 1}'),
      ],
      total: total,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _NoIssues implements IssueRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
