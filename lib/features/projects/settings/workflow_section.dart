import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import 'settings_common.dart';

/// Workflow states card: reorderable, renamable, colored rows with a Resolved
/// toggle. Enforces the >= 2 states guard on delete (UI side).
class WorkflowSection extends StatefulWidget {
  const WorkflowSection({
    super.key,
    required this.states,
    required this.resolved,
    required this.onRename,
    required this.onRecolor,
    required this.onReorder,
    required this.onToggleResolved,
    required this.onDelete,
    required this.onAdd,
  });

  final List<WorkflowState> states;
  final List<String> resolved;
  final void Function(String id, String name) onRename;
  final void Function(String id, int hue) onRecolor;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onToggleResolved; // by state name
  final ValueChanged<String> onDelete; // by state id
  final VoidCallback onAdd;

  @override
  State<WorkflowSection> createState() => _WorkflowSectionState();
}

class _WorkflowSectionState extends State<WorkflowSection> {
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final s in widget.states) {
      _controllers[s.id] = TextEditingController(text: s.name);
    }
  }

  @override
  void didUpdateWidget(covariant WorkflowSection old) {
    super.didUpdateWidget(old);
    final ids = widget.states.map((s) => s.id).toSet();
    for (final s in widget.states) {
      _controllers.putIfAbsent(s.id, () => TextEditingController(text: s.name));
    }
    _controllers.keys
        .where((id) => !ids.contains(id))
        .toList()
        .forEach((id) => _controllers.remove(id)?.dispose());
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = widget.states.length > 2;
    return SettingsSection(
      title: context.t('projectSettings.workflow'),
      note: context.t('projectSettings.workflowNote'),
      trailing: Text(
        context.t(
          'projectSettings.statesResolved',
          variables: {
            'states': '${widget.states.length}',
            'resolved': '${widget.resolved.length}',
          },
        ),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.inkFaint,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            // Default proxy wraps the row in an elevated square Material with a
            // hard shadow; render it transparently so the row keeps its own
            // rounded card while dragging.
            proxyDecorator: (child, index, animation) =>
                Material(type: MaterialType.transparency, child: child),
            itemCount: widget.states.length,
            onReorderItem: widget.onReorder,
            itemBuilder: (context, i) {
              final s = widget.states[i];
              final isResolved = widget.resolved.contains(s.name);
              return Padding(
                key: ValueKey(s.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _StateRow(
                  index: i,
                  state: s,
                  controller: _controllers[s.id]!,
                  isResolved: isResolved,
                  canDelete: canDelete,
                  onRename: (v) => widget.onRename(s.id, v),
                  onPickColor: (hue) => widget.onRecolor(s.id, hue),
                  onToggleResolved: () => widget.onToggleResolved(s.name),
                  onDelete: () => widget.onDelete(s.id),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: widget.onAdd,
            icon: const Icon(LucideIcons.plus, size: 16),
            label: Text(context.t('projectSettings.addState')),
          ),
        ],
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({
    required this.index,
    required this.state,
    required this.controller,
    required this.isResolved,
    required this.canDelete,
    required this.onRename,
    required this.onPickColor,
    required this.onToggleResolved,
    required this.onDelete,
  });

  final int index;
  final WorkflowState state;
  final TextEditingController controller;
  final bool isResolved;
  final bool canDelete;
  final ValueChanged<String> onRename;
  final ValueChanged<int> onPickColor;
  final VoidCallback onToggleResolved;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
      decoration: BoxDecoration(
        color: isResolved ? hueSoft(155) : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(
          color: isResolved ? hueBorder(155) : AppColors.hairline,
        ),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                LucideIcons.gripVertical,
                size: 18,
                color: AppColors.inkFaint,
              ),
            ),
          ),
          GlassHuePicker(hue: state.hue, onPick: onPickColor, size: 11),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onRename,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
              // Transparent field; only an accent underline appears on focus,
              // matching the reference (`.st-in`).
              decoration: const InputDecoration(
                isDense: true,
                filled: false,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.transparent),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _ResolvedPill(on: isResolved, onTap: onToggleResolved),
          IconButton(
            tooltip: context.t('projectSettings.removeState'),
            visualDensity: VisualDensity.compact,
            onPressed: canDelete ? onDelete : null,
            icon: Icon(
              LucideIcons.trash2,
              size: 18,
              color: canDelete ? AppColors.inkSoft : AppColors.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolvedPill extends StatelessWidget {
  const _ResolvedPill({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final green = hueChipText(155);
    return Material(
      color: on ? hueSoft(155) : AppColors.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            border: Border.all(color: on ? hueBorder(155) : AppColors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                on ? LucideIcons.circleCheckBig : LucideIcons.circle,
                size: 14,
                color: on ? green : AppColors.inkFaint,
              ),
              const SizedBox(width: 6),
              Text(
                context.t('projectSettings.resolved'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: on ? green : AppColors.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
