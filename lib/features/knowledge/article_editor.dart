import 'package:flutter/material.dart';
import '../../core/widgets/hive_loader.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/content_models.dart';
import '../../core/theme/app_colors.dart';

/// Create or edit a knowledge base article (Markdown content).
Future<Article?> showArticleEditor(BuildContext context,
    {Article? existing, String? parentId}) {
  final repository = context.read<HivoraRepository>();
  return WoltModalSheet.show<Article?>(
    context: context,
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: AppColors.surface,
        hasTopBarLayer: false,
        child: RepositoryProvider.value(
          value: repository,
          child: _ArticleEditorBody(existing: existing, parentId: parentId),
        ),
      ),
    ],
  );
}

class _ArticleEditorBody extends StatefulWidget {
  const _ArticleEditorBody({this.existing, this.parentId});

  final Article? existing;
  final String? parentId;

  @override
  State<_ArticleEditorBody> createState() => _ArticleEditorBodyState();
}

class _ArticleEditorBodyState extends State<_ArticleEditorBody> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _content = TextEditingController(text: widget.existing?.content);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t(widget.existing != null
                  ? 'knowledge.edit'
                  : 'knowledge.new'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _title,
              decoration:
                  InputDecoration(labelText: context.t('knowledge.articleTitle')),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? context.t('errors.required')
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _content,
              minLines: 8,
              maxLines: 16,
              decoration: InputDecoration(
                labelText: context.t('knowledge.content'),
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: HiveLoader(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(context.t('common.save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final article = await context.read<HivoraRepository>().saveArticle(
            id: widget.existing?.id,
            title: _title.text.trim(),
            content: _content.text,
            parentId: widget.existing?.parentId ?? widget.parentId,
          );
      if (mounted) Navigator.of(context).pop(article);
    } on ApiFailure catch (failure) {
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }
}
