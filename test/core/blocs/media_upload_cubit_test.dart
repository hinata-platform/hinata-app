import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hinata/core/api/api_client.dart';
import 'package:hinata/core/blocs/media_upload_cubit.dart';
import 'package:hinata/core/repositories/media_repository.dart';

/// The cubit only carries the editors' image upload to the repository; what
/// matters is that the file arrives untouched and the answer or the failure
/// comes back as the repository gave it.
void main() {
  test('uploads the file and answers the url and BlurHash', () async {
    final media = _FakeMediaRepository();
    final cubit = MediaUploadCubit(media);
    addTearDown(cubit.close);
    final file = MultipartFile.fromBytes([1, 2, 3], filename: 'a.png');

    final upload = await cubit.upload(file);

    expect(media.uploaded, [file]);
    expect(upload.url, '/api/v1/media/1');
    expect(upload.blurHash, 'LEHV6n');
  });

  test('passes a refusal through', () async {
    final cubit = MediaUploadCubit(
      _FakeMediaRepository(failure: ApiFailure('errors.tooLarge')),
    );
    addTearDown(cubit.close);

    await expectLater(
      cubit.upload(MultipartFile.fromBytes([1], filename: 'a.png')),
      throwsA(
        isA<ApiFailure>().having(
          (f) => f.message,
          'message',
          'errors.tooLarge',
        ),
      ),
    );
  });
}

class _FakeMediaRepository implements MediaRepository {
  _FakeMediaRepository({this.failure});

  final ApiFailure? failure;
  final List<MultipartFile> uploaded = [];

  @override
  Future<({String url, String? blurHash})> uploadMedia(
    MultipartFile file, {
    CancelToken? cancelToken,
  }) async {
    uploaded.add(file);
    if (failure != null) throw failure!;
    return (url: '/api/v1/media/1', blurHash: 'LEHV6n');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
