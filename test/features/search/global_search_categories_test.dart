import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/search_api.dart';
import 'package:hinata/core/repositories/search_repository.dart';
import 'package:hinata/core/storage/app_storage.dart';
import 'package:hinata/features/board/board_links.dart';
import 'package:hinata/features/search/global_search_controller.dart';
import 'package:hinata/features/search/global_search_dialog.dart';
import 'package:hinata/features/search/search_hit_mapper.dart';
import 'package:hinata/features/search/search_models.dart';
import 'package:hinata/features/teams/team_widgets.dart' show teamHueColor;
import 'package:shared_preferences/shared_preferences.dart';

/// The palette after HIN-165: every area of the app is a category, and every
/// hit leads to exactly the thing it names.
///
/// Widget tests render raw i18n keys, so nothing here asserts on copy.
void main() {
  /// One hit per category and kind, with the link the server hands out.
  final hits = <String, Map<String, dynamic>>{
    'issue': {'category': 'ISSUES', 'id': 'i1', 'route': '/issues/i1'},
    'comment': {
      'category': 'COMMENTS',
      'id': 'c1',
      'route': '/issues/i1?comment=c1',
      'issueId': 'i1',
      'authorName': 'Mia Berger',
    },
    'project': {
      'category': 'PROJECTS',
      'id': 'p1',
      'route': '/issues?projectId=p1',
    },
    'team': {
      'category': 'TEAMS',
      'id': 't1',
      'route': '/teams/t1',
      'key': 'EVT',
      'hue': 200,
    },
    'person': {
      'category': 'PEOPLE',
      'id': 'u1',
      'route': '/people/u1',
      'username': 'mia',
    },
    'board': {
      'category': 'BOARDS',
      'id': 'b1',
      'route': '/boards/b1',
      'kind': 'BOARD',
    },
    'sprint': {
      'category': 'BOARDS',
      'id': 's1',
      'route': '/boards/b1?sprint=s1',
      'kind': 'SPRINT',
    },
    'article': {
      'category': 'DOCS',
      'id': 'k1',
      'route': '/knowledge/k1',
      'kind': 'ARTICLE',
    },
    'space': {
      'category': 'DOCS',
      'id': 'sp1',
      'route': '/knowledge/spaces/Handbuch%20Verein',
      'kind': 'SPACE',
    },
    'attachment': {
      'category': 'ATTACHMENTS',
      'id': 'a1',
      'route': '/issues/i1?attachment=a1',
      'contentType': 'application/pdf',
      'size': 2048,
    },
    'event': {
      'category': 'SHIFTS',
      'id': 'e1',
      'route': '/shifts/events/e1',
      'kind': 'EVENT',
      'startsAt': '2026-10-24T12:00:00Z',
      'endsAt': '2026-10-24T18:00:00Z',
      'location': 'Halle 3',
    },
    'shift': {
      'category': 'SHIFTS',
      'id': 'sh1',
      'route': '/shifts/events/e1?shift=sh1',
      'kind': 'SHIFT',
      'cancelled': true,
    },
    'entry': {
      'category': 'TIME',
      'id': 'te1',
      'route': '/time/calendar?date=2026-10-19&entry=te1',
      'kind': 'ENTRY',
      'from': '2026-10-19',
      'minutes': 90,
    },
    'timesheet': {
      'category': 'TIME',
      'id': 'ts1',
      'route': '/time/timesheet?date=2026-10-19&project=p1',
      'kind': 'TIMESHEET',
      'from': '2026-10-19',
      'to': '2026-10-25',
      'status': 'SUBMITTED',
    },
    'request': {
      'category': 'ABSENCES',
      'id': 'r1',
      'route': '/time/absences?scope=requests&request=r1',
      'kind': 'REQUEST',
      'from': '2026-10-19',
      'to': '2026-10-23',
      'status': 'APPROVED',
      'hue': 155,
    },
    'absenceType': {
      'category': 'ABSENCES',
      'id': 'ty1',
      'route': '/time/absences?scope=requests&type=ty1',
      'kind': 'TYPE',
    },
    'budget': {
      'category': 'BILLING',
      'id': 'bu1',
      'route': '/projects/p1/settings?section=timeTracking',
      'kind': 'BUDGET',
      'projectKey': 'SOF',
      'projectColor': '#AEC6F4',
    },
    'rate': {
      'category': 'BILLING',
      'id': 'ra1',
      'route': '/time/rates?rate=ra1',
      'kind': 'RATE',
      'rateLevel': 'PROJECT',
      'rateKind': 'COST',
      'amountCents': 9500,
      'currency': 'EUR',
      'from': '2026-01-01',
    },
  };

  group('the wire', () {
    test('asks for revision 2, so people link to their profile', () async {
      final api = _RecordingApi(<String, dynamic>{
        'groups': <dynamic>[],
        'counts': <String, dynamic>{},
      });
      await SearchRepository(api).search(query: 'mia', scope: 'people');
      final (path, query) = api.calls.single;
      expect(path, '/api/v1/search');
      expect(query, containsPair('v', 2));
      expect(query, containsPair('scope', 'people'));
      expect(query, containsPair('q', 'mia'));
    });

    test('reads the new fields and the capped counts', () {
      final response = SearchApiResponse.fromJson({
        'groups': [
          {
            'category': 'SHIFTS',
            'items': [hits['event']],
          },
        ],
        'counts': {'SHIFTS': 100, 'TEAMS': 3},
        'cappedCounts': ['SHIFTS'],
      });
      final hit = response.groups.single.items.single;
      expect(hit.kind, 'EVENT');
      expect(hit.location, 'Halle 3');
      expect(hit.startsAt, isNotNull);
      expect(response.cappedCounts, {'SHIFTS'});
    });

    test('a rate reads its level and kind from their own fields', () {
      final hit = SearchApiHit.fromJson(hits['rate']!);
      expect(hit.rateLevel, 'PROJECT');
      expect(hit.rateKind, 'COST');
      expect(hit.type, isNull);
      expect(hit.status, isNull);
    });

    test('a team hit wears its own colour', () {
      final entry = mapSearchHit(
        SearchApiHit.fromJson({'title': 'Events', ...hits['team']!}),
        _labels(),
      );
      expect(entry.leadingColor, teamHueColor(200));
    });

    test('a group says whether there is more', () {
      final response = SearchApiResponse.fromJson({
        'groups': [
          {'category': 'TEAMS', 'items': <dynamic>[], 'more': true},
          {'category': 'PEOPLE', 'items': <dynamic>[]},
        ],
      });
      expect(response.groups.first.more, isTrue);
      expect(response.groups.last.more, isNull);
    });

    test('a response from before HIN-165 still reads', () {
      final response = SearchApiResponse.fromJson({
        'groups': [],
        'counts': {'ISSUES': 4},
      });
      expect(response.cappedCounts, isEmpty);
      expect(response.counts, {'ISSUES': 4});
    });
  });

  group('categories on offer', () {
    test('a module that is off offers no category', () {
      final none = availableSearchCats(const SearchModules());
      expect(
        none,
        isNot(
          anyOf(
            contains(SearchCat.shifts),
            contains(SearchCat.absences),
            contains(SearchCat.billing),
          ),
        ),
      );
      // Time entries are searchable everywhere, so the chip always is.
      expect(none, contains(SearchCat.time));

      final all = availableSearchCats(
        const SearchModules(
          advancedTime: true,
          absences: true,
          billing: true,
          shifts: true,
        ),
      );
      expect(all, SearchCat.values);
    });

    test('a category this app does not know is skipped', () {
      expect(searchCatFromName('WIDGETS'), isNull);
      expect(searchCatFromName('shifts'), SearchCat.shifts);
    });
  });

  group('the controller', () {
    late AppStorage storage;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      storage = AppStorage(
        await SharedPreferences.getInstance(),
        const FlutterSecureStorage(),
      );
    });

    testWidgets('counts past the ceiling read 99+', (tester) async {
      final repo = _FakeSearch(
        SearchApiResponse(
          groups: const [],
          counts: const {'SHIFTS': 100, 'TEAMS': 3},
          cappedCounts: const {'SHIFTS'},
        ),
      );
      final controller = GlobalSearchController(
        repository: repo,
        storage: storage,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _withContext((context) {
          controller.load(
            labels: SearchLabels.of(context),
            commands: const [],
            modules: const SearchModules(shifts: true),
          );
        }),
      );
      await tester.pump();
      expect(controller.countLabel(SearchCat.shifts), '99+');
      expect(controller.countLabel(SearchCat.teams), '3');
      // A count the server ran out of time for says nothing, not zero.
      expect(controller.countLabel(SearchCat.comments), isNull);
    });

    testWidgets('hits of a module that is off, or unknown, are not shown', (
      tester,
    ) async {
      final repo = _FakeSearch(
        SearchApiResponse.fromJson({
          'groups': [
            {
              'category': 'SHIFTS',
              'items': [hits['event']],
            },
            {
              'category': 'WIDGETS',
              'items': [
                {'category': 'WIDGETS', 'id': 'w', 'route': '/w'},
              ],
            },
            {
              'category': 'TEAMS',
              'items': [hits['team']],
            },
          ],
          'counts': <String, dynamic>{},
        }),
      );
      final controller = GlobalSearchController(
        repository: repo,
        storage: storage,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _withContext((context) {
          controller.load(labels: SearchLabels.of(context), commands: const []);
        }),
      );
      controller.setQuery('fest');
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.groups.map((g) => g.cat), [SearchCat.teams]);
    });

    testWidgets('a server without the flag: a full group offers more', (
      tester,
    ) async {
      final repo = _FakeSearch(
        SearchApiResponse.fromJson({
          'groups': [
            {
              'category': 'TEAMS',
              'items': [
                for (var i = 0; i < 5; i++)
                  {'category': 'TEAMS', 'id': 't$i', 'route': '/teams/t$i'},
              ],
            },
            {
              'category': 'PEOPLE',
              'items': [hits['person']],
            },
          ],
          'counts': <String, dynamic>{},
        }),
      );
      final controller = await _loaded(tester, repo, storage);
      controller.setQuery('a');
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.groups.first.more, isTrue);
      expect(controller.groups.last.more, isFalse);
    });

    testWidgets('the server says whether there is more, not the count', (
      tester,
    ) async {
      final repo = _FakeSearch(
        SearchApiResponse.fromJson({
          'groups': [
            {
              // Exactly five, and nothing beyond them.
              'category': 'COMMENTS',
              'more': false,
              'items': [
                for (var i = 0; i < 5; i++)
                  {'category': 'COMMENTS', 'id': 'c$i', 'route': '/issues/i'},
              ],
            },
            {
              'category': 'PEOPLE',
              'more': true,
              'items': [hits['person']],
            },
          ],
          'counts': <String, dynamic>{},
        }),
      );
      final controller = await _loaded(tester, repo, storage);
      controller.setQuery('a');
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.groups.first.more, isFalse);
      expect(controller.groups.last.more, isTrue);
    });

    testWidgets('typing waits for a pause and drops what it superseded', (
      tester,
    ) async {
      final repo = _FakeSearch(
        SearchApiResponse(groups: const [], counts: const {}),
      );
      final controller = await _loaded(tester, repo, storage);
      final opened = repo.calls.length;
      for (final text in ['s', 'sc', 'sch', 'schi']) {
        controller.setQuery(text);
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(repo.calls, hasLength(opened));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, hasLength(opened + 1));
      expect(repo.calls.last.query, 'schi');

      // A newer search aborts the one still on its way.
      repo.hold = true;
      controller.setQuery('schic');
      await tester.pump(const Duration(milliseconds: 300));
      final first = repo.calls.last.cancelToken!;
      controller.setQuery('schich');
      await tester.pump(const Duration(milliseconds: 300));
      expect(first.isCancelled, isTrue);
      expect(repo.calls.last.cancelToken!.isCancelled, isFalse);
      repo.release();
      await tester.pump();
    });

    testWidgets('tabbing through the chips asks only for the last one', (
      tester,
    ) async {
      final repo = _FakeSearch(
        SearchApiResponse(groups: const [], counts: const {}),
      );
      final controller = await _loaded(tester, repo, storage);
      final opened = repo.calls.length;
      for (var i = 0; i < 4; i++) {
        controller.cycleScope(true);
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.calls, hasLength(opened + 1));
      expect(repo.calls.last.scope, controller.scope!.name);
    });
  });

  group('a hit navigates to its route', () {
    for (final MapEntry(key: name, value: json) in hits.entries) {
      testWidgets(name, (tester) async {
        final hit = SearchApiHit.fromJson({'title': name, ...json});
        // A board's old address is turned into its own before going.
        final expected = currentBoardLink(hit.route);
        final storage = await _storage();
        final controller = GlobalSearchController(
          repository: _FakeSearch(
            SearchApiResponse(
              groups: [
                SearchApiGroup(category: hit.category, items: [hit]),
              ],
              counts: const {},
            ),
          ),
          storage: storage,
        );
        final router = _router();
        addTearDown(router.dispose);
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        // Open the palette the way the app does, minus the app's blocs.
        final context = tester.element(find.text('/'));
        controller.load(
          labels: SearchLabels.of(context),
          commands: const [],
          modules: const SearchModules(
            advancedTime: true,
            absences: true,
            billing: true,
            shifts: true,
          ),
        );
        showGeneralDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'search',
          barrierColor: Colors.transparent,
          pageBuilder: (_, _, _) => GlobalSearchDialog(controller: controller),
        );
        await tester.pump();
        await tester.enterText(find.byType(TextField), name);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 500));

        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();

        expect(router.state.uri.toString(), expected);
        expect(find.text('at $expected'), findsOneWidget);
        expect(find.byType(GlobalSearchDialog), findsNothing);
        controller.dispose();
      });
    }
  });

  group('every width and text size', () {
    for (final width in const [320.0, 390.0, 768.0, 1024.0, 1440.0]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets('${width.toInt()} px at ${(scale * 100).toInt()} %', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final byCategory = <String, List<SearchApiHit>>{};
          for (final MapEntry(key: name, value: json) in hits.entries) {
            final hit = SearchApiHit.fromJson({
              'title': '$name with a rather long title that has to give way',
              'subtitle': 'and a subtitle that is longer than any phone',
              ...json,
            });
            byCategory.putIfAbsent(hit.category, () => []).add(hit);
          }
          final controller = GlobalSearchController(
            repository: _FakeSearch(
              SearchApiResponse(
                groups: [
                  for (final MapEntry(key: category, value: items)
                      in byCategory.entries)
                    SearchApiGroup(category: category, items: items),
                ],
                counts: const {'SHIFTS': 100},
                cappedCounts: const {'SHIFTS'},
              ),
            ),
            storage: await _storage(),
          );
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () {
                      controller.load(
                        labels: SearchLabels.of(context),
                        commands: const [],
                        modules: const SearchModules(
                          advancedTime: true,
                          absences: true,
                          billing: true,
                          shifts: true,
                        ),
                      );
                      showGeneralDialog<void>(
                        context: context,
                        barrierLabel: 'search',
                        barrierColor: Colors.transparent,
                        pageBuilder: (_, _, _) =>
                            GlobalSearchDialog(controller: controller),
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
          await tester.enterText(find.byType(TextField), 'fest');
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // Every category the server answered is a group of its own.
          expect(controller.groups, hasLength(byCategory.length));
        });
      }
    }
  });
}

