import 'package:flutter/foundation.dart';

import '../../core/models/board_page_models.dart';
import '../../core/models/work_models.dart';

/// Multi-criteria board filter. Empty sets mean "no restriction" for that
/// facet. State / type / priority are stored as UPPER-CASE backend codes;
/// [assignees]/[authors] hold user ids, [sprints] hold sprint ids (or
/// [noSprint] for "Kein Sprint"), [labels] hold tag names. The same instance
/// backs both the people strip (which toggles [assignees]) and the glass filter
/// popup, so selection stays in lockstep across the board.
@immutable
class BoardFilter {
  const BoardFilter({
    this.states = const {},
    this.types = const {},
    this.priorities = const {},
    this.assignees = const {},
    this.sprints = const {},
    this.authors = const {},
    this.labels = const {},
    this.epics = const {},
  });

  final Set<String> states;
  final Set<String> types;
  final Set<String> priorities;
  final Set<String> assignees;
  final Set<String> sprints;
  final Set<String> authors;
  final Set<String> labels;

  /// Epic ids. A card passes when the epic it rolls up to, directly or through
  /// its parent, is in this set.
  final Set<String> epics;

  /// Sentinel value used in [sprints] to match issues with no sprint.
  static const noSprint = '__none__';

  bool get isEmpty =>
      states.isEmpty &&
      types.isEmpty &&
      priorities.isEmpty &&
      assignees.isEmpty &&
      sprints.isEmpty &&
      authors.isEmpty &&
      labels.isEmpty &&
      epics.isEmpty;

  int get activeCount =>
      states.length +
      types.length +
      priorities.length +
      assignees.length +
      sprints.length +
      authors.length +
      labels.length +
      epics.length;

  Set<String> facet(BoardFilterFacet f) => switch (f) {
    BoardFilterFacet.state => states,
    BoardFilterFacet.type => types,
    BoardFilterFacet.priority => priorities,
    BoardFilterFacet.assignee => assignees,
    BoardFilterFacet.sprint => sprints,
    BoardFilterFacet.author => authors,
    BoardFilterFacet.label => labels,
    BoardFilterFacet.epic => epics,
  };

  /// This filter as the server narrows by it, with the search [text] and the
  /// [shape] of the cards the board wants.
  BoardQuery toQuery({
    String text = '',
    BoardCardShape shape = BoardCardShape.wall,
  }) => BoardQuery(
    text: text,
    states: states,
    types: types,
    priorities: priorities,
    assigneeIds: assignees,
    reporterIds: authors,
    labels: labels,
    sprints: sprints,
    epicIds: epics,
    shape: shape,
  );

  BoardFilter copyWith({
    Set<String>? states,
    Set<String>? types,
    Set<String>? priorities,
    Set<String>? assignees,
    Set<String>? sprints,
    Set<String>? authors,
    Set<String>? labels,
    Set<String>? epics,
  }) => BoardFilter(
    states: states ?? this.states,
    types: types ?? this.types,
    priorities: priorities ?? this.priorities,
    assignees: assignees ?? this.assignees,
    sprints: sprints ?? this.sprints,
    authors: authors ?? this.authors,
    labels: labels ?? this.labels,
    epics: epics ?? this.epics,
  );

  /// Returns a copy with [value] toggled in the facet named [facet].
  BoardFilter toggle(BoardFilterFacet facet, String value) {
    Set<String> next(Set<String> current) {
      final updated = {...current};
      if (!updated.remove(value)) updated.add(value);
      return updated;
    }

    return switch (facet) {
      BoardFilterFacet.state => copyWith(states: next(states)),
      BoardFilterFacet.type => copyWith(types: next(types)),
      BoardFilterFacet.priority => copyWith(priorities: next(priorities)),
      BoardFilterFacet.assignee => copyWith(assignees: next(assignees)),
      BoardFilterFacet.sprint => copyWith(sprints: next(sprints)),
      BoardFilterFacet.author => copyWith(authors: next(authors)),
      BoardFilterFacet.label => copyWith(labels: next(labels)),
      BoardFilterFacet.epic => copyWith(epics: next(epics)),
    };
  }

  static const empty = BoardFilter();
}

enum BoardFilterFacet {
  state,
  type,
  priority,
  assignee,
  sprint,
  author,
  label,
  epic,
}

/// The distinct facet values available to filter on, gathered by the server
/// over every card of a board (plus the board's sprints and project labels),
/// so custom workflow states and labels resolve without hardcoding.
class BoardFilterOptions {
  BoardFilterOptions({
    required this.states,
    required this.types,
    required this.priorities,
    required this.assignees,
    required this.authors,
    required this.sprints,
    required this.labels,
    required this.epics,
  });

  /// UPPER-CASE workflow-state codes.
  final List<String> states;

  /// UPPER-CASE issue-type codes.
  final List<String> types;

  /// UPPER-CASE priority codes.
  final List<String> priorities;

  /// Assignee user ids.
  final List<String> assignees;

  /// Reporter (author) user ids.
  final List<String> authors;

  /// Sprint ids in board order (the "Kein Sprint" sentinel is added by the UI).
  final List<String> sprints;

  /// Label / tag names.
  final List<String> labels;

  /// Epic issue ids available to filter on (supplied by the board).
  final List<String> epics;

  bool get isEmpty =>
      states.isEmpty &&
      types.isEmpty &&
      priorities.isEmpty &&
      assignees.isEmpty &&
      authors.isEmpty &&
      sprints.isEmpty &&
      labels.isEmpty &&
      epics.isEmpty;

  /// The options the server gathered over every card of a board, so a value
  /// on a card nobody scrolled to is still there to filter by.
  factory BoardFilterOptions.fromFacets(
    BoardFacets facets, {
    required List<Sprint> boardSprints,
    required Iterable<String> projectLabels,
    Iterable<String> epicIds = const [],
  }) {
    List<String> upper(List<String> values) => [
      ...{
        for (final value in values)
          if (value.isNotEmpty) value.toUpperCase(),
      },
    ];
    return BoardFilterOptions(
      states: upper(facets.states),
      types: upper(facets.types),
      priorities: upper(facets.priorities),
      assignees: facets.assigneeIds,
      authors: facets.reporterIds,
      sprints: [for (final s in boardSprints) s.id],
      labels: [
        ...{
          ...facets.labels.where((l) => l.isNotEmpty),
          ...projectLabels.where((l) => l.isNotEmpty),
        },
      ],
      epics: epicIds.toList(),
    );
  }
}
