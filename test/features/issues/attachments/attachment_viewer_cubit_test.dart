import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/features/issues/attachments/attachment_viewer_cubit.dart';

import '../recording_fakes.dart';

void main() {
  late FakeApiClient api;
  late AttachmentViewerCubit cubit;

  setUp(() {
    api = FakeApiClient();
    cubit = AttachmentViewerCubit(api);
  });

  tearDown(() => cubit.close());

  test('downloads the file behind the path', () async {
    await expectForwarded(
      api,
      #getBytes,
      () => Future.value((bytes: const [1, 2], contentType: 'image/png')),
      () => cubit.download('/api/v1/attachments/a1/download'),
      positional: ['/api/v1/attachments/a1/download'],
    );
  });

  test('passes a failed download on unchanged', () async {
    await expectFailurePassedOn<({List<int> bytes, String contentType})?>(
      api,
      #getBytes,
      () => cubit.download('/x'),
    );
  });
}
