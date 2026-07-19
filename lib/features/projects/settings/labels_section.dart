import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/models/work_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/hue_colors.dart';
import 'settings_common.dart';

/// Labels card: colored, renamable chips with a recolor picker, plus add.
class LabelsSection extends StatefulWidget {
  const LabelsSection({
    super.key,
    required this.labels,
    required this.onRename,
    required this.onRecolor,
    required this.onRemove,
    required this.onAdd,
  });

  final List<ProjectLabel> labels;
  final void Function(String id, String name) onRename;
  final void Function(String id, int hue) onRecolor;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onAdd;

  @override
  State<LabelsSection> createState() => _LabelsSectionState();
}

class _LabelsSectionState extends State<LabelsSection> {
  final _controllers = <String, TextEditingController>{};
  final _addController = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final l in widget.labels) {
      _controllers[l.id] = TextEditingController(text: l.name);
    }
  }

  @override
  void didUpdateWidget(covariant LabelsSection old) {
    super.didUpdateWidget(old);
    final ids = widget.labels.map((l) => l.id).toSet();
    // Add controllers for new labels; drop removed ones.
    for (final l in widget.labels) {
      _controllers.putIfAbsent(l.id, () => TextEditingController(text: l.name));
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
    _addController.dispose();
    super.dispose();
  }

  void _submitAdd() {
    final name = _addController.text.trim();
    if (name.isEmpty) return;
    widget.onAdd(name);
    _addController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('projectSettings.labels'),
      note: context.t('projectSettings.labelsNote'),
      trailing: Text(
        '${widget.labels.length}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.inkFaint,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.labels.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                context.t('projectSettings.noLabels'),
                style: TextStyle(color: AppColors.inkSoft, fontSize: 12.5),
              ),
            )
          else
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final l in widget.labels)
                  _LabelChip(
                    label: l,
                    controller: _controllers[l.id]!,
                    onRename: (v) => widget.onRename(l.id, v),
                    onPickColor: (hue) => widget.onRecolor(l.id, hue),
                    onRemove: () => widget.onRemove(l.id),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          _AddLabelRow(controller: _addController, onAdd: _submitAdd),
        ],
      ),
    );
  }
}

class _LabelChip extends StatelessWidget {
  const _LabelChip({
    required this.label,
    required this.controller,
    required this.onRename,
    required this.onPickColor,
    required this.onRemove,
  });

  final ProjectLabel label;
  final TextEditingController controller;
  final ValueChanged<String> onRename;
  final ValueChanged<int> onPickColor;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ink = hueChipText(label.hue);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      decoration: BoxDecoration(
        color: hueSoft(label.hue),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(color: hueBorder(label.hue)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GlassHuePicker(hue: label.hue, onPick: onPickColor),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40, maxWidth: 130),
            child: IntrinsicWidth(
              child: TextField(
                controller: controller,
                onChanged: onRename,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
                // Transparent inside the chip; an underline in the label's own
                // ink appears on focus (reference `.lbl-in:focus`).
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(vertical: 2),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.transparent),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: ink, width: 1.2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            customBorder: const CircleBorder(),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: ink.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(LucideIcons.x, size: 13, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddLabelRow extends StatelessWidget {
  const _AddLabelRow({required this.controller, required this.onAdd});
  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, minWidth: 180),
          child: TextField(
            controller: controller,
            onSubmitted: (_) => onAdd(),
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            decoration: settingsInput(
              context,
              hint: context.t('projectSettings.addLabelHint'),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(LucideIcons.plus, size: 16),
          label: Text(context.t('projectSettings.add')),
        ),
      ],
    );
  }
}
