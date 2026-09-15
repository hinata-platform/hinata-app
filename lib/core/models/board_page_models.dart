import 'package:equatable/equatable.dart';

import 'core_models.dart';
import 'work_models.dart';

/// How many cards a board asks for at a time: a column's first screen and a
/// little more, so the wall paints from one request and the rest comes as
/// someone scrolls to it.
const int kBoardPageSize = 30;

/// The most cards the server hands over in one request.
const int kBoardMaxPageSize = 100;

/// How many cards a sprint of the planning shows until it is asked for more.
const int kSprintPageSize = 50;

/// How many cards a page of the planning's backlog holds.
const int kBacklogPageSize = 12;

/// The longest search text the server takes; the search field stops there.
const int kBoardSearchMaxLength = 100;

/// The most cards the server looks up the links between in one request.
const int kBoardMaxLinkCards = 1000;

/// Which cards a board query is about.
enum BoardCardShape {
  /// The wall: work items only. Epics head lanes and sub-tasks live inside
  /// their parent, so neither is a card of its own.
  wall,

  /// The wall grouped by sub-task, where the sub-tasks are cards. In a sprint
  /// this takes in the sub-tasks of the sprint's work items, which carry no
  /// sprint of their own.
  subtasks,

  /// The timeline: work items and epics, no sub-tasks.
  timeline,

  /// The sprint planning: every issue type, as it has always listed them.
  planning,
}

/// What a board narrows on the server: the search text and every facet of its
/// filter. An empty set restricts nothing.
class BoardQuery extends Equatable {
  const BoardQuery({
    this.text = '',
    this.states = const {},
    this.types = const {},
    this.priorities = const {},
    this.assigneeIds = const {},
    this.reporterIds = const {},
    this.labels = const {},
    this.sprints = const {},
    this.epicIds = const {},
    this.shape = BoardCardShape.wall,
  });

  /// Every card of the wall.
  static const all = BoardQuery();

  /// Stands in [sprints] for the cards that are in no sprint.
  static const noSprint = '__none__';

  /// Matched against the key, the title and the labels, ignoring case.
  final String text;

  /// Workflow states as UPPER-CASE codes; the server maps them onto the
  /// states the board's projects define.
  final Set<String> states;
  final Set<String> types;
  final Set<String> priorities;

  /// People assigned to a card, first or further.
  final Set<String> assigneeIds;
  final Set<String> reporterIds;
  final Set<String> labels;

  /// Sprint ids, or [noSprint].
  final Set<String> sprints;

  /// Epics a card rolls up to, directly or through its parent.
  final Set<String> epicIds;
  final BoardCardShape shape;

  bool get hasText => text.trim().isNotEmpty;

  /// Whether anything but the shape narrows the cards: a search or a facet.
  bool get narrows => copyWith(shape: BoardCardShape.wall) != all;

  BoardQuery copyWith({
    String? text,
    Set<String>? states,
    Set<String>? types,
    Set<String>? priorities,
    Set<String>? assigneeIds,
    Set<String>? reporterIds,
    Set<String>? labels,
    Set<String>? sprints,
    Set<String>? epicIds,
    BoardCardShape? shape,
  }) => BoardQuery(
    text: text ?? this.text,
    states: states ?? this.states,
    types: types ?? this.types,
    priorities: priorities ?? this.priorities,
    assigneeIds: assigneeIds ?? this.assigneeIds,
    reporterIds: reporterIds ?? this.reporterIds,
    labels: labels ?? this.labels,
    sprints: sprints ?? this.sprints,
    epicIds: epicIds ?? this.epicIds,
    shape: shape ?? this.shape,
  );

  /// The query parameters. Empty facets stay out and every list is sorted, so
  /// the same narrowing always reads as the same request.
  Map<String, dynamic> toQuery() {
    List<String> sorted(Set<String> values) => values.toList()..sort();
    final trimmed = text.trim();
    return {
      if (trimmed.isNotEmpty) 'q': trimmed,
      if (states.isNotEmpty) 'states': sorted(states),
      if (types.isNotEmpty) 'types': sorted(types),
      if (priorities.isNotEmpty) 'priorities': sorted(priorities),
      if (assigneeIds.isNotEmpty) 'assigneeIds': sorted(assigneeIds),
      if (reporterIds.isNotEmpty) 'reporterIds': sorted(reporterIds),
      if (labels.isNotEmpty) 'labels': sorted(labels),
      if (sprints.isNotEmpty) 'sprints': sorted(sprints),
      if (epicIds.isNotEmpty) 'epicIds': sorted(epicIds),
      if (shape != BoardCardShape.wall) 'shape': shape.name,
    };
  }

  @override
  List<Object?> get props => [
    text.trim(),
    states,
    types,
    priorities,
    assigneeIds,
    reporterIds,
    labels,
    sprints,
    epicIds,
    shape,
  ];
}

/// The cards of one workflow state in a sprint: how many, whether they are
/// resolved, and their story points. A sprint's head adds these up for its
/// buckets and its capacity, so it counts every card and not only the loaded
/// ones.
class BoardStateSummary extends Equatable {
  const BoardStateSummary({
    required this.state,
    required this.resolved,
    required this.count,
    required this.points,
  });

