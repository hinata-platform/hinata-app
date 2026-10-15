import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/models/work_models.dart';
import 'package:hinata/features/issues/issue_detail_sheet.dart';

/// The history names who was shared with, who was taken off and who left,
/// rather than "changed participant_added". Raw i18n keys render in tests.
void main() {
  Future<String> sentence(WidgetTester tester, IssueActivity activity) async {
    late String out;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            out = issueActivitySentence(context, activity, const {
              'u2': 'Helen',
            });
            return const SizedBox();
          },
        ),
      ),
    );
    return out;
  }

  IssueActivity entry(
    String field, {
    String? from,
    String? to,
    String? actor,
  }) => IssueActivity.fromJson({
    'id': 'a1',
    'issueId': 'i1',
    'actorId': actor ?? 'u1',
    'field': field,
    'fromValue': from,
    'toValue': to,
  });

  testWidgets('a share reads as one', (tester) async {
    expect(
      await sentence(tester, entry('PARTICIPANT_ADDED', to: 'u2')),
      'issues.act.participantAdded',
    );
  });

  testWidgets('a removal and a departure read apart', (tester) async {
    expect(
      await sentence(tester, entry('PARTICIPANT_REMOVED', from: 'u2')),
      'issues.act.participantRemoved',
    );
    expect(
      await sentence(
        tester,
        entry('PARTICIPANT_REMOVED', from: 'u2', actor: 'u2'),
      ),
      'issues.act.participantLeft',
    );
  });

  testWidgets('other changes keep their wording', (tester) async {
    expect(await sentence(tester, entry('TITLE')), 'issues.act.changed');
  });
}
