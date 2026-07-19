import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/markdown_image_upload.dart';
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
  const IssueDescriptionEditor({
    super.key,
    required this.controller,
    this.label,
  });

  final TextEditingController controller;

  /// Optional section label (e.g. “DESCRIPTION”) rendered on the same row as
  /// the Editor/Preview switcher, floating above the bordered editor box.
  final Widget? label;

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

  // Memoized preview: the parse (and the gesture recognizers it creates) is
  // only redone when the source text actually changes, not on every unrelated
  // rebuild of the host form — re-parsing in build() dropped frames and
  // disposed recognizers still referenced by the mounted RichText.
  String? _previewSource;
  List<Widget> _previewNodes = const [];

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header: section label (left) + Editor/Preview switcher floated
        // right, sitting above the bordered editor box so the toolbar below
        // is free to use the full width for a single scrollable command row.
        Row(
          children: [
            if (widget.label != null)
              Expanded(child: widget.label!)
            else
              const Spacer(),
            _tabs(),
          ],
        ),
        const SizedBox(height: 8),
        Container(
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
                onImage: () => pickAndInsertMarkdownImage(context, _actions),
              ),
              SizedBox(
                height: 220,
                child: _preview ? _previewPane() : _editPane(),
              ),
            ],
          ),
        ),
      ],
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
        hintText: context.t('issues.descriptionHint'),
        onTabIndent: () {},
      ),
    );
  }

  Widget _previewPane() {
    final source = _ctrl.text;
    // Only re-parse (and only then dispose + rebuild the recognizers) when the
    // text has actually changed since the last preview render.
    if (source != _previewSource) {
      for (final r in _sink) {
        r.dispose();
      }
      _sink.clear();
      _previewSource = source;
      _previewNodes = source.trim().isEmpty
          ? const []
          : KbMarkdownParser(fontSize: 14, sink: _sink).parse(source).nodes;
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: source.trim().isEmpty
          ? Text(
              context.t('issues.previewEmpty'),
              style: TextStyle(color: AppColors.inkFaint),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _previewNodes,
            ),
    );
  }
}
