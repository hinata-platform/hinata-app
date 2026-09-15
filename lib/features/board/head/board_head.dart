import 'package:flutter/material.dart';

import '../../../core/models/board_page_models.dart';
import '../../../core/models/core_models.dart';
import '../../../core/models/work_models.dart';
import '../board_filter.dart';
import '../board_filter_popup.dart';
import '../board_header.dart';
import '../board_people_strip.dart';
import '../board_swimlanes.dart';
import 'board_head_cubit.dart';

/// [boardPeople] of the users a board holds, worked out again only when another
/// map or list of them comes in.
class BoardPeopleMemo {
  Object? _key;
  BoardPeople? _people;

  /// The people of [users] and [more] together.
  BoardPeople of(Map<String, DirectoryUser> users, List<DirectoryUser> more) {
    final key = (users, more);
    final people = _people;
    if (people != null && key == _key) return people;
    _key = key;
    return _people = boardPeople([...more, ...users.values]);
  }
}

/// The head a board page wears, built from its [BoardHeadCubit]: the search,
/// the filter, the grouping and the faces, docked into the app bar on a phone.
///
/// Both kinds of board mix this in, so the same control behaves the same on
/// both. The words typed go straight to [head] and rebuild no page; the tools
/// here are drawn from a head state the page hands in.
mixin BoardHeadHost<T extends StatefulWidget> on State<T> {
  BoardHeadCubit get head;

  /// The search typed into the head.
  final TextEditingController searchController = TextEditingController();

  /// Whether a phone's docked row shows the search field instead of the tools.
  /// A wide window shows both side by side and never sets it.
  bool _searching = false;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  /// The phone's one docked row: [switcher], the search and [tools].
  Widget headDock({
    required Widget switcher,
    required List<Widget> tools,
    bool canSearch = true,
  }) => BoardHeaderDock(
    switcher: switcher,
    canSearch: canSearch,
    searching: _searching,
    searchController: searchController,
    onSearchChanged: head.search,
    onSearchOpen: () => setState(() => _searching = true),
    onSearchClose: () => setState(() => _searching = false),
    tools: tools,
  );

  /// The search as a field, where a wide window has room for one.
  Widget headSearchField() =>
      BoardSearchField(controller: searchController, onChanged: head.search);

  Widget headFilterPill(
    BoardHeadState state, {
    required void Function(Rect? anchor) onOpen,
    bool showLabel = false,
  }) => BoardFilterPill(
    count: state.filter.activeCount,
    showLabel: showLabel,
    onTap: onOpen,
  );

  Widget headGroupBy(
    BoardHeadState state, {
    required bool crossProject,
    bool compact = false,
  }) => BoardGroupByButton(
    value: state.grouping,
    compact: compact,
    options: boardGroupingsFor(crossProject: crossProject),
    onChanged: head.group,
  );

  /// The faces of the people the board's cards are assigned to, which toggle
  /// them in the filter; null while there are none.
  Widget? headPeople(BoardHeadState state) {
    final assignees = state.facets.assigneeIds;
    if (assignees.isEmpty) return null;
    final people = boardPeople(state.facets.users);
    return BoardPeopleStrip(
      userIds: assignees,
      names: people.names,
      avatars: people.avatars,
      pronouns: people.pronouns,
      selected: state.filter.assignees,
      onToggle: head.toggleAssignee,
    );
  }

  /// Opens the board's filter over the facets for cards of [shape], read again
  /// first when a change may have altered them. [sprints] are the ones the
  /// filter offers, [projects] lend their labels, [refs] and [users] name the
  /// epics and people of the cards loaded.
  Future<void> openHeadFilter({
    required BoardCardShape shape,
    required Rect? anchor,
    required List<Sprint> sprints,
    required Iterable<Project> projects,
    required Iterable<Issue> refs,
    required Iterable<DirectoryUser> users,
  }) async {
    await head.ensureFacets(shape, forFilter: true);
    if (!mounted) return;
    final facets = head.state.facets;
    final epics = boardEpics(facets.epics, refs);
    final people = boardPeople([...users, ...facets.users]);
    await openBoardFilter(
      context,
      anchor: anchor,
      filter: head.state.filter,
      options: BoardFilterOptions.fromFacets(
        facets,
        boardSprints: sprints,
        projectLabels: [for (final project in projects) ...project.labelNames],
        epicIds: [for (final epic in epics) epic.id],
      ),
      names: people.names,
      avatars: people.avatars,
      pronouns: people.pronouns,
      sprintNames: {for (final sprint in sprints) sprint.id: sprint.name},
      epicNames: {
        for (final epic in epics) epic.id: '${epic.readableId}  ${epic.title}',
      },
      onChanged: head.setFilter,
    );
  }
}
