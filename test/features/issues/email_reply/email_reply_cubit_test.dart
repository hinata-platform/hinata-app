import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/issues/email_reply/email_reply_cubit.dart';

import '../recording_fakes.dart';

void main() {
  late FakeIssueRepository issues;
  late EmailReplyCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    cubit = EmailReplyCubit(issues);
  });

  tearDown(() => cubit.close());

  test('sends the reply with the attachments it references', () async {
    await expectForwarded(
      issues,
      #replyEmail,
      () => Future<void>.value(),
      () => cubit.send(
        'i1',
        subject: 'Re: Login',
        body: 'Fixed.',
        attachmentIds: const ['a1'],
      ),
      positional: ['i1'],
      named: {
        #subject: 'Re: Login',
        #body: 'Fixed.',
        #attachmentIds: ['a1'],
      },
    );
  });

  test('attaches and detaches files on the issue', () async {
    final file = MultipartFile.fromBytes(const [1, 2, 3], filename: 'a.txt');
    await expectForwarded(
      issues,
      #uploadAttachment,
      () => Future.value(testIssue()),
      () => cubit.attach('i1', file),
      positional: ['i1', file],
    );
    await expectForwarded(
      issues,
      #deleteAttachment,
      () => Future<void>.value(),
      () => cubit.detach('i1', 'a1'),
      positional: ['i1', 'a1'],
    );
  });

  test('passes a refused reply on unchanged', () async {
    await expectFailurePassedOn<void>(
      issues,
      #replyEmail,
      () => cubit.send('i1', subject: 's', body: 'b'),
    );
  });
}
