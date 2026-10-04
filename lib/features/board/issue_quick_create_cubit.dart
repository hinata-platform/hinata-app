import 'package:bloc/bloc.dart';

import '../../core/models/core_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/issue_repository.dart';
import '../../core/repositories/user_repository.dart';

/// The two requests of the inline composer: creating the issue and searching
/// the directory for its assignee.
///
/// Holds no state: the composer keeps its draft and the picker its pages.
/// Failures pass through as the repository's `ApiFailure`.
class IssueQuickCreateCubit extends Cubit<void> {
  IssueQuickCreateCubit({
    required IssueRepository issues,
    required UserRepository users,
  }) : _issues = issues,
       _users = users,
       super(null);

  final IssueRepository _issues;
  final UserRepository _users;

  Future<Issue> create(Map<String, dynamic> body) => _issues.createIssue(body);

  /// One page of the directory matching [query].
  Future<({List<DirectoryUser> items, int total})> searchUsers(
    String query, {
    int page = 0,
    int size = 25,
  }) => _users.searchUsers(query, page: page, size: size);
}
