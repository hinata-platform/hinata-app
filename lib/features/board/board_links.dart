/// Where a board lives in the app.
///
/// A board has an address of its own, under the list it was opened from, so a
/// reload or a copied link lands on the board rather than on that list
/// (HIN-114). Open one with `context.go`, never `push`: go_router's `push`
/// leaves the browser's address where it was, which is how a board used to
/// reload into the overview.
///
/// Ids are encoded. A link can carry any text as an id, and put into the
/// address as it came, `..%2F..%2Fadmin` would lead somewhere that is not a
/// board.
library;

/// The overview of every board.
const boardsLocation = '/board';

/// A board opened from the overview, or from anywhere without a list of its
/// own. Without a board to name, the overview.
String boardLocation(String boardId) => _isSegment(boardId)
    ? '$boardsLocation/${Uri.encodeComponent(boardId)}'
    : boardsLocation;

/// A board opened from one project's boards, which stay underneath it.
String projectBoardLocation(String projectId, String boardId) =>
    '/projects/${Uri.encodeComponent(projectId)}'
    '/boards/${Uri.encodeComponent(boardId)}';

/// Whether [id] can stand as a path segment of its own. `.` and `..` stay what
/// they are when encoded, and a path resolves them away.
bool _isSegment(String id) => id.isNotEmpty && id != '.' && id != '..';
