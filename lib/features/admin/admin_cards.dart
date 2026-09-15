import 'package:flutter/material.dart';

import '../../core/responsive/golden_columns.dart';

/// The cards of an admin section, spread over as many golden columns as the
/// pane holds ([GoldenColumns]), with an optional note above them and an
/// optional line below.
///
/// A section used to be one column whatever the screen, and time tracking grew
/// to eleven cards in it. The cards are named rather than numbered so that one
/// that comes and goes with a switch does not take another card's measured
/// height with it. They start out counted alike; how tall each really stands is
/// measured once they have laid out.
class AdminCards extends StatelessWidget {
  const AdminCards({super.key, this.note, required this.cards, this.footer});

  /// A line above the columns, across the whole pane.
  final Widget? note;

  /// The cards in the order the section declares them, by name.
  final Map<String, Widget> cards;

  /// A line below the columns, for what holds for all of them.
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (note != null) ...[note!, const SizedBox(height: 16)],
      GoldenColumns<String>(
        groups: [
          for (final name in cards.keys)
            GoldenGroup([name], weight: 1, wide: true),
        ],
        card: (name) => cards[name]!,
      ),
      if (footer != null) ...[const SizedBox(height: 16), footer!],
    ],
  );
}
