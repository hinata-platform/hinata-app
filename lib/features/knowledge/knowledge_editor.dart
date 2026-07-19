import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/widgets/markdown_image_upload.dart';
import '../../core/widgets/markdown_toolbar.dart';
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_scope.dart';
import 'knowledge_tokens.dart';
import 'markdown/markdown_renderer.dart';
import 'markdown/mention_field.dart';

/// Result handed back to the shell on Save / Publish.
class EditorResult {
  EditorResult(this.title, this.body, this.spaceId);
  final String title;
  final String body;
  final String spaceId;
}

/// Full markdown editor: title + space picker, formatting toolbar, and a split
/// markdown source ⇄ live preview that collapses to Write / Preview tabs below
/// ~760 px. Toolbar commands mirror the reference `linePrefix` / `surround` /
/// `insertBlock` helpers exactly.
class KnowledgeEditor extends StatefulWidget {
  const KnowledgeEditor({
    super.key,
    required this.isNew,
    required this.initialTitle,
    required this.initialBody,
    required this.spaceId,
    required this.onSave,
    required this.onCancel,
  });

  final bool isNew;
  final String initialTitle;
  final String initialBody;
  final String spaceId;
  final ValueChanged<EditorResult> onSave;
  final VoidCallback onCancel;

  @override
  State<KnowledgeEditor> createState() => _KnowledgeEditorState();
}

class _KnowledgeEditorState extends State<KnowledgeEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  late final TextEditingController _body = TextEditingController(
    text: widget.initialBody,
  );
  final FocusNode _bodyFocus = FocusNode();
  late final MarkdownEditingActions _actions = MarkdownEditingActions(
    _body,
    _bodyFocus,
  );
  late String _spaceId = widget.spaceId;
  String _tab = 'write'; // write | preview (narrow only)
  final List<TapGestureRecognizer> _recognizerSink = [];

  @override
  void initState() {
    super.initState();
    _body.addListener(_onBodyChanged);
  }

  void _onBodyChanged() => setState(() {});

  @override
  void dispose() {
    _body.removeListener(_onBodyChanged);
    for (final r in _recognizerSink) {
      r.dispose();
    }
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _save() =>
      widget.onSave(EditorResult(_title.text.trim(), _body.text, _spaceId));

  @override
  Widget build(BuildContext context) {
    final repo = KnowledgeScope.of(context).repo;
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = constraints.maxWidth >= KbTokens.editorSplit;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(KbTokens.radiusCard),
            border: Border.all(color: AppColors.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _head(repo),
              _toolbar(split),
              Expanded(child: _body0(split, repo)),
            ],
          ),
        );
      },
    );
  }

  Widget _head(KnowledgeRepository repo) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 380),
            child: TextField(
              controller: _title,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              style: const TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: context.t('knowledge.articleTitleHint'),
                hintStyle: TextStyle(color: AppColors.inkFaint),
              ),
            ),
          ),
          GlassPopupMenu<String>(
            value: _spaceId,
            width: 220,
            onSelected: (v) => setState(() => _spaceId = v),
            items: [
              for (final s in repo.spaces)
                GlassMenuItem(
                  value: s.id,
                  label: s.name,
                  leading: Icon(
                    lucideIcon(s.icon),
                    size: 16,
                    color: KbTokens.accent,
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(lucideIcon('hash'), size: 15, color: AppColors.inkFaint),
                const SizedBox(width: 6),
                Text(
                  repo.spaceById(_spaceId)?.name ?? '',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  lucideIcon('chevron-down'),
                  size: 15,
                  color: AppColors.inkFaint,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: widget.onCancel,
            child: Text(context.t('common.cancel')),
          ),
          FilledButton.icon(
            onPressed: _save,
            icon: Icon(lucideIcon('check'), size: 16),
            label: Text(
              widget.isNew
                  ? context.t('knowledge.publish')
                  : context.t('common.save'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(bool split) => MarkdownToolbar(
    actions: _actions,
    trailing: split ? null : _tabs(),
    onImage: () => pickAndInsertMarkdownImage(context, _actions),
  );

  Widget _tabs() {
    Widget tab(String id, String label) {
      final on = _tab == id;
      return GestureDetector(
        onTap: () => setState(() => _tab = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
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
              fontSize: 12.5,
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
          tab('write', context.t('issues.tabEditor')),
          const SizedBox(width: 3),
          tab('preview', context.t('issues.tabPreview')),
        ],
      ),
    );
  }

  Widget _body0(bool split, KnowledgeRepository repo) {
    final showWrite = split || _tab == 'write';
    final showPreview = split || _tab == 'preview';
    if (split) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _writePane()),
          Container(width: 1, color: AppColors.hairline),
          Expanded(child: _previewPane()),
        ],
      );
    }
    return showWrite
        ? _writePane()
        : showPreview
        ? _previewPane()
        : const SizedBox();
  }

  Widget _writePane() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: MentionField(
        controller: _body,
        focusNode: _bodyFocus,
        expands: true,
        monospace: true,
        hintText: context.t('knowledge.writeHint'),
        onTabIndent: () {},
      ),
    );
  }

  Widget _previewPane() {
    // Dispose previous link recognizers before reparsing.
    for (final r in _recognizerSink) {
      r.dispose();
    }
    _recognizerSink.clear();
    final parser = KbMarkdownParser(sink: _recognizerSink);
    final parsed = parser.parse(_body.text);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_title.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                _title.text.trim(),
                style: const TextStyle(
                  fontFamily: AppTheme.fontBrand,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ),
          if (_body.text.trim().isEmpty)
            Text(
              context.t('knowledge.nothingToPreview'),
              style: TextStyle(color: AppColors.inkFaint),
            )
          else
            ...parsed.nodes,
        ],
      ),
    );
  }
}
