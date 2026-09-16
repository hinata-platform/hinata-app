import 'package:flutter/widgets.dart';

import 'responsive.dart';

/// The widest a page of card columns grows: 1597 · φ. Past it a column only gets
/// longer lines, not room for anything more.
const double goldenContentMax = 2584;

/// Cards that belong together: kept together, and in order, in one column.
class GoldenGroup<T> {
  /// [weight] is roughly how tall the group stands in a narrow column; only the
  /// proportions between the groups of a page matter. In the golden column it is
  /// taken a little shorter, and a [wide] group in a narrow one taller.
  const GoldenGroup(
    this.cards, {
    required double weight,
    this.wide = false,
    this.lead = false,
  }) : narrow = weight * (wide ? _wideInNarrowCost : 1.0),
       golden = weight * _goldenColumnCost;

  /// How tall the cards were measured to stand in each kind of column, rather
  /// than guessed from one weight.
  const GoldenGroup.measured(
    this.cards, {
    required this.narrow,
    required this.golden,
    this.wide = false,
    this.lead = false,
  });

  final List<T> cards;

  /// How tall the group stands in a narrow column.
  final double narrow;

  /// How tall it stands in the golden one.
  final double golden;

  /// Whether the group opens the golden column whatever the others weigh: the
  /// card a page is read from, which must not drift into a narrow column once
  /// the heights are measured.
  final bool lead;

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
/// Every group says how tall it stands in each kind of column, so a card whose
/// rows wrap in a narrow column is counted there at what it really costs.
GoldenArrangement<T> arrangeGolden<T>(
  List<GoldenGroup<T>> groups,
  int columns,
) {
  if (columns <= 1) {
    return GoldenArrangement(
      [groups.expand((group) => group.cards).toList()],
      [groups.fold(0, (sum, group) => sum + group.narrow)],
    );
  }
  final loads = List<double>.filled(columns, 0);
  final assigned = List.generate(columns, (_) => <int>[]);
  for (var i = 0; i < groups.length; i++) {
    if (!groups[i].lead) continue;
    loads[0] += groups[i].golden;
    assigned[0].add(i);
  }
  final heaviestFirst =
      [
        for (var i = 0; i < groups.length; i++)
          if (!groups[i].lead) i,
      ]..sort((a, b) {
        final byWeight = groups[b].narrow.compareTo(groups[a].narrow);
        return byWeight != 0 ? byWeight : a.compareTo(b);
      });
  for (final index in heaviestFirst) {
    final group = groups[index];
    var best = -1;
    var bestLoad = double.infinity;
    for (var column = 0; column < columns; column++) {
      final load = loads[column] + (column == 0 ? group.golden : group.narrow);
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
    column.sort((a, b) {
      if (groups[a].lead != groups[b].lead) return groups[a].lead ? -1 : 1;
      return a.compareTo(b);
    });
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
///
/// **Where a card sits depends on nothing but the page's own declaration and
/// the number of columns.** That is the whole contract, and it is worth more
/// than a perfectly level pair of columns.
///
/// It did measure, once. Every card was measured after it laid out and again
/// whenever it changed size, and the page re-arranged itself around the real
/// heights — which meant a card's position depended on how much data it had
/// found, and how late. Cards visibly hopped between columns for a second while
/// a page loaded, and the same page put the same card in a different place for
/// a different project. Nobody can learn a layout like that; you end up hunting
/// for a card you have opened a hundred times. Level columns are a thing you
/// notice once. A card that moves is a thing you notice every time.
///
/// So the weights a page declares are the whole input. They are a statement
/// about the card, not about today's data: roughly how tall it stands, whether
/// it is [GoldenGroup.wide], and whether it [GoldenGroup.lead]s its column. A
/// page whose columns end uneven is tuned by changing what it declares.
class GoldenColumns<T> extends StatefulWidget {
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
  State<GoldenColumns<T>> createState() => _GoldenColumnsState<T>();
}

class _GoldenColumnsState<T> extends State<GoldenColumns<T>> {
  /// One key per card, so a card keeps its state when the window resizes and
  /// the columns are dealt again.
  final _keys = <T, GlobalKey>{};

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _columns);

  Widget _columns(BuildContext context, BoxConstraints constraints) {
    final arrangement = arrangeBalanced(
      widget.groups,
      goldenColumnCount(constraints.maxWidth),
    );
    final live = {for (final group in widget.groups) ...group.cards};
    _keys.removeWhere((card, _) => !live.contains(card));

    Widget column(List<T> cards) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) SizedBox(height: widget.gap),
          KeyedSubtree(
            key: _keys.putIfAbsent(cards[i], GlobalKey.new),
            child: widget.card(cards[i]),
          ),
        ],
      ],
    );
    final columns = arrangement.columns;
    if (columns.isEmpty) return const SizedBox.shrink();
    if (columns.length == 1) {
      // A page of one card would otherwise run the whole width of a wide
      // screen, and a form that wide is no longer a column.
      return Align(
        alignment: AlignmentDirectional.topStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Breakpoints.readingWidth),
          child: column(columns.single),
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < columns.length; i++) ...[
          if (i > 0) SizedBox(width: widget.gap),
          Expanded(flex: arrangement.flex[i], child: column(columns[i])),
        ],
      ],
    );
  }
}
