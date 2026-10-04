import 'package:bloc/bloc.dart';
import 'package:dio/dio.dart';

import '../repositories/media_repository.dart';

/// Uploads inline images for the editors' image buttons.
///
/// Holds no state: the button already shows its own spinner and the editor
/// owns where the picture lands, so the cubit is only the path from the button
/// to [MediaRepository]. A failure surfaces as the repository's own
/// `ApiFailure`, which the button turns into a toast.
class MediaUploadCubit extends Cubit<void> {
  MediaUploadCubit(this._media) : super(null);

  final MediaRepository _media;

  /// Uploads [file] and answers its app-relative URL and BlurHash.
  Future<({String url, String? blurHash})> upload(MultipartFile file) =>
      _media.uploadMedia(file);
}
