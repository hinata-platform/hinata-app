import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';

/// Where the attachment viewer fetches the files it shows.
///
/// Holds no state of its own: each page keeps its own future, and the byte
/// cache that makes paging back instant is shared by every viewer opened.
class AttachmentViewerCubit extends Cubit<void> {
  AttachmentViewerCubit(this._api) : super(null);

  final ApiClient _api;

  /// The raw bytes behind the API download path [path], or null when the
  /// server sent none.
  Future<({List<int> bytes, String contentType})?> download(String path) =>
      _api.getBytes(path);
}
