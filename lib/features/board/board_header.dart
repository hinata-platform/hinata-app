/// The controls a board wears at its head, shared by both kinds of board.
///
/// A Kanban wall and a Scrum board are the two pages a team moves between all
/// day, and they used to carry the same tools in different materials: a white
/// segmented control, white filter buttons and a search field down in the page,
/// under a glass app bar everything else in the app docks its tools into. These
/// are the glass versions, built once, so the two boards put the same control
/// in the same place.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_filter_bar.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../../core/widgets/hive_widgets.dart' show SegmentItem;
import '../sprint/modals/glass_modal.dart' show anchorRectOfContext;

/// How tall a board's docked row is on a phone.
const double kBoardDockHeight = kGlassDockRow;

/// The views of a board as the glass switch the time module and the Gantt
/// chart wear: icons on a phone, icons and words on a wide window.
class BoardViewSwitch extends StatelessWidget {
  const BoardViewSwitch({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.compact = false,
  });

  final List<SegmentItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  /// The icon-only shape, sized to a docked row.
  final bool compact;

  @override
  Widget build(BuildContext context) => GlassSwitchBar(
    compact: compact,
    maxWidth: (compact ? 60.0 : 150.0) * items.length,
    chips: [
      for (var i = 0; i < items.length; i++) ...[
        if (i > 0) const SizedBox(width: 2),
        GlassSwitchChip(
          label: items[i].label,
          icon: items[i].icon,
          active: i == selected,
          iconOnly: compact,
          // The view on screen is not a button.
          onTap: i == selected ? null : () => onChanged(i),
        ),
      ],
    ],
  );
}

/// The pill that opens a board's filter, with the number of criteria in force.
///
/// Washed amber while any are: a board quietly cut down to one person's cards
/// must not look like a board that has nothing else on it.
class BoardFilterPill extends StatelessWidget {
  const BoardFilterPill({
    super.key,
    required this.count,
    required this.onTap,
    this.showLabel = false,
  });

  final int count;

  /// Handed the pill's own rectangle, for the popover to hang from. The pill
  /// may be drawn by the shell's app bar rather than by the page, so a key the
  /// page holds is no way to find it.
  final void Function(Rect? anchor) onTap;

  /// Whether the word stands beside the icon. Only where there is room for it.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final label = context.t('board.filterButton');
    final active = count > 0;
    final ink = active ? AppColors.accentStrong : AppColors.inkSoft;
    final pill = Builder(
      builder: (context) => GlassPill(
        height: kGlassControlHeight,
        active: active,
        onTap: () => onTap(anchorRectOfContext(context)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: showLabel ? 14 : 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.slidersHorizontal, size: 16, color: ink),
              if (showLabel) ...[
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ],
              if (active) ...[const SizedBox(width: 6), _CountBadge(count)],
            ],
          ),
        ),
      ),
    );
    // Only where the word is gone; a tooltip repeating visible text is noise.
    return showLabel ? pill : Tooltip(message: label, child: pill);
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 18),
    height: 18,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 5),
    decoration: BoxDecoration(
      color: AppColors.accent,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        fontFamily: AppTheme.fontMono,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF2A2410),
      ),
    ),
  );
}

/// A board's search on a wide window, where it has room to be a field.
class BoardSearchField extends StatelessWidget {
  const BoardSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: GlassSearchField(
      hint: context.t('board.searchIssues'),
      controller: controller,
      onChanged: onChanged,
    ),
  );
}

/// The people's faces for a wide toolbar, bounded so a crowded board scrolls
/// its faces rather than pushing the tools apart.
class BoardPeopleSlot extends StatelessWidget {
  const BoardPeopleSlot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 240),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: child,
    ),
  );
}

/// A board's one docked row on a phone, in the band the app bar is already
/// blurring: the view switch, the search, and the tools of the view on screen.
///
/// One row, because the blur holds two lines and the title is the first. The
/// search field takes the row over only while it is open (see
/// [GlassSearchDock]), and the tools scroll sideways when a narrow phone has no
/// room for all of them.
class BoardHeaderDock extends StatelessWidget {
  const BoardHeaderDock({
    super.key,
    required this.switcher,
    required this.tools,
    required this.searching,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchOpen,
    required this.onSearchClose,
    this.canSearch = true,
  });

  final Widget switcher;
  final List<Widget> tools;
  final bool searching;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchOpen;
  final VoidCallback onSearchClose;

  /// False where the view on screen has nothing to search, like the insights.
  final bool canSearch;

  @override
  Widget build(BuildContext context) {
    final hint = context.t('board.searchIssues');
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
      // The bar hands the row its height as a tight constraint; the Align lets
      // the shorter controls come in under it, on the leading edge under the
      // title rather than drifting to the middle as tools come and go.
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: GlassSearchDock(
          searching: searching && canSearch,
          hint: hint,
          controller: searchController,
          onChanged: onSearchChanged,
          onClose: onSearchClose,
          controls: SizedBox(
            height: kGlassControlHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              // The gutter is spent above; clipping here would cut the last
              // tool off instead of letting it scroll into view.
              clipBehavior: Clip.none,
              child: Row(
                children: [
                  switcher,
                  if (canSearch) ...[
                    const SizedBox(width: 8),
                    GlassSearchButton(
                      tooltip: hint,
                      active: searchController.text.trim().isNotEmpty,
                      onTap: onSearchOpen,
                    ),
                  ],
                  for (final tool in tools) ...[const SizedBox(width: 8), tool],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
