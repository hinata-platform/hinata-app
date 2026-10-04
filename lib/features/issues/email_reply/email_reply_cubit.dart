import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/work_models.dart';
import '../../../core/repositories/issue_repository.dart';

/// Where the reply-by-email composer sends the reply and its attachments.
///
/// Holds no state of its own: the composer keeps the draft, the upload chips
/// and the sending flag, and awaits these calls the way it awaited the
/// repository.
class EmailReplyCubit extends Cubit<void> {
  EmailReplyCubit(this._issues) : super(null);

  final IssueRepository _issues;

  /// Mails the reply to the issue's original sender.
  Future<void> send(
    String issueId, {
    required String subject,
    required String body,
    List<String> attachmentIds = const [],
  }) => _issues.replyEmail(
    issueId,
    subject: subject,
    body: body,
    attachmentIds: attachmentIds,
  );

  /// Uploads [file] onto the issue; answers the issue with it attached.
  Future<Issue> attach(String issueId, MultipartFile file) =>
      _issues.uploadAttachment(issueId, file);

  /// Removes an attachment the draft dropped again.
  Future<void> detach(String issueId, String attachmentId) =>
      _issues.deleteAttachment(issueId, attachmentId);
}