  final String state;
  final bool resolved;
  final int count;
  final int points;

  factory BoardStateSummary.fromJson(Map<String, dynamic> json) =>
      BoardStateSummary(
        state: json['state'] as String? ?? '',
        resolved: json['resolved'] as bool? ?? false,
        count: (json['count'] as num?)?.toInt() ?? 0,
        points: (json['points'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [state, resolved, count, points];
}

/// A summary by state, added up.
extension BoardStateSummaries on Iterable<BoardStateSummary> {
  /// How many cards the rows count.
  int get cardCount => fold(0, (sum, row) => sum + row.count);

  /// The story points of those cards.
  int get points => fold(0, (sum, row) => sum + row.points);
}

/// One page of a board's cards: of a column, a sprint, the backlog or the
/// timeline.
class BoardCardPage extends Equatable {
  const BoardCardPage({
    required this.items,
    required this.total,
    this.users = const [],
    this.refs = const [],
    this.summary,
  });

  final List<Issue> items;

  /// Every card the query holds, loaded or not.
  final int total;

  /// The people the cards name, so a page never needs a lookup of its own.
  final List<DirectoryUser> users;

  /// The epics and parents the cards name, for lane headers.
  final List<Issue> refs;

  /// Only when asked for: the whole query's cards by state.
  final List<BoardStateSummary>? summary;

  factory BoardCardPage.fromJson(Map<String, dynamic> json) => BoardCardPage(
    items: _issues(json['content']),
    total: (json['totalElements'] as num?)?.toInt() ?? 0,
    users: _users(json['users']),
    refs: _issues(json['refs']),
    summary: (json['summary'] as List<dynamic>?)
        ?.map((s) => BoardStateSummary.fromJson(s as Map<String, dynamic>))
        .toList(),
  );

  @override
  List<Object?> get props => [items, total, users, refs, summary];
}

/// What a board's filter and its row of faces can offer, gathered on the
/// server over every card of the board rather than the ones loaded.
class BoardFacets extends Equatable {
  const BoardFacets({
    this.assigneeIds = const [],
    this.reporterIds = const [],
    this.labels = const [],
    this.states = const [],
    this.types = const [],
    this.priorities = const [],
    this.epics = const [],
    this.users = const [],
  });

  static const empty = BoardFacets();

  final List<String> assigneeIds;
  final List<String> reporterIds;
  final List<String> labels;
  final List<String> states;
  final List<String> types;
  final List<String> priorities;

  /// The epics of the board's projects.
  final List<Issue> epics;

  /// The people behind [assigneeIds] and [reporterIds].
  final List<DirectoryUser> users;

  factory BoardFacets.fromJson(Map<String, dynamic> json) => BoardFacets(
    assigneeIds: _strings(json['assigneeIds']),
    reporterIds: _strings(json['reporterIds']),
    labels: _strings(json['labels']),
    states: _strings(json['states']),
    types: _strings(json['types']),
    priorities: _strings(json['priorities']),
    epics: _issues(json['epics']),
    users: _users(json['users']),
  );

  @override
  List<Object?> get props => [
    assigneeIds,
    reporterIds,
    labels,
    states,
    types,
    priorities,
    epics,
    users,
  ];
}

/// A board as its wall first paints it: the columns, each with the number of
/// cards it holds and the first page of them, and the people, epics and
/// parents those cards name.
class BoardWallPage extends Equatable {
  const BoardWallPage({
    required this.board,
    required this.sprints,
    required this.columns,
    this.sprintId,
    this.users = const [],
    this.refs = const [],
  });

  final AgileBoard board;
  final List<Sprint> sprints;

  /// The sprint the wall shows: the one asked for, else the board's active one.
  final String? sprintId;
  final List<BoardColumnView> columns;
  final List<DirectoryUser> users;
  final List<Issue> refs;

  factory BoardWallPage.fromJson(Map<String, dynamic> json) => BoardWallPage(
    board: AgileBoard.fromJson(json['board'] as Map<String, dynamic>),
    sprints: ((json['sprints'] as List<dynamic>?) ?? const [])
        .map((s) => Sprint.fromJson(s as Map<String, dynamic>))
        .toList(),
    sprintId: json['sprintId'] as String?,
    columns: ((json['columns'] as List<dynamic>?) ?? const [])
        .map((c) => BoardColumnView.fromJson(c as Map<String, dynamic>))
        .toList(),
    users: _users(json['users']),
    refs: _issues(json['refs']),
  );

  @override
  List<Object?> get props => [board, sprints, sprintId, columns, users, refs];
}

List<Issue> _issues(Object? value) => ((value as List<dynamic>?) ?? const [])
    .map((i) => Issue.fromJson(i as Map<String, dynamic>))
    .toList();

List<DirectoryUser> _users(Object? value) =>
    ((value as List<dynamic>?) ?? const [])
        .map((u) => DirectoryUser.fromJson(u as Map<String, dynamic>))
        .toList();

List<String> _strings(Object? value) =>
    ((value as List<dynamic>?) ?? const []).whereType<String>().toList();
