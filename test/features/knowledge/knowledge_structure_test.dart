import 'dart:async';
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

    test('reset during a reload keeps the cache empty and init then loads the '
        'new account', () async {
      final (repo, api) = await loaded([page('a')]);
      final gate = Completer<void>();
      api.gate = gate;
      final pending = repo.reload();

      repo.reset();
      api.pages
        ..clear()
        ..add(page('c'));
      gate.complete();
      await pending;

      // The answer of the account that left is dropped, and the cache
      // still knows it has to load.
      expect(repo.articles, isEmpty);
      api.gate = null;
      await repo.init();
      expect(repo.articles.map((a) => a.id), ['c']);
    });

    test('link targets fetched before a reset answer nothing', () async {
      final (repo, _) = await loaded([page('a')]);
      final gate = Completer<List<Issue>>();
      final pending = repo.linkIssues(() => gate.future);
      repo.reset();
      gate.complete([
        const Issue(
          id: 'i1',
          projectId: 'p1',
          readableId: 'OLD-1',
          title: 'old',
          state: 'Open',
        ),
      ]);
      expect(await pending, isEmpty);
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

    test(
      'the same query on an unchanged cache is not searched again',
      () async {
        final (repo, _) = await loaded([page('a')]);
        final first = repo.search('page');
        expect(repo.search('page'), same(first));
        await repo.reorder(['a']);
        expect(repo.search('page'), isNot(same(first)));
      },
    );

    test('an excerpt is made once per query and change of the cache', () async {
      final (repo, _) = await loaded([
        {...page('a'), 'content': 'Some words around a needle in the text'},
      ]);
      final first = repo.searchExcerpt('a', 'needle');
      expect(first, contains('needle'));
      expect(repo.searchExcerpt('a', 'needle'), same(first));
      expect(repo.searchExcerpt('a', 'words'), isNot(same(first)));
      final again = repo.searchExcerpt('a', 'needle');
      await repo.reorder(['a']);
      expect(repo.searchExcerpt('a', 'needle'), isNot(same(again)));
      expect(repo.searchExcerpt('a', 'needle'), again);
    });

    test('a large knowledge base finds the same with prepared text', () async {
      // Enough text to prepare the search in an isolate during the load.
      final filler = 'Lorem ipsum ' * 400;
      List<Map<String, dynamic>> pages() => [
        for (var i = 0; i < 20; i++)
          {
            ...page('p$i', tags: [if (i == 3) 'Setup']),
            'content': i.isEven ? '$filler NEEDLE\n  here' : filler,
          },
      ];
      final (large, api) = await loaded(pages());
      final expected = [for (var i = 0; i < 20; i += 2) 'p$i'];
      expect(large.search('needle here').map((a) => a.id), expected);
      expect(large.search('setup').map((a) => a.id), ['p3']);

      // A changed page drops its prepared text and is read anew.
      api.saved = {...page('p1'), 'content': 'needle here now'};
      await large.saveEdit('p1', title: 'Page p1', doc: '{}', spaceId: 'Docs');
      expect(large.search('needle here').map((a) => a.id), [
        ...expected.take(1),
        'p1',
        ...expected.skip(1),
      ]);
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

    test('many linking pages are read off the UI thread alike', () async {
      // Enough document text to go to an isolate.
      final filler = 'x' * 2000;
      final (repo, _) = await loaded([
        page('target'),
        for (var i = 0; i < 40; i++)
          page(
            'p$i',
            doc: linkTo(
              'target',
            ).replaceFirst('"label":"x"', '"label":"$filler"'),
          ),
      ]);
      expect(repo.relatedArticles(repo.articleById('target')!), hasLength(40));
      expect(repo.relatedArticles(repo.articleById('p7')!).map((a) => a.id), [
        'target',
      ]);
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

  /// Holds the page list back until completed, for a reset mid-load.
  Completer<void>? gate;

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
    // The answer is what the server held when asked, not when it arrives.
    final answer = [...pages];
    await gate?.future;
    return (data: answer, header: (String _) => null);
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
