import 'package:flutter/material.dart';

import '../../core/i18n/i18n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass_popup_menu.dart';
import '../../core/lexical/hinata_editor.dart';
import '../../core/lexical/hinata_editor_controller.dart';
import '../../core/lexical/hinata_editor_tools.dart';
import '../../core/lexical/hinata_markdown_preview.dart';
import '../sprint/modals/glass_modal.dart' show showGlassErrorToast;
import 'data/knowledge_models.dart';
import 'data/knowledge_repository.dart';
import 'knowledge_place_field.dart';
import 'knowledge_scope.dart';
import 'knowledge_tokens.dart';
import 'widgets/knowledge_label_field.dart';
import '../../core/theme/app_type.dart';

/// Result handed back to the shell on Save / Publish.
class EditorResult {
  EditorResult(
    this.title,
    this.doc,
    this.spaceId, {
    this.projectId,
    this.teamId,
    this.labels = const [],
  });
  final String title;

  /// The page's labels as edited.
  final List<String> labels;

  /// The Lexical document to store.
  final String doc;
  final String spaceId;

  /// Where a new top-level page lives; both null keeps it to its author.
  /// Ignored for an edit, which never moves a page.
  final String? projectId;
  final String? teamId;
}

/// Page editor: the title first, a quiet line of properties (space, who
/// reads it, labels) under it, then the text. Saving and leaving live in the
/// app bar; the screen reaches them through [KnowledgeEditorState.save].
///
/// There is no preview pane and no Write/Preview switch any more. Those existed
/// because the writer typed markdown and could not see what it would become;
/// the editor now shows the document itself, so a second view of it would show
/// the same thing twice and take half the width doing it.
class KnowledgeEditor extends StatefulWidget {
  const KnowledgeEditor({
    super.key,
    required this.isNew,
    required this.initialTitle,
    required this.initialDoc,
    required this.spaceId,
    required this.onSave,
    this.initialBody = '',
    this.initialLabels = const [],
    this.choosePlace = false,
    this.onDirtyChanged,
    this.bottomPadding = 32,
  });

  /// Room under the text inside the scroll, so the end of a long page clears
  /// the floating navigation.
  final double bottomPadding;

  final List<String> initialLabels;

  /// Told when the page first differs from what was opened, and when it no
  /// longer does, so leaving can ask before throwing changes away.
  final ValueChanged<bool>? onDirtyChanged;

  final bool isNew;
  final String initialTitle;

  /// The stored Lexical document, or null for a new article.
  final String? initialDoc;

  /// The article's markdown. Normally the plain-text projection of
  /// [initialDoc]; on a row the server's backfill could not convert it is the
  /// only copy of the content there is, and the editor seeds from it rather
  /// than opening blank over it.
  final String initialBody;

  final String spaceId;
  final ValueChanged<EditorResult> onSave;

  /// Show "visible to" — for a new top-level page, which starts private.
  final bool choosePlace;

  @override
  State<KnowledgeEditor> createState() => KnowledgeEditorState();
}

