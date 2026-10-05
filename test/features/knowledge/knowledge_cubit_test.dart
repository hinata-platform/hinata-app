import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/knowledge/data/knowledge_models.dart';
import 'package:hinata/features/knowledge/knowledge_cubit.dart';

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
  late FakeUserRepository users;
  late KnowledgeCubit cubit;

  setUp(() {
    knowledge = FakeKnowledgeRepository();
    issues = FakeIssueRepository();
    users = FakeUserRepository();
    cubit = KnowledgeCubit(knowledge, issues, users);
  });
  tearDown(() => cubit.close());

  test('the screen renders from the shared cache it was given', () {
    expect(cubit.store, same(knowledge));
  });

  test('link targets are every issue, then the directory', () async {
    final all = [_issue('HIN-1')];
    final directory = <DirectoryUser>[];
    issues.answer<List<Issue>>(#allIssues, all);
    users.answer<List<DirectoryUser>>(#users, directory);

    final targets = await cubit.linkTargets();

    expect(targets.issues, same(all));
    expect(targets.users, same(directory));
    expect(issues.only.memberName, #allIssues);
    expect(users.only.memberName, #users);
  });

  test('without issues the directory is not asked', () async {
    issues.fail(#allIssues, failure);

    await expectLater(cubit.linkTargets(), throwsA(same(failure)));
    expect(users.calls, isEmpty);
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
    });
    expect(knowledge.calls[3].positionalArguments, ['a1']);
    expect(knowledge.calls[3].namedArguments, {
      #title: 't',
      #doc: '{}',
      #spaceId: 's1',
    });
  });

  test('init overlays the cache', () async {
    knowledge.answer<void>(#init, null);

    await cubit.init();

    expect(knowledge.only.memberName, #init);
  });
}
