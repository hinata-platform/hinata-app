import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/content_models.dart';
import 'package:hinata/core/models/core_models.dart';
import 'package:hinata/core/models/team_models.dart';
import 'package:hinata/core/repositories/article_repository.dart';
import 'package:hinata/core/repositories/team_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/core/theme/app_colors.dart';
import 'package:hinata/features/knowledge/team_pages_picker.dart';
import 'package:hinata/features/teams/team_member_modals.dart';
import 'package:hinata/features/teams/team_members_cubit.dart';
import 'package:hinata/features/teams/team_modal_kit.dart';

/// HIN-129: the knowledge base inside team roles. Adding and managing members
/// carries a knowledge grant; Team-Admins read every page anyway, so their
/// picker is shut; the page picker counts a page's subtree as included.
void main() {
  setUp(() => AppColors.brightness = Brightness.light);

  const team = Team(
    id: 't1',
    key: 'OPS',
    name: 'Ops',
    members: [
      TeamMembership(userId: 'a', role: TeamRole.admin),
      TeamMembership(userId: 'b', role: TeamRole.admin),
    ],
  );

  group('TeamRepository', () {
    test('adding members sends the knowledge grant', () async {
      final api = _RecordingApiClient()..response = _teamJson;
      await TeamRepository(api).addTeamMembers(
        't1',
        ['u1'],
        role: TeamRole.member,
        access: const ProjectAccess.none(),
        knowledge: KnowledgeAccess.some(const ['p1', 'p2']),
      );

      final (method, path, body) = api.calls.single;
      expect(method, 'post');
      expect(path, '/api/v1/teams/t1/members');
      expect((body! as Map)['knowledge'], {
        'scope': 'SOME',
        'articleIds': ['p1', 'p2'],
      });
    });

    test('adding members without a choice sends NONE', () async {
      final api = _RecordingApiClient()..response = _teamJson;
      await TeamRepository(api).addTeamMembers(
        't1',
        ['u1'],
        role: TeamRole.member,
        access: const ProjectAccess.all(),
      );
      expect((api.calls.single.$3! as Map)['knowledge'], {'scope': 'NONE'});
    });

    test('a membership update leaves knowledge out unless given', () async {
      final api = _RecordingApiClient()..response = _teamJson;
      final repo = TeamRepository(api);

      await repo.updateTeamMembership('t1', 'u1', role: TeamRole.admin);
      expect((api.calls.last.$3! as Map).containsKey('knowledge'), isFalse);

      await repo.updateTeamMembership(
        't1',
        'u1',
        knowledge: const KnowledgeAccess.all(),
      );
      expect(api.calls.last.$1, 'patch');
      expect((api.calls.last.$3! as Map)['knowledge'], {'scope': 'ALL'});
    });
  });

  group('manage member modal', () {
    Future<void> pump(WidgetTester tester, TeamMembership membership) async {
      tester.view
        ..physicalSize = const Size(700, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _RecordingApiClient();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider(
              create: (_) => TeamMembersCubit(
                teams: TeamRepository(api),
                users: UserRepository(api),
              ),
              child: ManageMemberBody(
                articles: ArticleRepository(api),
                team: team,
                membership: membership,
                user: const DirectoryUser(
                  id: 'u1',
                  username: 'u1',
                  displayName: 'Uma',
                ),
                projectsById: const {},
                isSelf: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    InkWell optionOf(WidgetTester tester, String key) => tester.widget<InkWell>(
      find.ancestor(of: find.text(key), matching: find.byType(InkWell)).first,
    );

    testWidgets('an Admin reads every page, so the picker is shut', (
      tester,
    ) async {
      await pump(
        tester,
        const TeamMembership(userId: 'u1', role: TeamRole.admin),
      );

      expect(find.text('teams.knowledge.adminReadsAll'), findsOneWidget);
      expect(optionOf(tester, 'teams.knowledge.none').onTap, isNull);
      expect(optionOf(tester, 'teams.knowledge.all').onTap, isNull);
      expect(optionOf(tester, 'teams.knowledge.some').onTap, isNull);
    });

    testWidgets('a member picks selected pages through a field, not a list', (
      tester,
    ) async {
      await pump(tester, const TeamMembership(userId: 'u1'));

      expect(find.text('teams.knowledge.adminReadsAll'), findsNothing);
      expect(optionOf(tester, 'teams.knowledge.some').onTap, isNotNull);
      expect(find.text('teams.knowledge.choosePages'), findsNothing);

      await tester.ensureVisible(find.text('teams.knowledge.some'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('teams.knowledge.some'));
      await tester.pumpAndSettle();
      expect(find.text('teams.knowledge.choosePages'), findsOneWidget);
    });

    testWidgets('an existing grant shows its page count', (tester) async {
      await pump(
        tester,
        TeamMembership(
          userId: 'u1',
          knowledge: KnowledgeAccess.some(const ['p1', 'p2', 'p3']),
        ),
      );
      expect(find.text('teams.knowledge.pagesPicked'), findsOneWidget);
    });
  });

  group('member list chip', () {
    Future<void> pumpChip(WidgetTester tester, TeamMembership m) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: KnowledgeAccessChip(membership: m)),
          ),
        );

    testWidgets('says none for a member without a grant', (tester) async {
      await pumpChip(tester, const TeamMembership(userId: 'u1'));
      expect(find.text('teams.knowledge.chip'), findsOneWidget);
    });

    test('counts come from the server when the ids are withheld', () {
      // What a viewer who is not Team-Admin of the team receives.
      final other = KnowledgeAccess.fromJson(const {
        'scope': 'SOME',
        'articleIds': <String>[],
        'count': 4,
      });
      expect(other.articleIds, isEmpty);
      expect(other.count, 4);
      // A Team-Admin gets the ids; the count agrees with them.
      expect(KnowledgeAccess.some(const ['a', 'b']).count, 2);
    });
  });

  group('page picker', () {
    const pages = [
      TeamPageRef(id: 'root', title: 'Handbook'),
      TeamPageRef(id: 'child', title: 'Onboarding', parentId: 'root'),
      TeamPageRef(id: 'other', title: 'Runbook'),
    ];

    Future<void> pumpPicker(
      WidgetTester tester,
      List<String> selected, {
      bool truncated = false,
      List<String?>? queries,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TeamPagesPickerPanel(
              loadPages: (query) async {
                queries?.add(query);
                final q = query.toLowerCase();
                return (
                  items: [
                    for (final p in pages)
                      if (q.isEmpty || p.title.toLowerCase().contains(q)) p,
                  ],
                  truncated: truncated,
                );
              },
              selected: selected,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a picked page includes the pages below it', (tester) async {
      await pumpPicker(tester, const ['root']);

      expect(find.text('teams.knowledge.includedVia'), findsOneWidget);
      final child = tester.widget<InkWell>(
        find
            .ancestor(
              of: find.text('Onboarding'),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(child.onTap, isNull);
    });

    testWidgets('search asks the server, once typing pauses', (tester) async {
      final queries = <String?>[];
      await pumpPicker(tester, const [], queries: queries);
      await tester.enterText(find.byType(TextField), 'run');
      await tester.pump();
      // Nothing yet: the question waits for the pause.
      expect(queries, ['']);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(queries, ['', 'run']);
      expect(find.text('Runbook'), findsOneWidget);
      expect(find.text('Handbook'), findsNothing);
    });

    testWidgets('a cut list says so', (tester) async {
      await pumpPicker(tester, const [], truncated: true);
      expect(find.text('teams.knowledge.truncated'), findsOneWidget);
    });

    testWidgets('a grant on a page not in the answer survives the save', (
      tester,
    ) async {
      // A page past the cut: the picker never saw it, and must not drop it.
      late List<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<List<String>>(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: TeamPagesPickerPanel(
                          loadPages: (_) async =>
                              (items: pages, truncated: true),
                          selected: const ['beyond', 'other'],
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('teams.knowledge.apply'));
      await tester.pumpAndSettle();

      expect(result, containsAll(<String>['beyond', 'other']));
    });

    testWidgets('a page missing from the whole team is gone and dropped', (
      tester,
    ) async {
      late List<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<List<String>>(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        body: TeamPagesPickerPanel(
                          loadPages: (_) async =>
                              (items: pages, truncated: false),
                          selected: const ['deleted', 'other'],
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('teams.knowledge.apply'));
      await tester.pumpAndSettle();

      expect(result, ['other']);
    });
  });

  group('ArticleRepository.teamPages', () {
    test('reads the slim endpoint with the search and the cut', () async {
      final api = _RecordingApiClient()
        ..response = [
          {'id': 'a', 'title': 'Handbook', 'sortOrder': 2},
        ]
        ..headers = {'x-truncated': 'true'};

      final answer = await ArticleRepository(
        api,
      ).teamPages('t1', query: ' run ');

      final (method, path, query) = api.calls.single;
      expect(method, 'get');
      expect(path, '/api/v1/teams/t1/pages');
      expect(query, {'q': 'run'});
      expect(answer.truncated, isTrue);
      expect(
        answer.items.single,
        const TeamPageRef(id: 'a', title: 'Handbook', sortOrder: 2),
      );
    });
  });
}

const _teamJson = <String, dynamic>{'id': 't1', 'key': 'OPS', 'name': 'Ops'};

class _RecordingApiClient implements ApiClient {
  final List<(String, String, Object?)> calls = [];
  Object? response;
  Map<String, String> headers = const {};

  @override
  Future<({dynamic data, String? Function(String name) header})> getWithHeaders(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    calls.add(('get', path, query));
    return (data: response, header: (String name) => headers[name]);
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    calls.add(('post', path, body));
    return response;
  }

  @override
  Future<dynamic> patch(String path, {Object? body}) async {
    calls.add(('patch', path, body));
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