class KnowledgeEditorState extends State<KnowledgeEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.initialTitle,
  );
  late final HinataEditorController _body = HinataEditorController(
    doc: documentOrLegacy(widget.initialDoc, widget.initialBody),
  );
  late String _spaceId = widget.spaceId;
  late List<String> _labels = [...widget.initialLabels];
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(_onChange);
    _body.addListener(_onChange);
  }

  /// Notes the first change. Once the page is dirty it stays so until saved:
  /// comparing the document serialises it, which is not worth doing on every
  /// keystroke only to notice an edit typed and undone.
  void _onChange() {
    if (_dirty) return;
    final dirty =
        _title.text.trim() != widget.initialTitle.trim() ||
        _spaceId != widget.spaceId ||
        !_sameLabels ||
        _body.isDirty;
    if (!dirty) return;
    _dirty = true;
    widget.onDirtyChanged?.call(true);
  }

  bool get _sameLabels =>
      _labels.length == widget.initialLabels.length &&
      _labels.every(widget.initialLabels.contains);

  /// Whether the page differs from what was opened.
  bool get isDirty => _dirty;

  /// A new page starts private: nobody but its author sees it until it is put
  /// into a project or a team.
  KbPlaceChoice _place = (projectId: null, teamId: null);

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Whether saving right now would write an empty document over content that
  /// is still there.
  ///
  /// The seed above makes this all but impossible, and "all but" is not a
  /// guarantee worth betting an article on: this is the one action in the app
  /// that can destroy a page of writing with a single click, and it costs two
  /// lines to make it impossible instead of unlikely.
  bool get _wouldBlankExistingContent =>
      _body.isEmpty &&
      (widget.initialBody.trim().isNotEmpty ||
          (widget.initialDoc ?? '').trim().isNotEmpty);

  /// Hands the page to [KnowledgeEditor.onSave], unless that would write an
  /// empty document over content that is still there.
  void save() {
    if (_wouldBlankExistingContent) {
      showGlassErrorToast(context, context.t('knowledge.saveWouldBlank'));
      return;
    }
    widget.onSave(
      EditorResult(
        _title.text.trim(),
        _body.doc,
        _spaceId,
        projectId: _place.projectId,
        teamId: _place.teamId,
        labels: _labels,
      ),
    );
    _body.markSaved();
    _dirty = false;
    widget.onDirtyChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final repo = KnowledgeScope.of(context).repo;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(KbTokens.radiusCard),
        border: Border.all(color: AppColors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, widget.bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _title,
              autofocus: widget.isNew,
              maxLines: null,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.next,
              style: TextStyle(
                fontFamily: AppTheme.fontBrand,
                fontSize: AppType.hero,
                fontWeight: FontWeight.w800,
                height: 1.15,
                letterSpacing: -0.6,
                color: AppColors.ink,
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: context.t('knowledge.articleTitleHint'),
                hintStyle: TextStyle(color: AppColors.inkSoft),
                // The hint goes when typing starts; the label names the field
                // for a screen reader all along.
                semanticCounterText: '',
              ),
            ),
            const SizedBox(height: 12),
            _properties(repo),
            const SizedBox(height: 12),
            Divider(height: 1, color: AppColors.hairline),
            const SizedBox(height: 8),
            HinataEditor(
              controller: _body,
              minHeight: 360,
              // Image upload and the mention picker, which need this host's
              // repository and resolver rather than the toolbar's.
              trailing: hinataEditorTools(context, _body),
            ),
          ],
        ),
      ),
    );
  }

  /// Space, who reads it, labels: one wrapping line, each opening a picker.
  Widget _properties(KnowledgeRepository repo) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        GlassPopupMenu<String>(
          value: _spaceId,
          width: 240,
          onSelected: (v) => setState(() {
            _spaceId = v;
            _onChange();
          }),
          items: [
            for (final s in repo.spaces)
              GlassMenuItem(
                value: s.id,
                label: s.name,
                leading: Icon(
                  lucideIcon(s.icon),
                  size: 16,
                  color: KbTokens.spaceChipText(s.hue),
                ),
              ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  lucideIcon(repo.spaceById(_spaceId)?.icon ?? 'layout-grid'),
                  size: 15,
                  color: AppColors.inkSoft,
                ),
                const SizedBox(width: 6),
                Text(
                  repo.spaceById(_spaceId)?.name ??
                      context.t('knowledge.editor.pickSpace'),
                  style: TextStyle(
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  lucideIcon('chevron-down'),
                  size: 15,
                  color: AppColors.inkSoft,
                ),
              ],
            ),
          ),
        ),
        if (widget.choosePlace)
          KnowledgePlaceField(
            repo: repo,
            projectId: _place.projectId,
            teamId: _place.teamId,
            onChanged: (place) => setState(() => _place = place),
          ),
        KnowledgeLabelField(
          labels: _labels,
          known: [for (final l in repo.labels()) l.label],
          onChanged: (labels) => setState(() {
            _labels = labels;
            _onChange();
          }),
        ),
      ],
    );
  }
}
