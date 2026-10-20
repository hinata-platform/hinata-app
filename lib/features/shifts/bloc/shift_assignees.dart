import '../../../core/models/core_models.dart' show DirectoryUser;
import '../../../core/repositories/shift_repository.dart';

/// The people a planner can put on a shift of one project (HIN-162): the
/// server's candidates, everybody active who reaches the project, directly
/// or through a team.
///
/// One request per query and no pages: the server answers with the first
/// [limit] by name and says when there were more ([truncated]); typing a
/// name narrows the list instead of scrolling through it.
class ShiftAssignees {
  ShiftAssignees(this._shifts, this.projectId, {this.limit = 50});

  final ShiftRepository _shifts;
  final String projectId;
  final int limit;

  /// Whether the last answer left people out.
  bool get truncated => _truncated;
  bool _truncated = false;

  /// The people matching [query]. Only the first page has people; a later
  /// one is empty, so the picker never asks twice for the same list.
  Future<({List<DirectoryUser> items, int total})> search(
    String query,
    int page,
    int size,
  ) async {
    if (page > 0) return (items: const <DirectoryUser>[], total: 0);
    final answer = await _shifts.candidates(
      projectId,
      query: query,
      limit: limit,
    );
    _truncated = answer.truncated;
    final items = [
      for (final c in answer.candidates)
        DirectoryUser(
          id: c.userId,
          username: '',
          displayName: c.name,
          avatarUrl: c.avatarUrl,
        ),
    ];
    return (items: items, total: items.length);
  }
}
