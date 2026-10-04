import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/issues/attachments/attachments_cubit.dart';

import '../recording_fakes.dart';

void main() {
  late FakeIssueRepository issues;
  late FakeApiClient api;
  late AttachmentsCubit cubit;

  setUp(() {
    issues = FakeIssueRepository();
    api = FakeApiClient();
    cubit = AttachmentsCubit(issues: issues, api: api);
  });

  tearDown(() => cubit.close());

  test('opens the live attachment events of the issue', () async {
    final token = CancelToken();
    await expectForwarded(
      issues,
      #attachmentEventStream,
      () => Future.value(const Stream<List<int>>.empty()),
      () => cubit.events('i1', cancelToken: token),
      positional: ['i1'],
      named: {#cancelToken: token},
    );
  });

  test('reads the issue, uploads and deletes attachments', () async {
    await expectForwarded(
      issues,
      #issue,
      () => Future.value(testIssue()),
      () => cubit.issue('i1'),
      positional: ['i1'],
    );

    final file = MultipartFile.fromBytes(const [1], filename: 'a.png');
    final token = CancelToken();
    void progress(double _) {}
    await expectForwarded(
      issues,
      #uploadAttachment,
      () => Future.value(testIssue()),
      () => cubit.upload('i1', file, onProgress: progress, cancelToken: token),
      positional: ['i1', file],
      named: {#onProgress: progress, #cancelToken: token},
    );

    await expectForwarded(
      issues,
      #deleteAttachment,
      () => Future<void>.value(),
      () => cubit.delete('i1', 'a1'),
      positional: ['i1', 'a1'],
    );
    await expectForwarded(
      issues,
      #deleteAttachments,
      () => Future<void>.value(),
      () => cubit.deleteAll('i1', const ['a1', 'a2']),
      positional: [
        'i1',
        ['a1', 'a2'],
      ],
    );
  });

  test('downloads through the client, the archive by its path', () async {
    issues.answers[#attachmentsArchivePath] = (call) =>
        '/api/v1/issues/${call.positionalArguments.single}/attachments/archive';
    expect(cubit.archivePath('i1'), '/api/v1/issues/i1/attachments/archive');

    await expectForwarded(
      api,
      #getBytes,
      () => Future.value((bytes: const [1, 2], contentType: 'image/png')),
      () => cubit.download('/api/v1/attachments/a1/download'),
      positional: ['/api/v1/attachments/a1/download'],
    );
  });

  test('passes a refused delete on unchanged', () async {
    await expectFailurePassedOn<void>(
      issues,
      #deleteAttachment,
      () => cubit.delete('i1', 'a1'),
    );
  });
}
