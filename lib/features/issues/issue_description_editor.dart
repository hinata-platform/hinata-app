import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/markdown_toolbar.dart';
import '../knowledge/knowledge_tokens.dart';
import '../knowledge/markdown/markdown_renderer.dart';
import '../knowledge/markdown/mention_field.dart';

/// Issue description editor with the *same* authoring power as a KB article — the
/// shared [MarkdownToolbar] plus `@`-smart-links (issues · articles · people) —
/// but kept compact for the issue layout: instead of a side-by-side
/// source⇄preview split, a short **Editor / Vorschau** tab switcher toggles
/// between writing markdown and previewing the rendered draft.
///
/// Operates on [controller] in place; the host owns Save / Cancel.
class IssueDescriptionEditor extends StatefulWidget {
  const IssueDescriptionEditor({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<IssueDescriptionEditor> createState() => _IssueDescriptionEditorState();
}

class _IssueDescriptionEditorState extends State<IssueDescriptionEditor> {
  final FocusNode _focus = FocusNode();
  final List<TapGestureRecognizer> _sink = [];
  late final MarkdownEditingActions _actions = MarkdownEditingActions(
    widget.controller,
    _focus,
  );
  bool _preview = false;

  TextEditingController get _ctrl => widget.controller;

  @override
  void dispose() {
    _focus.dispose();
    for (final r in _sink) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(KbTokens.radiusControl),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MarkdownToolbar(
            actions: _actions,
            enabled: !_preview,
            dense: true,
            trailing: _tabs(),
          ),
          SizedBox(height: 220, child: _preview ? _previewPane() : _editPane()),
        ],
      ),
    );
  }

  Widget _tabs() {
    Widget tab(bool preview, String label) {
      final on = _preview == preview;
      return GestureDetector(
        onTap: () => setState(() => _preview = preview),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: on ? AppColors.surface : null,
            borderRadius: BorderRadius.circular(7),
            boxShadow: on
                ? [
                    BoxShadow(
                      color: AppColors.navyDeep.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? AppColors.ink : AppColors.inkSoft,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.canvas2,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab(false, context.t('issues.tabEditor')),
          const SizedBox(width: 3),
          tab(true, context.t('issues.tabPreview')),
        ],
      ),
    );
  }

  Widget _editPane() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 4),
      child: MentionField(
        controller: _ctrl,
        focusNode: _focus,
        expands: true,
        monospace: true,
        hintText:
            'Write in markdown… type @ to link an issue, article or teammate.',
        onTabIndent: () {},
      ),
    );
  }

  Widget _previewPane() {
    for (final r in _sink) {
      r.dispose();
    }
    _sink.clear();
    final text = _ctrl.text.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: text.isEmpty
          ? Text(
              context.t('issues.previewEmpty'),
              style: TextStyle(color: AppColors.inkFaint),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: KbMarkdownParser(fontSize: 14, sink: _sink)
                  .parse(_ctrl.text)
                  .nodes,
            ),
    );
  }
}
