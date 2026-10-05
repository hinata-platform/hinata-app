import 'package:flutter/widgets.dart';

import '../../core/responsive/golden_columns.dart';
import '../../core/responsive/responsive.dart';

/// Stable card keys for show/hide personalisation; the server stores them.
/// [hero] is the anchor card (with the board picker) and is never hideable.
abstract final class DashboardCard {
  static const hero = 'hero';
  static const focus = 'focus';
  static const git = 'git';
  static const kpis = 'kpis';
  static const completion = 'completion';
  static const tracker = 'tracker';
  static const ranking = 'ranking';
  static const away = 'away';
}

/// Content at least this wide holds a third column of panels.
///
/// Lower than the reading width the other card pages switch at: the key
/// figures span the whole page above the columns here, so no panel has to
/// carry four tiles side by side, and a narrow column of ~400 points still
/// holds a focus row with its title, estimate and assignee.
const double kDashboardThreeColumns = 1500;

/// One column while the content is narrower than φ², two up to
/// [kDashboardThreeColumns], three beyond it.
int dashboardColumnCount(double width) {
  if (width < Breakpoints.mediumMax) return 1;
  if (width < kDashboardThreeColumns) return 2;
  return 3;
}

/// The panels below the key figures, in the order the page declares them.
///
/// The weights say how tall each card stands, not how much it holds today:
/// a panel that collapses to its empty line keeps its place, so nobody has to
/// hunt for a card that moved because a week had no focus time. "Fokus heute"
/// is declared the heaviest of the narrow cards, so it is always placed first
/// and opens the column beside the hero: what needs the reader today sits next
/// to where the sprint stands, at every width that has two columns.
const _panels = <GoldenGroup<String>>[
  // The hero leads: it holds the board picker the page is personalised by.
  GoldenGroup([DashboardCard.hero], weight: 7, wide: true, lead: true),
  GoldenGroup([DashboardCard.focus], weight: 7),
  GoldenGroup([DashboardCard.away], weight: 4),
  GoldenGroup([DashboardCard.completion], weight: 3),
  GoldenGroup([DashboardCard.tracker], weight: 5, wide: true),
  GoldenGroup([DashboardCard.git], weight: 6),
  GoldenGroup([DashboardCard.ranking], weight: 5.5),
];

/// The declared panels that [shown] keeps.
List<GoldenGroup<String>> dashboardPanelGroups(bool Function(String) shown) => [
  for (final group in _panels)
    if (shown(group.cards.single)) group,
];

/// Every card in one column, the order a phone reads them in.
const dashboardStackOrder = [
  DashboardCard.hero,
  DashboardCard.kpis,
  DashboardCard.focus,
  DashboardCard.away,
  DashboardCard.completion,
  DashboardCard.tracker,
  DashboardCard.git,
  DashboardCard.ranking,
];

/// The dashboard's cards for the width they get.
///
/// One column: [dashboardStackOrder]. Two or three: the key figures across the
/// whole width, then the panels in golden columns ([arrangeBalanced]) dealt
/// from the declaration alone, never from measured heights.
class DashboardColumns extends StatefulWidget {
  const DashboardColumns({
    super.key,
    required this.shown,
    required this.card,
    this.gap = 18,
  });

  /// The cards to lay out; the reader's hidden ones are already gone.
  final Set<String> shown;
  final Widget Function(String key) card;
  final double gap;

  @override
  State<DashboardColumns> createState() => _DashboardColumnsState();
}

class _DashboardColumnsState extends State<DashboardColumns> {
  /// One key per card, so a card keeps its state (the focus-time range) when
  /// the window resizes and the columns are dealt again.
  final _keys = <String, GlobalKey>{};

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: _layout);

  Widget _card(String key) => KeyedSubtree(
    key: _keys.putIfAbsent(key, GlobalKey.new),
    child: widget.card(key),
  );

  Widget _column(Iterable<String> keys) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, key) in keys.indexed) ...[
        if (i > 0) SizedBox(height: widget.gap),
        _card(key),
      ],
    ],
  );

  Widget _layout(BuildContext context, BoxConstraints constraints) {
    final shown = widget.shown;
    _keys.removeWhere((key, _) => !shown.contains(key));
    final columns = dashboardColumnCount(constraints.maxWidth);
    if (columns == 1) {
      return _column(dashboardStackOrder.where(shown.contains));
    }
    final arrangement = arrangeBalanced(
      dashboardPanelGroups(shown.contains),
      columns,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (shown.contains(DashboardCard.kpis)) ...[
          _card(DashboardCard.kpis),
          SizedBox(height: widget.gap),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, cards) in arrangement.columns.indexed) ...[
              if (i > 0) SizedBox(width: widget.gap),
              Expanded(flex: arrangement.flex[i], child: _column(cards)),
            ],
          ],
        ),
      ],
    );
  }
}
