import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/work_models.dart';
import '../../../core/repositories/issue_repository.dart';

/// Where an issue's attachments section sends its requests.
///
/// Holds no state of its own: the section keeps the list it shows, its
/// optimistic removals and the uploads in flight with their progress, and
/// awaits these calls the way it awaited the repository and the client.
class AttachmentsCubit extends Cubit<void> {
  AttachmentsCubit({required IssueRepository issues, required ApiClient api})
    : _issues = issues,
      _api = api,
      super(null);

  final IssueRepository _issues;
  final ApiClient _api;

  /// The live `added`/`removed` frames for [issueId]'s attachments.
  Future<Stream<List<int>>> events(
    String issueId, {
    CancelToken? cancelToken,
  }) => _issues.attachmentEventStream(issueId, cancelToken: cancelToken);

  /// The issue as the server holds it — its attachments are the authoritative
  /// list after a reconnect.
  Future<Issue> issue(String issueId) => _issues.issue(issueId);

  /// Uploads [file]; answers the issue with every attachment it now has.
  Future<Issue> upload(
    String issueId,
    MultipartFile file, {
    void Function(double pct)? onProgress,
    CancelToken? cancelToken,
  }) => _issues.uploadAttachment(
    issueId,
    file,
    onProgress: onProgress,
    cancelToken: cancelToken,
  );

  Future<void> delete(String issueId, String attachmentId) =>
      _issues.deleteAttachment(issueId, attachmentId);

  Future<void> deleteAll(String issueId, List<String> ids) =>
      _issues.deleteAttachments(issueId, ids);

  /// Where the zip of every attachment of [issueId] is served.
  String archivePath(String issueId) => _issues.attachmentsArchivePath(issueId);

  /// The bytes behind the API path [path] — a download or the archive — or
  /// null when the server sent none.
  Future<({List<int> bytes, String contentType})?> download(String path) =>
      _api.getBytes(path);
}
