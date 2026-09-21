import 'dart:async';

import 'package:flutter/material.dart';

import '../responsive/responsive.dart';
import 'glass_filter_bar.dart';

/// One scope of a [GlassScopeRow]: its key, its glyph and its label.
typedef GlassScope = ({String key, IconData icon, String label});

/// A page's lists or tabs as a row of glass pills — docked into the app bar on
/// a phone, at the head of the page on a wide window.
///
/// The active one scrolls into view: on a phone five pills are wider than the
/// screen, and a pill sat past the edge while it was the one shown (HIN-118
/// live check). A widget of its own because the docked row is built by the
/// shell a frame after the page, so only the row itself knows when it is laid
/// out. Shared by the absences and the reports (HIN-93), so both rows behave
/// the same.
class GlassScopeRow extends StatefulWidget {
  const GlassScopeRow({
    super.key,
    required this.scopes,
    required this.active,
    required this.onSelected,
  });

  final List<GlassScope> scopes;
  final String active;
  final ValueChanged<String> onSelected;

  @override
  State<GlassScopeRow> createState() => _GlassScopeRowState();
}

class _GlassScopeRowState extends State<GlassScopeRow> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reveal() {
    if (!mounted || !_scroll.hasClients) return;
    final index = widget.scopes.indexWhere(
      (scope) => scope.key == widget.active,
    );
    final position = _scroll.position;
    final target = widget.scopes.length <= 1 || index <= 0
        ? 0.0
        : position.maxScrollExtent * index / (widget.scopes.length - 1);
    if ((position.pixels - target).abs() < 1) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(target);
    } else {
      unawaited(
        position.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        height: kGlassControlHeight,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: context.isCompact
              ? EdgeInsets.symmetric(horizontal: context.pageGutter)
              : EdgeInsets.zero,
          child: Row(
            children: [
              for (final (index, scope) in widget.scopes.indexed) ...[
                if (index > 0) const SizedBox(width: 8),
                GlassScopePill(
                  icon: scope.icon,
                  label: scope.label,
                  active: widget.active == scope.key,
                  onTap: () => widget.onSelected(scope.key),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
