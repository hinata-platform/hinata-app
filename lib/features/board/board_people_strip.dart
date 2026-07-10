import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/hive_widgets.dart';

/// Overlapping, selectable avatar stack of the people active on a board.
///
/// Clicking an avatar toggles it in the assignee filter (persistent
/// multi-select); hovering only lifts/brightens it. When at least one person
/// is selected the rest dim so the active filter reads at a glance. The strip
/// scrolls horizontally so it can never overflow on narrow layouts.
class BoardPeopleStrip extends StatefulWidget {
  const BoardPeopleStrip({
    super.key,
    required this.userIds,
    required this.names,
    required this.selected,
    required this.onToggle,
    this.avatars = const {},
    this.size = 30,
  });

  final List<String> userIds;
  final Map<String, String> names;
  final Map<String, String> avatars;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final double size;

  @override
  State<BoardPeopleStrip> createState() => _BoardPeopleStripState();
}

class _BoardPeopleStripState extends State<BoardPeopleStrip> {
  String? _hovered;

  @override
  Widget build(BuildContext context) {
    final ids = widget.userIds;
    if (ids.isEmpty) return const SizedBox.shrink();

    final size = widget.size;
    final overlap = size * 0.34;
    final step = size - overlap;
    final stackWidth = size + (ids.length - 1) * step;
    final anySelected = widget.selected.isNotEmpty;

    // Paint order: unselected first, then selected, then the hovered one last,
    // so highlighted avatars sit on top of their neighbours.
    int z(String id) =>
        id == _hovered ? 2 : (widget.selected.contains(id) ? 1 : 0);
    final order = List<int>.generate(ids.length, (i) => i)
      ..sort((a, b) => z(ids[a]).compareTo(z(ids[b])));

    // Content-sized (no internal scroll); the caller wraps it in a horizontal
    // scroller so it can shrink/scroll without an unbounded-width error.
    return SizedBox(
      width: stackWidth,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final i in order)
            Positioned(
              left: i * step,
              top: 3,
              child: _PersonAvatar(
                name: widget.names[ids[i]] ?? ids[i],
                imageUrl: widget.avatars[ids[i]],
                size: size,
                selected: widget.selected.contains(ids[i]),
                dimmed: anySelected && !widget.selected.contains(ids[i]),
                hovered: _hovered == ids[i],
                onEnter: () => setState(() => _hovered = ids[i]),
                onExit: () {
                  if (_hovered == ids[i]) setState(() => _hovered = null);
                },
                onTap: () => widget.onToggle(ids[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({
    required this.name,
    required this.size,
    required this.selected,
    required this.dimmed,
    required this.hovered,
    required this.onEnter,
    required this.onExit,
    required this.onTap,
    this.imageUrl,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final bool selected;
  final bool dimmed;
  final bool hovered;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lift = (selected || hovered) ? -2.0 : 0.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: GestureDetector(
        // opaque so a tap still registers even though the animated avatar below
        // is wrapped in IgnorePointer (see below).
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Tooltip(
          message: name,
          waitDuration: const Duration(milliseconds: 400),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: dimmed ? 0.45 : 1,
            child: IgnorePointer(
              // Keep the hover-lift as a paint-only effect: don't let the web
              // mouse-tracker hit-test down into the translating render object.
              // RenderFractionalTranslation asserts `!debugNeedsLayout` when
              // hit-tested mid-relayout — the same assert-flood that hung the
              // issue sheet on web. Hover/tap are handled by the MouseRegion +
              // opaque GestureDetector above, so nothing is lost.
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 150),
                curve: hiveEase,
                offset: Offset(0, lift / size),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      if (selected)
                        BoxShadow(
                          color: AppColors.accentStrong,
                          spreadRadius: 3.2,
                        ),
                      BoxShadow(color: AppColors.surface, spreadRadius: 1.6),
                    ],
                  ),
                  child: HiveAvatar(name: name, imageUrl: imageUrl, size: size),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
