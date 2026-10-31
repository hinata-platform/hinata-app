import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/features/issues/attachments/attachments_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../support/recording_fake.dart';

/// HIN-180: a PDF that needs a password carries a lock on its card in the
/// file list, so nobody has to open it to find out.
void main() {
  test('the flag comes from the server, and only a true makes it', () {
    IssueAttachment parse(Object? flag) => IssueAttachment.fromJson({
      'id': 'a1',
      'fileName': 'x.pdf',
      'passwordProtected': ?flag,
    });
    expect(parse(true).passwordProtected, isTrue);
    expect(parse(null).passwordProtected, isFalse);
    expect(parse('yes').passwordProtected, isFalse);
  });

  testWidgets('only the protected PDF wears a lock, and says what it means', (
    tester,
  ) async {
    final events = StreamController<List<int>>();
    addTearDown(events.close);
    final issues = FakeIssueRepository()
      ..answer<Stream<List<int>>>(#attachmentEventStream, events.stream);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IssueRepository>.value(value: issues),
          RepositoryProvider<ApiClient>.value(value: FakeApiClient()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AttachmentsSection(
                issueId: 'i1',
                initial: [
                  IssueAttachment(
                    id: 'a1',
                    fileName: 'secret.pdf',
                    size: 10,
                    contentType: 'application/pdf',
                    passwordProtected: true,
                  ),
                  IssueAttachment(id: 'a2', fileName: 'open.zip', size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final lock = find.byIcon(LucideIcons.lock);
    expect(lock, findsOneWidget);
    // On the secret file's card, not the other one.
    final card = find.ancestor(of: lock, matching: find.byType(Stack)).first;
    expect(
      find.descendant(of: card, matching: find.text('secret.pdf')),
      findsOneWidget,
    );
    expect(
      find.byTooltip('issues.attachments.passwordProtected'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
