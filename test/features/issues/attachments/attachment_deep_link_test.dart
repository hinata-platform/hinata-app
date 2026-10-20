import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/core/repositories/issue_repository.dart';
import 'package:hinata/features/issues/attachments/attachments_section.dart';

import '../../../support/recording_fake.dart';

/// HIN-165: a search hit for an attachment links to
/// `/issues/:id?attachment=<id>`, and the issue opens that file in the viewer.
/// The route hands the id to the body, the body to the section; what is
/// checked here is the last step, that the section opens exactly that file.
void main() {
  late StreamController<List<int>> events;

  setUp(() => events = StreamController<List<int>>());
  tearDown(() => events.close());

  Future<GlobalKey<AttachmentsSectionState>> pump(WidgetTester tester) async {
    final issues = FakeIssueRepository()
      ..answer<Stream<List<int>>>(#attachmentEventStream, events.stream);
    final key = GlobalKey<AttachmentsSectionState>();
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<IssueRepository>.value(value: issues),
          RepositoryProvider<ApiClient>.value(value: FakeApiClient()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AttachmentsSection(
                key: key,
                issueId: 'i1',
                initial: const [
                  IssueAttachment(id: 'a1', fileName: 'first.zip', size: 10),
                  IssueAttachment(id: 'a2', fileName: 'second.zip', size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return key;
  }

  testWidgets('the linked attachment opens in the viewer', (tester) async {
    final key = await pump(tester);
    final before = find.text('second.zip').evaluate().length;

    unawaited(key.currentState!.openAttachment('a2'));
    await tester.pumpAndSettle();

    expect(find.text('second.zip').evaluate().length, greaterThan(before));
    // Unmount, so the live connection stops before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an id the issue does not carry opens nothing', (tester) async {
    final key = await pump(tester);
    final routes = find.byType(ModalBarrier).evaluate().length;

    final opened = await key.currentState!.openAttachment('gone');
    await tester.pumpAndSettle();

    expect(opened, isFalse);
    expect(find.byType(ModalBarrier).evaluate().length, routes);
    await tester.pumpWidget(const SizedBox());
  });
}
