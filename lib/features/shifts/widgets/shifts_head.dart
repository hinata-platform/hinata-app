import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass_filter_bar.dart'
    show GlassFilterPill, kGlassControlHeight;
import '../../../core/widgets/glass_popup_menu.dart';
import '../../../core/widgets/glass_scope_row.dart';
import '../../../core/widgets/hive_widgets.dart' show PageHead;
import '../shift_views.dart';

List<GlassScope> _scopes(BuildContext context) => [
  for (final view in ShiftsView.values)
    (key: view.name, icon: view.icon, label: context.t(view.labelKey)),
];

void _go(BuildContext context, ShiftsView current, String key) {
  final view = ShiftsView.byName(key);
  // Going, not pushing: the three are one place seen three ways.
  if (view != null && view != current) context.go(view.route);
}

/// The module's head on a wide window: its name, then the three scope pills
/// (Meine, Kalender, Events), and under them the view's own [filters].
class ShiftsHead extends StatelessWidget {
  const ShiftsHead({super.key, required this.current, this.filters});

  final ShiftsView current;
  final Widget? filters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        context.pageGutter,
        18 + context.topGutter,
        context.pageGutter,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IntrinsicWidth(child: PageHead(title: context.t('nav.shifts'))),
              GlassScopeRow(
                scopes: _scopes(context),
                active: current.name,
                onSelected: (key) => _go(context, current, key),
              ),
            ],
          ),
          if (filters != null) ...[const SizedBox(height: 14), filters!],
        ],
      ),
    );
  }
}

/// The phone's docked row: the view on screen as one pill that opens the
/// other two, then the view's own [filters], scrolling sideways together.
class ShiftsDock extends StatelessWidget {
  const ShiftsDock({super.key, required this.current, this.filters = const []});

  final ShiftsView current;
  final List<Widget> filters;

  @override
  Widget build(BuildContext context) {
    final gutter = context.pageGutter;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        height: kGlassControlHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Row(
            children: [
              Tooltip(
                message: context.t('shifts.view.menu'),
                child: GlassFilterPill(
                  icon: current.icon,
                  label: context.t(current.labelKey),
                  active: current != ShiftsView.mine,
                  onTap: (anchor) => unawaited(_pick(context, anchor)),
                ),
              ),
              for (final filter in filters) ...[
                const SizedBox(width: 8),
                filter,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context, Rect? anchor) async {
    if (anchor == null) return;
    final picked = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor,
      width: 240,
      value: current.name,
      items: [
        for (final scope in _scopes(context))
          GlassMenuItem(
            value: scope.key,
            label: scope.label,
            leading: Icon(scope.icon, size: 16, color: AppColors.inkSoft),
          ),
      ],
    );
    if (picked == null || !context.mounted) return;
    _go(context, current, picked);
  }
}
