import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// The weights of the groups are only where the page starts. How tall a card
/// really stands depends on its data (how many members, repositories, sessions
/// or labels), and some cards read that data only after they appeared. So the
/// cards are measured after they laid out, and again whenever one changes its
/// size, until somebody touches the page: a tap or a focus inside it, or a few
/// seconds without either. After that the arrangement holds still. A card that
/// grows while somebody types in it must not jump to another column and take
/// the caret with it. Resizing the window spreads the same measured heights over
/// the new number of columns.
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
  /// When the page holds still whatever still arrives. Long enough for the
  /// reads a card makes on its own, short enough that nothing moves under a
  /// reader who is only slow to touch anything.
  static const _latest = Duration(seconds: 12);

  /// How often the same arrangement may come back before the page stops there:
  /// a card that wraps differently in the other column would otherwise make two
  /// arrangements point at each other for good.
  static const _repeats = 3;

  /// One key per card, so a card keeps its state when it moves to another
  /// column.
  final _keys = <T, GlobalKey>{};

  /// Measured heights, per kind of column: the same card stands taller in a
  /// narrow column than in the golden one, and by how much is nothing a factor
  /// can say. Until a card has stood in both, the other is estimated from the
  /// group's own proportion.
  final _inGolden = <T, double>{};
  final _inNarrow = <T, double>{};

  /// How often the page has stood in each arrangement, see [_repeats].
  final _seen = <String, int>{};

  GoldenArrangement<T>? _shown;
  Timer? _lastCall;
  bool _settled = false;
  bool _pending = false;
  bool _force = false;

  @override
  void initState() {
    super.initState();
    _lastCall = Timer(_latest, _holdStill);
  }

  @override
  void didUpdateWidget(GoldenColumns<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A card came or went (a hidden one shown for editing, data that arrived):
    // nobody is typing in a card that was not there, so measure the new set
    // once more rather than fall back to the estimates for good.
    final before = {for (final group in oldWidget.groups) ...group.cards};
    final after = {for (final group in widget.groups) ...group.cards};
    if (before.length == after.length && before.containsAll(after)) return;
    _keys.removeWhere((card, _) => !after.contains(card));
    _inGolden.removeWhere((card, _) => !after.contains(card));
    _inNarrow.removeWhere((card, _) => !after.contains(card));
    _schedule(force: true);
  }

  @override
  void dispose() {
    _lastCall?.cancel();
    super.dispose();
  }

  void _holdStill() {
    _settled = true;
    _lastCall?.cancel();
  }

  /// Measures after the coming frame, when the cards have their new sizes.
  void _schedule({bool force = false}) {
    _force |= force;
    if ((_settled && !_force) || _pending) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      final forced = _force;
      _force = false;
      if (mounted) _measure(force: forced);
    });
  }

  /// Whether every card has been measured at least once; estimates and measured
  /// heights are not in one unit, so a page uses one or the other.
  bool get _measured => widget.groups.every(
    (group) => group.cards.every(
      (card) => _inGolden.containsKey(card) || _inNarrow.containsKey(card),
    ),
  );

  /// What [card] of [group] stands in that kind of column, measured where it has
  /// been and carried over by the group's own proportion where it has not.
  double _heightOf(T card, GoldenGroup<T> group, {required bool golden}) {
    final measured = golden ? _inGolden[card] : _inNarrow[card];
    if (measured != null) return measured;
    final other = (golden ? _inNarrow[card] : _inGolden[card])!;
    final ratio = group.narrow / group.golden;
    return golden ? other / ratio : other * ratio;
  }

  List<GoldenGroup<T>> get _weighted {
    if (!_measured) return widget.groups;
    return [
      for (final group in widget.groups)
        GoldenGroup.measured(
          group.cards,
          narrow: group.cards.fold(
            0,
            (sum, card) => sum + _heightOf(card, group, golden: false),
          ),
          golden: group.cards.fold(
            0,
            (sum, card) => sum + _heightOf(card, group, golden: true),
          ),
          wide: group.wide,
          lead: group.lead,
        ),
    ];
  }

  void _measure({bool force = false}) {
    if (_settled && !force) return;
    final shown = _shown;
    if (shown == null || shown.columns.length < 2) return;
    var changed = false;
    for (var column = 0; column < shown.columns.length; column++) {
      final into = column == 0 ? _inGolden : _inNarrow;
      for (final card in shown.columns[column]) {
        final box = _keys[card]?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        final height = box.size.height + widget.gap;
        if (((into[card] ?? -1) - height).abs() < 1) continue;
        into[card] = height;
        changed = true;
      }
    }
    if (!changed) return;
    setState(() {});
  }

  static bool _sameColumns<T>(List<List<T>> a, List<List<T>> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => listEquals(a[i], b[i]));

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) {
      if (focused) _holdStill();
    },
    child: Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _holdStill(),
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _schedule();
          return true;
        },
        child: LayoutBuilder(builder: _columns),
      ),
    ),
  );

  Widget _columns(BuildContext context, BoxConstraints constraints) {
    final arrangement = arrangeBalanced(
      _weighted,
      goldenColumnCount(constraints.maxWidth),
    );
    final previous = _shown;
    if (previous == null) {
      _schedule();
    } else if (!_sameColumns(previous.columns, arrangement.columns)) {
      final signature = arrangement.columns.toString();
      final seen = (_seen[signature] ?? 0) + 1;
      _seen[signature] = seen;
      if (seen >= _repeats) _holdStill();
    }
    _shown = arrangement;
    Widget column(List<T> cards) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) SizedBox(height: widget.gap),
          KeyedSubtree(
            key: _keys.putIfAbsent(cards[i], GlobalKey.new),
            child: SizeChangedLayoutNotifier(child: widget.card(cards[i])),
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
