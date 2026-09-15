import '../../../core/models/work_models.dart';

/// What the server holds of the planning's cards while changes to them are
/// under way: each card's sprint and story points as they were before the
/// first of those changes, and as every change the server took left them.
///
/// A refused change takes a card back to this rather than to what the
/// planning showed when the change began, which may itself be a change not
/// taken yet.
class HeldCards {
  final Map<String, String?> _sprints = {};
  final Map<String, int?> _points = {};

  /// How many changes to each card are under way.
  final Map<String, int> _underWay = {};

  /// Notes a change to [card] under way. The first of the changes under way
  /// notes what the server holds of the card.
  void begin(Issue card) {
    if (!_underWay.containsKey(card.id)) {
      _sprints[card.id] = card.sprintId;
      _points[card.id] = card.storyPoints;
    }
    _underWay.update(card.id, (count) => count + 1, ifAbsent: () => 1);
  }

  /// The sprint the server holds the card [id] in, null for the backlog.
  String? sprintOf(String id) => _sprints[id];

  /// The story points the server holds for the card [id].
  int? pointsOf(String id) => _points[id];

  /// Notes that the server took the card [id] into [sprintId], which decides
  /// that change.
  void moved(String id, String? sprintId) {
    _sprints[id] = sprintId;
    end(id);
  }

  /// Notes that the server took [points] for the card [id], which decides
  /// that change.
  void estimated(String id, int? points) {
    _points[id] = points;
    end(id);
  }

  /// Notes a change to the card [id] decided. Once none is under way, what the
  /// server holds of the card is for the next read to show.
  void end(String id) {
    final left = (_underWay[id] ?? 1) - 1;
    if (left > 0) {
      _underWay[id] = left;
      return;
    }
    _underWay.remove(id);
    _sprints.remove(id);
    _points.remove(id);
  }
}
