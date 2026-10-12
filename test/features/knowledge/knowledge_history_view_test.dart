import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/blocs/paged_cubit.dart';
import 'package:hinata/core/models/content_models.dart' show ArticleVersion;
import 'package:hinata/core/repositories/article_repository.dart';
import 'package:hinata/core/repositories/auth_repository.dart';
import 'package:hinata/core/repositories/user_repository.dart';
import 'package:hinata/features/knowledge/data/knowledge_models.dart';
import 'package:hinata/features/knowledge/data/knowledge_repository.dart';
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
}
