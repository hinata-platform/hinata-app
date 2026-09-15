import '../../../core/models/work_models.dart';
import 'board_wall_cubit.dart';

/// The wall's loaded cards and the epics and parents they name, by id: what
/// lanes resolve a card's epic or parent from. Worked out again only once the
/// wall holds other cards or references.
class BoardCardsByIdMemo {
  Object? _key;
  Map<String, Issue> _byId = const {};

  Map<String, Issue> of(BoardWallState wall) {
    final key = (wall.refs, wall.columns);
    if (key != _key) {
      _key = key;
      _byId = {...wall.refs, for (final card in wall.cards) card.id: card};
    }
    return _byId;
  }
}
