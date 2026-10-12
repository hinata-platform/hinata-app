import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/content_models.dart' show ArticleVersion;
import 'package:hinata/core/repositories/article_repository.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/knowledge/data/knowledge_models.dart';
import 'package:hinata/features/knowledge/data/knowledge_repository.dart';
import 'package:hinata/features/knowledge/knowledge_debouncer.dart';
import 'package:hinata/features/knowledge/views/knowledge_history_view.dart';

import '../../support/recording_fake.dart';

void main() {
  testWidgets('the version list fits a narrow phone at double text size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Never called: the list only asks the cache for editor names.
    final api = FakeApiClient();
    final repo = KnowledgeRepository(
      articles: ArticleRepository(api),
      users: UserRepository(api),
      auth: AuthRepository(api),
    );
    final versions = PagedCubit<ArticleVersion>(
      (page, size) async => (
        items: [
          const ArticleVersion(number: 12345, title: 'Page', editorId: 'u1'),
          const ArticleVersion(number: 12344, title: 'Page'),
        ],
        total: 2,
      ),
    );
    addTearDown(versions.close);
    await versions.load();

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: KnowledgeHistoryView(
                repo: repo,
                article: const KbArticle(
                  id: 'a',
                  spaceId: 'Docs',
                  parentId: null,
                  title: 'Page',
                  icon: 'file-text',
                  authorId: 'u1',
                  labels: [],
                  body: '',
                ),
                versions: versions,
                loadVersion: (n) async =>
                    ArticleVersion(number: n, title: 'Page'),
                selected: null,
                onSelect: (_) {},
                wide: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('knowledge.history.current'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // The widget tester's clock is a fake one, so a pump moves the timers on.
  group('KbDebouncer', () {
    testWidgets('runs the last call once typing pauses', (tester) async {
      final debouncer = KbDebouncer();
      addTearDown(debouncer.dispose);
      final runs = <String>[];
      debouncer.run(() => runs.add('s'));
      await tester.pump(const Duration(milliseconds: 100));
      debouncer.run(() => runs.add('se'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(runs, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(runs, ['se']);
    });

    testWidgets('a call to run now drops the waiting one', (tester) async {
      final debouncer = KbDebouncer();
      addTearDown(debouncer.dispose);
      final runs = <String>[];
      debouncer.run(() => runs.add('typed'));
      debouncer.run(() => runs.add('cleared'), immediately: true);
      await tester.pump(const Duration(seconds: 1));
      expect(runs, ['cleared']);
    });

    testWidgets('nothing runs after dispose', (tester) async {
      final debouncer = KbDebouncer();
      var ran = false;
      debouncer.run(() => ran = true);
      debouncer.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(ran, isFalse);
    });
  });
}
