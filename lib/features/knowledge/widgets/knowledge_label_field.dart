import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_type.dart';
import '../../sprint/modals/glass_modal.dart'
    show
        anchorRectOfContext,
        kGlassPopoverBreakpoint,
        showGlassAnchoredPopover,
        showGlassBottomSheet;
import 'knowledge_widgets.dart';

/// Longest label the field accepts; the server keeps labels as short strings.
const int kKbLabelMaxLength = 40;

/// A page's labels as one line: the chosen ones as chips, and a control that
/// opens a searchable glass picker to add, create or remove them.
class KnowledgeLabelField extends StatelessWidget {
  const KnowledgeLabelField({
    super.key,
    required this.labels,
    required this.known,
    required this.onChanged,
  });

  /// The labels the page carries.
  final List<String> labels;

  /// Labels on pages the reader sees, most used first, to choose from.
  final List<String> known;
  final ValueChanged<List<String>> onChanged;

  Future<void> _pick(BuildContext context) async {
    final panel = _LabelPanel(selected: labels, known: known);
    final wide = MediaQuery.sizeOf(context).width >= kGlassPopoverBreakpoint;
    final anchor = anchorRectOfContext(context);
    final result = wide && anchor != null
        ? await showGlassAnchoredPopover<List<String>>(
            context,
            anchorRect: anchor,
            width: 320,
            minHeight: 200,
            maxHeight: 420,
            builder: (_) => panel,
          )
        : await showGlassBottomSheet<List<String>>(
            context,
            builder: (_) => SizedBox(height: 420, child: panel),
          );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final l in labels) KbLabelChip(label: l),
        Builder(
          builder: (context) => Semantics(
            button: true,
            child: InkWell(
              onTap: () => _pick(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.tag, size: 15, color: AppColors.inkSoft),
                      const SizedBox(width: 6),
                      // Flexible, so a large text size wraps the label
                      // rather than running off the screen.
                      Flexible(
                        child: Text(
                          context.t(
                            labels.isEmpty
                                ? 'knowledge.labels.add'
                                : 'knowledge.labels.edit',
                          ),
                          style: TextStyle(
                            fontSize: AppType.label,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabelPanel extends StatefulWidget {
  const _LabelPanel({required this.selected, required this.known});

  final List<String> selected;
  final List<String> known;

  @override
  State<_LabelPanel> createState() => _LabelPanelState();
}

class _LabelPanelState extends State<_LabelPanel> {
  late final List<String> _selected = [...widget.selected];
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// A label as stored: trimmed, inner whitespace collapsed, bounded.
  static String _clean(String raw) {
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return text.length > kKbLabelMaxLength
        ? text.substring(0, kKbLabelMaxLength)
        : text;
  }

  void _toggle(String label) => setState(() {
    _selected.contains(label) ? _selected.remove(label) : _selected.add(label);
  });

  void _create() {
    final label = _clean(_query.text);
    if (label.isEmpty) return;
    setState(() {
      if (!_selected.contains(label)) _selected.add(label);
      _query.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    // The page's own labels first, so what is set is seen before what could be.
    final options = {
      ...widget.selected,
      ...widget.known,
      ..._selected,
    }.where((l) => q.isEmpty || l.toLowerCase().contains(q)).toList();
    final exact = options.any(
      (l) => l.toLowerCase() == _clean(q).toLowerCase(),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _query,
            focusNode: _focus,
            maxLength: kKbLabelMaxLength,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontSize: AppType.body),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              labelText: context.t('knowledge.labels.search'),
              prefixIcon: Icon(
                LucideIcons.search,
                size: 17,
                color: AppColors.inkSoft,
              ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                borderSide: BorderSide(color: AppColors.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                borderSide: BorderSide(color: AppColors.hairline),
              ),
            ),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              if (q.isNotEmpty && !exact)
                _Option(
                  icon: LucideIcons.plus,
                  label: context.t(
                    'knowledge.labels.create',
                    variables: {'label': _clean(_query.text)},
                  ),
                  onTap: _create,
                ),
              for (final l in options)
                _Option(
                  icon: _selected.contains(l)
                      ? LucideIcons.squareCheck
                      : LucideIcons.square,
                  label: l,
                  selected: _selected.contains(l),
                  onTap: () => _toggle(l),
                ),
              if (options.isEmpty && q.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    context.t('knowledge.labels.none'),
                    style: TextStyle(
                      fontSize: AppType.label,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: AppColors.hairline),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_selected),
              child: Text(context.t('knowledge.labels.done')),
            ),
          ),
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Null for an action row, a checked state for a label.
  final bool? selected;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(
      button: selected == null,
      checked: selected,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    icon,
                    size: 17,
                    color: selected == true
                        ? AppColors.accentInk
                        : AppColors.inkSoft,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.body,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
