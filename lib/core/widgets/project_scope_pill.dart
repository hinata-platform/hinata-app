import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/work_models.dart';
import 'glass_filter_bar.dart';
import 'glass_popup_menu.dart';

/// The one project a page is about, as a glass pill that opens the list of
/// projects to switch to (Gantt, reports).
///
/// Never washed amber: these pages always show exactly one project, so there
/// is no unscoped state for the wash to mark.
class ProjectScopePill extends StatelessWidget {
  const ProjectScopePill({
    super.key,
    required this.projects,
    required this.selected,
    required this.onChanged,
  });

  final List<Project> projects;
  final String? selected;
  final ValueChanged<String> onChanged;

  Project get _current =>
      projects.where((p) => p.id == selected).firstOrNull ?? projects.first;

  Future<void> _pick(BuildContext context, Rect? anchor) async {
    // Null means the pill is no longer on screen: nothing to hang a menu off.
    if (anchor == null) return;
    final chosen = await showGlassMenu<String>(
      context: context,
      anchorRect: anchor,
      value: _current.id,
      items: [
        for (final p in projects) GlassMenuItem(value: p.id, label: p.name),
      ],
    );
    if (chosen != null && chosen != _current.id) onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) => GlassFilterPill(
    icon: LucideIcons.folderKanban,
    label: _current.name,
    active: false,
    onTap: (anchor) => unawaited(_pick(context, anchor)),
  );
}
