import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/article_repository.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/knowledge/data/knowledge_repository.dart';
import 'package:hinata/features/knowledge/knowledge_location.dart';

/// HIN-135: how the knowledge base is put together for reading — the order of
/// pages, the way up a tree, labels, links between pages, favourites, and the
/// addresses every view has.
void main() {
  Map<String, dynamic> page(
    String id, {
    String? parentId,
    String space = 'Docs',
    int sortOrder = 0,
    List<String> tags = const [],
    String? doc,
    String? updatedAt,
  }) => {
    'id': id,
    'title': 'Page $id',
    'space': space,
    'parentId': ?parentId,
    'sortOrder': sortOrder,
    'tags': tags,
    'contentDoc': ?doc,
    'updatedAt': ?updatedAt,
    'authorId': 'me',
    'projectId': 'p1',
  };

  String linkTo(String id) => jsonEncode({
    'root': {
      'type': 'root',
      'children': [
        {
          'type': 'paragraph',
          'children': [
            {'type': 'smartlink', 'kind': 'doc', 'targetId': id, 'label': 'x'},
          ],
        },
      ],
    },
  });

  Future<(KnowledgeRepository, _Api)> loaded(
    List<Map<String, dynamic>> pages, {
    Map<String, dynamic>? marks,
  }) async {
    final api = _Api(pages)..marks = marks;
    final repo = KnowledgeRepository(
      articles: ArticleRepository(api),
      users: UserRepository(api),
      auth: AuthRepository(api),
    );
    await repo.init();
    return (repo, api);
  }

  group('account change', () {
    test('reset forgets the pages and loads the next account afresh', () async {
      final (repo, api) = await loaded([page('a'), page('b')]);
      expect(repo.articles, hasLength(2));

      repo.reset();
      expect(repo.articles, isEmpty);
      api.pages
        ..clear()
        ..add(page('c'));
      await repo.init();

      expect(repo.articles.map((a) => a.id), ['c']);
    });
  });

  group('order', () {
    test('siblings come by position, then by title', () async {
      final (repo, _) = await loaded([
        page('b', sortOrder: 1),
        page('c', sortOrder: 0),
        page('a', sortOrder: 1),
      ]);
      expect(repo.rootsInSpace('Docs').map((a) => a.id), ['c', 'a', 'b']);
    });

    test('reordering shows at once and goes back when refused', () async {
      final (repo, api) = await loaded([
        page('a', sortOrder: 0),
        page('b', sortOrder: 1),
      ]);
      api.failPut = true;

      await expectLater(repo.reorder(['b', 'a']), throwsA(isA<ApiFailure>()));

      expect(repo.rootsInSpace('Docs').map((a) => a.id), ['a', 'b']);
      final (method, path, body) = api.calls.last;
      expect((method, path), ('put', '/api/v1/articles/order'));
      expect(body, {
        'ids': ['b', 'a'],
      });
    });
  });

  group('tree', () {
    test('the way up runs from the top down to the parent', () async {
      final (repo, _) = await loaded([
        page('root'),
        page('mid', parentId: 'root'),
        page('leaf', parentId: 'mid'),
      ]);
      expect(repo.ancestorsOf('leaf').map((a) => a.id), ['root', 'mid']);
      expect(repo.ancestorsOf('root'), isEmpty);
    });

    test('the way up stops at a parent the reader cannot see', () async {
      final (repo, _) = await loaded([page('leaf', parentId: 'hidden')]);
      expect(repo.ancestorsOf('leaf'), isEmpty);
    });

    test('a cycle in stored data does not loop', () async {
      final (repo, _) = await loaded([
        page('a', parentId: 'b'),
        page('b', parentId: 'a'),
      ]);
      expect(repo.ancestorsOf('a').map((a) => a.id), ['b']);
    });
  });

  group('subpages', () {
    test('come in sibling order and follow a move', () async {
      final (repo, api) = await loaded([
        page('root'),
        page('b', parentId: 'root', sortOrder: 1),
        page('a', parentId: 'root', sortOrder: 0),
        page('other'),
      ]);
      expect(repo.childrenOf('root').map((a) => a.id), ['a', 'b']);

      api.saved = page('b', parentId: 'other');
      await repo.moveArticle('b', parentId: 'other');
      expect(repo.childrenOf('root').map((a) => a.id), ['a']);
      expect(repo.childrenOf('other').map((a) => a.id), ['b']);
    });
  });

  group('search', () {
    test('titles first, then space, labels and text', () async {
      final (repo, _) = await loaded([
        {
          ...page('a', tags: ['Setup']),
          'title': 'Laptop',
        },
        {...page('b'), 'title': 'Setup guide'},
        {...page('c'), 'content': 'How to   SETUP\nthe printer'},
        {...page('d', space: 'Setup'), 'title': 'Rules'},
        page('e'),
      ]);
      expect(repo.search('setup').map((a) => a.id), ['b', 'a', 'c', 'd']);
      expect(repo.search(''), isEmpty);
    });

    test('the excerpt shows the words around the match', () async {
      final long = '${'word ' * 30}needle${' tail' * 40}';
      final (repo, _) = await loaded([
        {...page('a'), 'content': long},
        {...page('b'), 'content': 'Short\n\ntext'},
      ]);
      final excerpt = repo.searchExcerpt('a', 'needle');
      expect(excerpt, startsWith('…'));
      expect(excerpt, contains('needle'));
      expect(excerpt, endsWith('…'));
      // No match in the text: its start, whitespace collapsed.
      expect(repo.searchExcerpt('b', 'docs'), 'Short text');
    });

    test('follows a saved text', () async {
      final (repo, api) = await loaded([page('a')]);
      expect(repo.search('fresh'), isEmpty);
      api.saved = {...page('a'), 'content': 'fresh words'};
      await repo.saveEdit('a', title: 'Page a', doc: '{}', spaceId: 'Docs');
      expect(repo.search('fresh').map((a) => a.id), ['a']);
    });
  });

  group('link targets', () {
    test(
      'issues are fetched once, again after a failure or a reload',
      () async {
        final (repo, _) = await loaded([page('a')]);
        var fetches = 0;
        var fail = true;
        Future<List<Issue>> fetch() async {
          fetches++;
          if (fail) throw ApiFailure('down');
          return const [];
        }

        await expectLater(repo.linkIssues(fetch), throwsA(isA<ApiFailure>()));
        fail = false;
        await repo.linkIssues(fetch);
        await repo.linkIssues(fetch);
        expect(fetches, 2);

        await repo.reload();
        await repo.linkIssues(fetch);
        expect(fetches, 3);
      },
    );
  });

  group('labels', () {
    test('come from readable pages, most used first, per space', () async {
      final (repo, _) = await loaded([
        page('a', tags: ['howto', 'setup']),
        page('b', tags: ['howto']),
        page('c', space: 'Other', tags: ['legal']),
      ]);
      expect(repo.labels().map((l) => (l.label, l.count)), [
        ('howto', 2),
        ('legal', 1),
        ('setup', 1),
      ]);
      expect(repo.labels(spaceId: 'Docs').map((l) => l.label), [
        'howto',
        'setup',
      ]);
    });
  });

  group('related pages', () {
    test('are the pages linked to and the pages linking here', () async {
      final (repo, _) = await loaded([
        page('a', doc: linkTo('b')),
        page('b'),
        page('c', doc: linkTo('b')),
        page('d'),
      ]);
      expect(repo.relatedArticles(repo.articleById('b')!).map((a) => a.id), [
        'a',
        'c',
      ]);
      expect(repo.relatedArticles(repo.articleById('a')!).map((a) => a.id), [
        'b',
      ]);
      expect(repo.relatedArticles(repo.articleById('d')!), isEmpty);
    });

    test('a link to a page the reader cannot see is left out', () async {
      final (repo, _) = await loaded([page('a', doc: linkTo('secret'))]);
      expect(repo.relatedArticles(repo.articleById('a')!), isEmpty);
    });

    test('follow a saved link and a deleted page without a reload', () async {
      final (repo, api) = await loaded([
        page('a'),
        page('b'),
        page('c', doc: linkTo('b')),
      ]);
      expect(repo.relatedArticles(repo.articleById('b')!).map((a) => a.id), [
        'c',
      ]);

      api.saved = page('a', doc: linkTo('b'));
      await repo.saveEdit(
        'a',
        title: 'Page a',
        doc: linkTo('b'),
        spaceId: 'Docs',
      );
      expect(repo.relatedArticles(repo.articleById('b')!).map((a) => a.id), [
        'c',
        'a',
      ]);

      // The link is taken out again: the index forgets it.
      api.saved = page('c');
      await repo.saveEdit('c', title: 'Page c', doc: '{}', spaceId: 'Docs');
      expect(repo.relatedArticles(repo.articleById('b')!).map((a) => a.id), [
        'a',
      ]);

      await repo.deleteArticle('a');
      expect(repo.relatedArticles(repo.articleById('b')!), isEmpty);
    });

    test('the cache moves its revision on with every change', () async {
      final (repo, api) = await loaded([page('a'), page('b', sortOrder: 1)]);
      final before = repo.revision;
      await repo.reorder(['b', 'a']);
      expect(repo.revision, greaterThan(before));
    });

    test('an unreadable document links nowhere', () {
      expect(
        KnowledgeRepository.linkedDocIds('{ "smartlink" not json'),
        isEmpty,
      );
      expect(KnowledgeRepository.linkedDocIds(null), isEmpty);
    });
  });

  group('favourites and recent pages', () {
    test('come from the server, and only name pages still here', () async {
      final (repo, _) = await loaded(
        [page('a'), page('b')],
        marks: {
          'starred': [
            {'id': 'b', 'at': '2026-10-10T10:00:00Z'},
            {'id': 'gone', 'at': '2026-10-09T10:00:00Z'},
          ],
          'recent': [
            {'id': 'a', 'at': '2026-10-11T10:00:00Z'},
          ],
        },
      );
      expect(repo.starred.map((a) => a.id), ['b']);
      expect(repo.recent.map((a) => a.id), ['a']);
      expect(repo.isStarred('b'), isTrue);
    });

    test('starring shows at once and goes back when refused', () async {
      final (repo, api) = await loaded([page('a')]);
      api.failPut = true;

      final pending = repo.setStarred('a', starred: true);
      expect(repo.isStarred('a'), isTrue);
      await expectLater(pending, throwsA(isA<ApiFailure>()));
      expect(repo.isStarred('a'), isFalse);
    });

    test('opening a page puts it first in the recent list', () async {
      final (repo, api) = await loaded([page('a'), page('b')]);
      await repo.recordView('a');
      await repo.recordView('b');
      await repo.recordView('a');
      expect(repo.recent.map((a) => a.id), ['a', 'b']);
      expect(api.calls.where((c) => c.$1 == 'post').length, 3);
    });

    test(
      'an old server without the endpoint leaves both lists empty',
      () async {
        final (repo, _) = await loaded([page('a')]);
        expect(repo.starred, isEmpty);
        expect(repo.recent, isEmpty);
      },
    );
  });

  group('recently changed', () {
    test('newest first, narrowed to a space', () async {
      final (repo, _) = await loaded([
        page('old', updatedAt: '2026-01-01T00:00:00Z'),
        page('new', updatedAt: '2026-10-01T00:00:00Z'),
        page('elsewhere', space: 'Other', updatedAt: '2026-10-05T00:00:00Z'),
      ]);
      expect(repo.recentlyUpdated().map((a) => a.id), [
        'elsewhere',
        'new',
        'old',
      ]);
      expect(repo.recentlyUpdated(spaceId: 'Docs').map((a) => a.id), [
        'new',
        'old',
      ]);
    });
  });

  group('addresses', () {
    test('every view has its own address', () {
      expect(const KnowledgeHomeLocation().path, '/knowledge');
      expect(
        const KnowledgeSpaceLocation('Team Wiki').path,
        '/knowledge/spaces/Team%20Wiki',
      );
      expect(const KnowledgeArticleLocation('a1').path, '/knowledge/a1');
      expect(const KnowledgeEditLocation('a1').path, '/knowledge/a1/edit');
      expect(
        const KnowledgeHistoryLocation('a1').path,
        '/knowledge/a1/history',
      );
      expect(
        const KnowledgeHistoryLocation('a1', version: 3).path,
        '/knowledge/a1/history?v=3',
      );
      expect(const KnowledgeNewLocation().path, '/knowledge/new');
      expect(
        const KnowledgeNewLocation(spaceId: 'Docs', parentId: 'a1').path,
        '/knowledge/new?space=Docs&parent=a1',
      );
    });
  });
}

class _Api implements ApiClient {
  _Api(this.pages);

  final List<Map<String, dynamic>> pages;
  Map<String, dynamic>? marks;

  /// What the server answers a save or a move with.
  Map<String, dynamic>? saved;
  bool failPut = false;
  final List<(String, String, Object?)> calls = [];

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
      '/api/v1/articles/marks' when marks != null => marks,
      _ => throw ApiFailure('not faked: $path'),
    };
  }

  @override
  Future<({dynamic data, String? Function(String name) header})> getWithHeaders(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    calls.add(('get', path, query));
    return (data: pages, header: (String _) => null);
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add(('put', path, body));
    if (failPut) throw ApiFailure('refused');
    return null;
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    calls.add(('post', path, body));
    return null;
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async {
    calls.add(('patch', path, body));
    return saved;
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    calls.add(('delete', path, body));
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