Future<AppStorage> _storage() async {
  SharedPreferences.setMockInitialValues({});
  return AppStorage(
    await SharedPreferences.getInstance(),
    const FlutterSecureStorage(),
  );
}

/// Every address a hit can lead to, each showing where it landed.
GoRouter _router() {
  Widget at(GoRouterState state) =>
      Scaffold(body: Center(child: Text('at ${state.uri}')));
  return GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Center(child: Text('/'))),
      ),
      for (final path in [
        '/issues',
        '/issues/:id',
        '/teams/:id',
        '/people/:id',
        '/board/:id',
        '/knowledge/:id',
        '/knowledge/spaces/:space',
        '/shifts/events/:id',
        '/time/calendar',
        '/time/timesheet',
        '/time/absences',
        '/time/rates',
        '/projects/:id/settings',
      ])
        GoRoute(path: path, builder: (_, state) => at(state)),
    ],
  );
}

Widget _withContext(void Function(BuildContext context) run) => MaterialApp(
  home: Builder(
    builder: (context) {
      run(context);
      return const SizedBox.shrink();
    },
  ),
);

Future<GlobalSearchController> _loaded(
  WidgetTester tester,
  SearchRepository repo,
  AppStorage storage,
) async {
  final controller = GlobalSearchController(repository: repo, storage: storage);
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    _withContext((context) {
      controller.load(labels: SearchLabels.of(context), commands: const []);
    }),
  );
  await tester.pump();
  return controller;
}

SearchLabels _labels() => SearchLabels(
  t: (key, [_]) => key,
  day: (date) => '$date',
  time: (date) => '$date',
  duration: (minutes) => '$minutes',
  money: (cents, currency) => '$cents $currency',
  ago: (when) => '$when',
);

class _FakeSearch implements SearchRepository {
  _FakeSearch(this.response);
  final SearchApiResponse response;
  final calls = <({String query, String? scope, CancelToken? cancelToken})>[];

  /// Keeps the answers back until [release], like a slow server.
  bool hold = false;
  final _held = <Completer<void>>[];

  void release() {
    for (final gate in _held) {
      gate.complete();
    }
    _held.clear();
  }

  @override
  Future<SearchApiResponse> search({
    String query = '',
    String? scope,
    bool archived = false,
    CancelToken? cancelToken,
  }) async {
    calls.add((query: query, scope: scope, cancelToken: cancelToken));
    if (hold) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingApi implements ApiClient {
  _RecordingApi(this.response);
  final Object response;
  final List<(String, Map<String, dynamic>?)> calls = [];

  @override
  Future<dynamic> getCancellable(
    String path, {
    Map<String, dynamic>? query,
    required CancelToken cancelToken,
  }) async {
    calls.add((path, query));
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
