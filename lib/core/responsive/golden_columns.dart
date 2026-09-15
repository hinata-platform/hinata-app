import 'package:flutter/widgets.dart';

import 'responsive.dart';

/// The widest a page of card columns grows: 1597 · φ. Past it a column only gets
/// longer lines, not room for anything more.
const double goldenContentMax = 2584;

/// Cards that belong together: kept together, and in order, in one column.
class GoldenGroup<T> {
  const GoldenGroup(this.cards, {required this.weight, this.wide = false});

  final List<T> cards;

  /// Roughly how tall the group stands in a narrow column. Only the proportions
  /// between the groups of a page matter.
  final double weight;

  /// Whether its rows carry several controls side by side, so it wants the
  /// golden column.
  final bool wide;
}

/// Where the groups of a page went: the columns left to right, the golden one
/// first, and how much each column is expected to hold.
class GoldenArrangement<T> {
  const GoldenArrangement(this.columns, this.loads);

  final List<List<T>> columns;
  final List<double> loads;

  /// The flex of each column, `1618 : 1000 : 1000`.
  List<int> get flex => [
    for (var i = 0; i < columns.length; i++) i == 0 ? 1618 : 1000,
  ];
}

/// One column below [Breakpoints.mediumMax], two up to
/// [Breakpoints.readingWidth], three beyond it.
int goldenColumnCount(double width) {
  if (width < Breakpoints.mediumMax) return 1;
  if (width < Breakpoints.readingWidth) return 2;
  return 3;
}

/// A group in the golden column stands this much shorter: its rows wrap less.
const double _goldenColumnCost = 0.8;

/// A wide group squeezed into a narrow column stands this much taller.
const double _wideInNarrowCost = 1.3;

/// Spreads [groups] over [columns] columns so that they end about level.
///
/// The heaviest group is placed first, each where it adds the least height, so
/// a page that gains a card does not simply grow one column. A wide group costs
/// more in a narrow column and so settles in the golden one unless that is far
/// ahead; on a tie it takes the golden column and every other group a narrow
/// one. Within a column the groups keep the order the page declares them in,
/// and the narrow columns stand in the order of their first group.
///
/// Weights are fixed per page, never measured: a card that grew while somebody
/// typed in it must not jump to another column and take the caret with it.
GoldenArrangement<T> arrangeGolden<T>(
  List<GoldenGroup<T>> groups,
  int columns,
) {
  if (columns <= 1) {
    return GoldenArrangement(
      [groups.expand((group) => group.cards).toList()],
      [groups.fold(0, (sum, group) => sum + group.weight)],
    );
  }
  final loads = List<double>.filled(columns, 0);
  final assigned = List.generate(columns, (_) => <int>[]);
  final heaviestFirst = [for (var i = 0; i < groups.length; i++) i]
    ..sort((a, b) {
      final byWeight = groups[b].weight.compareTo(groups[a].weight);
      return byWeight != 0 ? byWeight : a.compareTo(b);
    });
  for (final index in heaviestFirst) {
    final group = groups[index];
    var best = -1;
    var bestLoad = double.infinity;
    for (var column = 0; column < columns; column++) {
      final factor = column == 0
          ? _goldenColumnCost
          : group.wide
          ? _wideInNarrowCost
          : 1.0;
      final load = loads[column] + group.weight * factor;
      final tie = (load - bestLoad).abs() < 1e-9;
      if (load < bestLoad - 1e-9 || (tie && !group.wide && best == 0)) {
        best = column;
        bestLoad = load;
      }
    }
    loads[best] = bestLoad;
    assigned[best].add(index);
  }
  for (final column in assigned) {
    column.sort();
  }
  final order = [
    0,
    ...([
      for (var i = 1; i < columns; i++)
        if (assigned[i].isNotEmpty) i,
    ]..sort((a, b) => assigned[a].first.compareTo(assigned[b].first))),
  ].where((i) => assigned[i].isNotEmpty).toList();
  return GoldenArrangement(
    [
      for (final column in order)
        [for (final index in assigned[column]) ...groups[index].cards],
    ],
    [for (final column in order) loads[column]],
  );
}

/// How far apart the columns may end before one fewer column is the better page.
const double levelEnough = 1.35;

/// The arrangement with the most columns, up to [maxColumns], whose columns end
/// within [levelEnough] of each other.
///
/// The width decides how many columns there is room for; the content decides how
/// many it fills. A page of four groups on a very wide screen would otherwise
/// leave a third column half empty beside two long ones. Two columns are kept
/// even when they are not level, since one column on a wide screen is worse.
GoldenArrangement<T> arrangeBalanced<T>(
  List<GoldenGroup<T>> groups,
  int maxColumns,
) {
  for (var columns = maxColumns; columns > 2; columns--) {
    final arrangement = arrangeGolden(groups, columns);
    if (spreadOf(arrangement.loads) <= levelEnough) return arrangement;
  }
  return arrangeGolden(groups, maxColumns < 2 ? maxColumns : 2);
}

/// The tallest column against the shortest; 1 for a single column.
double spreadOf(List<double> loads) {
  final positive = loads.where((load) => load > 0).toList();
  if (positive.length < 2) return 1;
  return positive.reduce((a, b) => a > b ? a : b) /
      positive.reduce((a, b) => a < b ? a : b);
}

/// Cards in as many golden columns as the width holds ([goldenColumnCount]) and
/// the content fills, spread by [arrangeBalanced].
class GoldenColumns<T> extends StatelessWidget {
  const GoldenColumns({
    super.key,
    required this.groups,
    required this.card,
    this.gap = 16,
  });

  final List<GoldenGroup<T>> groups;
  final Widget Function(T card) card;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final arrangement = arrangeBalanced(
        groups,
        goldenColumnCount(constraints.maxWidth),
      );
      Widget column(List<T> cards) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            card(cards[i]),
          ],
        ],
      );
      final columns = arrangement.columns;
      if (columns.isEmpty) return const SizedBox.shrink();
      if (columns.length == 1) return column(columns.single);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < columns.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: arrangement.flex[i], child: column(columns[i])),
          ],
        ],
      );
    },
  );
}
