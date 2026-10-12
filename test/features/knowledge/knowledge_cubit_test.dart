import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/knowledge/data/knowledge_models.dart';
import 'package:hinata/features/knowledge/knowledge_cubit.dart';
import 'package:hinata/features/knowledge/knowledge_state.dart';

import '../../support/recording_fake.dart';

Issue _issue(String key) => Issue(
  id: 'id-$key',
  projectId: 'p1',
  readableId: key,
  title: key,
  state: 'Open',
);

/// The Knowledge Base screen writes pages and spaces through this cubit and
/// resolves its smart links with it.
void main() {
  late FakeKnowledgeRepository knowledge;
  late FakeIssueRepository issues;
  late KnowledgeCubit cubit;

  setUp(() {
    knowledge = FakeKnowledgeRepository();
    issues = FakeIssueRepository();
    cubit = KnowledgeCubit(knowledge, issues);
    // The cache hands the fetch straight on, as the real one does the first
    // time; whether it fetches again is the repository's test.
    knowledge.answerWith(
      #linkIssues,
      (call) =>
          (call.positionalArguments.single as Future<List<Issue>> Function())(),
    );
    knowledge.answerWith(#users, (_) => const <KbUser>[]);
  });
  tearDown(() => cubit.close());

  test('the screen renders from the shared cache it was given', () {
    expect(cubit.store, same(knowledge));
  });

  test('loading opens the cache, then resolves issues and names', () async {
    knowledge.answer<void>(#init, null);
    knowledge.answerWith(
      #users,
      (_) => const [KbUser(id: 'u1', name: 'Ada', title: '', hue: 1)],
    );
    issues.answer<List<Issue>>(#allIssues, [_issue('HIN-1')]);

    await cubit.load();

    expect(knowledge.calls.map((c) => c.memberName), [
      #init,
      #users,
      #linkIssues,
    ]);
    expect(cubit.state.status, KnowledgeStatus.ready);
    expect(cubit.state.issuesByReadable.keys, ['HIN-1']);
    // Names come from the directory the cache already holds, not a new call.
    expect(cubit.state.userNames, {'u1': 'Ada'});
  });

  test(
    'a cache that fails to load says so, and issues are not asked',
    () async {
      knowledge.fail(#init, failure);

      await cubit.load();

      expect(cubit.state.status, KnowledgeStatus.failure);
      expect(issues.calls, isEmpty);
      expect(
        knowledge.calls.map((c) => c.memberName),
        isNot(contains(#linkIssues)),
      );
    },
  );

  test('pages stay readable when the issues do not load', () async {
    knowledge.answer<void>(#init, null);
    issues.fail(#allIssues, failure);

    await cubit.load();

    expect(cubit.state.status, KnowledgeStatus.ready);
    expect(cubit.state.issuesByReadable, isEmpty);
  });

  test('a write moves the revision on, so the views rebuild', () async {
    knowledge.answer<void>(#deleteArticle, null);
    final before = cubit.state.revision;

    await cubit.deleteArticle('a1');

    expect(cubit.state.revision, before + 1);
  });

  test('shifting a page reorders its siblings around it', () async {
    KbArticle page(String id, int order) => KbArticle(
      id: id,
      spaceId: 's1',
      parentId: 'p',
      title: id,
      icon: 'file-text',
      authorId: 'me',
      labels: const [],
      body: '',
      sortOrder: order,
    );
    final siblings = [page('a', 0), page('b', 1), page('c', 2)];
    knowledge.answerWith(#articleById, (_) => siblings[2]);
    knowledge.answerWith(#childrenOf, (_) => siblings);
    knowledge.answer<void>(#reorder, null);

    await cubit.shift('c', -1);

    expect(knowledge.calls.last.memberName, #reorder);
    expect(knowledge.calls.last.positionalArguments, [
      ['a', 'c', 'b'],
    ]);
  });

  test('the first page cannot move further up', () async {
    const first = KbArticle(
      id: 'a',
      spaceId: 's1',
      parentId: null,
      title: 'a',
      icon: 'file-text',
      authorId: 'me',
      labels: [],
      body: '',
    );
    knowledge.answerWith(#articleById, (_) => first);
    knowledge.answerWith(#rootsInSpace, (_) => [first]);

    await cubit.shift('a', -1);

    expect(knowledge.calls.map((c) => c.memberName), isNot(contains(#reorder)));
  });

  test('an issue is found by its exact key, not by a longer one', () async {
    issues.answer<({List<Issue> issues, int total})>(#issues, (
      issues: [_issue('HIN-10'), _issue('HIN-1')],
      total: 2,
    ));

    expect((await cubit.findIssue('HIN-1'))?.readableId, 'HIN-1');
    expect(issues.only.namedArguments[#query], 'HIN-1');
    expect(issues.only.namedArguments[#size], 20);
    expect(await cubit.findIssue('HIN-2'), isNull);
  });

  test('page and space writes go to the cache with their arguments', () async {
    const space = KbSpace(
      id: 's1',
      key: 'S',
      name: 'Space',
      hue: 40,
      icon: 'book',
      desc: '',
    );
    knowledge.answer<void>(#deleteArticle, null);
    knowledge.answer<void>(#deleteSpace, null);
    knowledge.answer<KbSpace>(#createSpace, space);

    await cubit.deleteArticle('a1');
    await cubit.deleteSpace('s1');
    expect(
      await cubit.createSpace(
        name: 'Space',
        icon: 'book',
        hue: 40,
        description: 'd',
      ),
      same(space),
    );

    expect(knowledge.calls[0].positionalArguments, ['a1']);
    expect(knowledge.calls[1].positionalArguments, ['s1']);
    expect(knowledge.calls[2].namedArguments, {
      #name: 'Space',
      #icon: 'book',
      #hue: 40,
      #description: 'd',
    });
  });

  test('moves, places, creates and saves pass their failure back', () async {
    for (final member in [
      #moveArticle,
      #placeArticle,
      #createArticle,
      #saveEdit,
    ]) {
      knowledge.fail(member, failure);
    }

    await expectLater(
      cubit.moveArticle('a1', parentId: 'a0', spaceId: 's1'),
      throwsA(same(failure)),
    );
    await expectLater(
      cubit.placeArticle('a1', projectId: 'p1'),
      throwsA(same(failure)),
    );
    await expectLater(
      cubit.createArticle(title: 't', doc: '{}', spaceId: 's1', teamId: 't1'),
      throwsA(same(failure)),
    );
    await expectLater(
      cubit.saveEdit('a1', title: 't', doc: '{}', spaceId: 's1'),
      throwsA(same(failure)),
    );

    expect(knowledge.calls[0].namedArguments, {
      #parentId: 'a0',
      #spaceId: 's1',
    });
    expect(knowledge.calls[1].namedArguments, {
      #projectId: 'p1',
      #teamId: null,
    });
    expect(knowledge.calls[2].namedArguments, {
      #title: 't',
      #doc: '{}',
      #spaceId: 's1',
      #parentId: null,
      #projectId: null,
      #teamId: 't1',
      #labels: const <String>[],
    });
    expect(knowledge.calls[3].positionalArguments, ['a1']);
    expect(knowledge.calls[3].namedArguments, {
      #title: 't',
      #doc: '{}',
      #spaceId: 's1',
      #labels: null,
    });
  });
}
