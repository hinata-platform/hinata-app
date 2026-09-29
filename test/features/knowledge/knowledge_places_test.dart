import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/repositories/article_repository.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/project_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/knowledge/data/knowledge_models.dart';
import 'package:hinata/features/knowledge/data/knowledge_repository.dart';
import 'package:hinata/features/knowledge/knowledge_place_field.dart';
import 'package:hinata/features/knowledge/knowledge_tree.dart';

/// HIN-129: where a knowledge page lives decides who reads it.
///
/// Grants can open a subpage without its parent, so the tree has to show such
/// a page as a root; a top-level page moves through its own `place` endpoint;
/// and an edit never tries to move a page by sending a project or team.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  Map<String, dynamic> page(
    String id, {
    String? parentId,
    String? projectId,
    String? teamId,
    String space = 'Docs',
  }) => {
    'id': id,
    'title': 'Page $id',
    'space': space,
    'parentId': ?parentId,
    'projectId': ?projectId,
    'teamId': ?teamId,
    'authorId': 'me',
  };

  Future<(KnowledgeRepository, _RoutingApiClient)> loaded(
    List<Map<String, dynamic>> pages, {
    bool truncated = false,
    List<Map<String, dynamic>> teams = const [],
    List<Map<String, dynamic>> projects = const [],
  }) async {
    final api = _RoutingApiClient(pages)
      ..truncated = truncated
      ..teams = teams
      ..projects = projects;
    final repo = KnowledgeRepository(
      articles: ArticleRepository(api),
      users: UserRepository(api),
      auth: AuthRepository(api),
      projects: ProjectRepository(api),
      teams: TeamRepository(api),
    );
    await repo.init();
    return (repo, api);
  }

  group('tree roots', () {
    test(
      'a page whose parent is not readable is a root, not dropped',
      () async {
        final (repo, _) = await loaded([
          page('top'),
          page('child', parentId: 'top'),
          // Granted on its own: its parent "hidden" is not in the answer.
          page('granted', parentId: 'hidden', teamId: 't1'),
        ]);

        final roots = repo.rootsInSpace('Docs').map((a) => a.id).toSet();
        expect(roots, {'top', 'granted'});
        // Its place still follows the unseen parent, so it is not top-level.
        expect(repo.isTopLevel(repo.articleById('granted')!), isFalse);
      },
    );

    testWidgets('the tree renders the orphan with its place glyph', (
      tester,
    ) async {
      late KnowledgeRepository repo;
      await tester.runAsync(() async {
        repo = (await loaded([
          page('top', projectId: 'p1'),
          page('granted', parentId: 'hidden', teamId: 't1'),
        ])).$1;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KnowledgeTree(
                repo: repo,
                spaceId: 'Docs',
                selectedId: null,
                onSelect: (_) {},
                onSpaceChange: (_) {},
                onNewChild: (_) {},
                onMove: (_, {parentId, required spaceId}) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Page granted'), findsOneWidget);
      expect(find.text('Page top'), findsOneWidget);
      expect(
        find.byIcon(KbPlaceGlyph.iconFor(KbPlace.project)),
        findsOneWidget,
      );
      expect(find.byIcon(KbPlaceGlyph.iconFor(KbPlace.team)), findsOneWidget);
    });
  });

  group('truncated list', () {
    test('the repository remembers the server cut the list', () async {
      final (full, _) = await loaded([page('top')]);
      expect(full.listTruncated, isFalse);
      final (cut, _) = await loaded([page('top')], truncated: true);
      expect(cut.listTruncated, isTrue);
    });

    testWidgets('the tree says so instead of leaving orphans unexplained', (
      tester,
    ) async {
      late KnowledgeRepository repo;
      await tester.runAsync(() async {
        repo = (await loaded([
          page('granted', parentId: 'past-the-cut'),
        ], truncated: true)).$1;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KnowledgeTree(
                repo: repo,
                spaceId: 'Docs',
                selectedId: null,
                onSelect: (_) {},
                onSpaceChange: (_) {},
                onNewChild: (_) {},
                onMove: (_, {parentId, required spaceId}) {},
                onDelete: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('knowledge.tree.truncated'), findsOneWidget);
    });
  });

  group('place names and rights', () {
    const team = {
      'id': 't1',
      'name': 'Ops',
      'members': [
        {'userId': 'me', 'role': 'ADMIN'},
      ],
    };
    const otherTeam = {
      'id': 't2',
      'name': 'Sales',
      'members': [
        {'userId': 'me', 'role': 'MEMBER'},
      ],
    };
    const project = {
      'id': 'p1',
      'key': 'WEB',
      'name': 'Website',
      'leadIds': ['someone-else'],
    };

    test('names come from one team list and one project lookup', () async {
      final (repo, api) = await loaded(
        [
          page('a', projectId: 'p1'),
          page('b', projectId: 'p1'),
          page('c', teamId: 't1'),
        ],
        teams: const [team],
        projects: const [project],
      );

      await Future.wait([repo.loadPlaces(), repo.loadPlaces()]);

      expect(repo.placeName('p1'), 'Website');
      expect(repo.placeName('t1'), 'Ops');
      expect(api.calls.where((c) => c.$2 == '/api/v1/teams'), hasLength(1));
      final resolves = api.calls.where(
        (c) => c.$2 == '/api/v1/projects/resolve',
      );
      expect(resolves, hasLength(1));
      expect((resolves.single.$3! as Map)['ids'], 'p1');
      // Never one request per page.
      expect(
        api.calls.where((c) => c.$2.startsWith('/api/v1/projects/p')),
        isEmpty,
      );
    });

    test('who may move a page follows the place it is in', () async {
      final (repo, _) = await loaded(
        [
          page('mine'),
          {...page('theirs'), 'authorId': 'other'},
          page('ops', teamId: 't1'),
          page('sales', teamId: 't2'),
          page('web', projectId: 'p1'),
        ],
        teams: const [team, otherTeam],
        projects: const [project],
      );
      await repo.loadPlaces();

      bool may(String id) => repo.mayChangePlace(repo.articleById(id)!);
      expect(may('mine'), isTrue);
      expect(may('theirs'), isFalse);
      // Team-Admin of Ops, plain member of Sales.
      expect(may('ops'), isTrue);
      expect(may('sales'), isFalse);
      // Not a lead, and no team of mine owns the project.
      expect(may('web'), isFalse);
    });

    testWidgets('the field shows the name and stays shut without the right', (
      tester,
    ) async {
      late KnowledgeRepository repo;
      await tester.runAsync(() async {
        repo = (await loaded(
          [page('sales', teamId: 't2')],
          teams: const [team, otherTeam],
        )).$1;
        await repo.loadPlaces();
      });
      final article = repo.articleById('sales')!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnowledgePlaceField(
              repo: repo,
              projectId: article.projectId,
              teamId: article.teamId,
              canChange: () => repo.mayChangePlace(article),
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sales'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });
  });

  group('copyWith', () {
    test('a place can be cleared, and is kept when not passed', () {
      const article = KbArticle(
        id: 'a',
        spaceId: 'Docs',
        parentId: null,
        title: 'A',
        icon: 'file-text',
        authorId: 'me',
        contributorIds: [],
        updated: '',
        created: '',
        reads: 0,
        labels: [],
        status: 'published',
        body: '',
        teamId: 't1',
      );
      expect(article.copyWith(title: 'B').teamId, 't1');
      expect(article.copyWith(teamId: null).teamId, isNull);
      expect(article.copyWith(projectId: 'p1').place, KbPlace.project);
    });
  });

  group('place', () {
    test('moving a page calls PUT /place and carries the subtree', () async {
      final (repo, api) = await loaded([
        page('top'),
        page('child', parentId: 'top'),
      ]);
      api.putResponse = page('top', teamId: 't1');

      await repo.placeArticle('top', teamId: 't1');

      final (method, path, body) = api.calls.last;
      expect(method, 'put');
      expect(path, '/api/v1/articles/top/place');
      expect(body, {'projectId': null, 'teamId': 't1'});
      expect(repo.articleById('top')!.place, KbPlace.team);
      expect(repo.articleById('child')!.teamId, 't1');
    });

    test('making a page private sends both as null', () async {
      final (repo, api) = await loaded([page('top', projectId: 'p1')]);
      api.putResponse = page('top');

      await repo.placeArticle('top');

      expect(api.calls.last.$3, {'projectId': null, 'teamId': null});
      expect(repo.articleById('top')!.place, KbPlace.private);
    });

    test('an edit never sends a project or team', () async {
      final (repo, api) = await loaded([page('top', projectId: 'p1')]);
      api.patchResponse = page('top', projectId: 'p1');

      await repo.saveEdit('top', title: 'New', doc: '{}', spaceId: 'Docs');

      final (method, _, body) = api.calls.last;
      final sent = body! as Map;
      expect(method, 'patch');
      expect(sent.containsKey('projectId'), isFalse);
      expect(sent.containsKey('teamId'), isFalse);
    });

    test('a subpage is created without a place of its own', () async {
      final (repo, api) = await loaded([page('top', teamId: 't1')]);
      api.postResponse = page('new', parentId: 'top', teamId: 't1');

      await repo.createArticle(
        title: 'New',
        doc: '{}',
        spaceId: 'Docs',
        parentId: 'top',
        teamId: 'ignored',
      );

      final body = api.calls.last.$3! as Map;
      expect(body['parentId'], 'top');
      expect(body.containsKey('teamId'), isFalse);
    });

    test('a new top-level page goes where it was put', () async {
      final (repo, api) = await loaded(const []);
      api.postResponse = page('new', projectId: 'p1');

      await repo.createArticle(
        title: 'New',
        doc: '{}',
        spaceId: 'Docs',
        projectId: 'p1',
      );

      expect((api.calls.last.$3! as Map)['projectId'], 'p1');
    });
  });
}

/// Answers the knowledge base's loads by path and records every write.
class _RoutingApiClient implements ApiClient {
  _RoutingApiClient(this.pages);

  final List<Map<String, dynamic>> pages;
  final List<(String, String, Object?)> calls = [];
  bool truncated = false;
  List<Map<String, dynamic>> teams = const [];
  List<Map<String, dynamic>> projects = const [];
  Map<String, dynamic>? putResponse;
  Map<String, dynamic>? patchResponse;
  Map<String, dynamic>? postResponse;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    calls.add(('get', path, query));
    return switch (path) {
      '/api/v1/users' => const <dynamic>[],
      '/api/v1/spaces' => const <dynamic>[],
      '/api/v1/auth/me' => {
        'id': 'me',
        'email': 'me@example.org',
        'username': 'me',
      },
      '/api/v1/teams' => teams,
      '/api/v1/projects/resolve' => [
        for (final p in projects)
          if ((query!['ids'] as String).split(',').contains(p['id'])) p,
      ],
      _ => throw ApiFailure('not faked: $path'),
    };
  }

  @override
  Future<({dynamic data, String? Function(String name) header})> getWithHeaders(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    calls.add(('get', path, query));
    if (path != '/api/v1/articles') throw ApiFailure('not faked: $path');
    return (
      data: pages,
      header: (String name) =>
          truncated && name.toLowerCase() == 'x-truncated' ? 'true' : null,
    );
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add(('put', path, body));
    return putResponse;
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async {
    calls.add(('patch', path, body));
    return patchResponse;
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    calls.add(('post', path, body));
    return postResponse;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
