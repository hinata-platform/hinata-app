import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:wolt_modal_sheet/wolt_modal_sheet.dart';

import '../../core/api/api_client.dart';
import '../../core/api/hivora_repository.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Centered create-issue dialog for wider screens — mirrors the issue detail
/// sheet's modal chrome, capped to a comfortable single-column form width.
class _CreateDialogType extends WoltDialogType {
  const _CreateDialogType();

  @override
  BoxConstraints layoutModal(Size availableSize) {
    const pad = 48.0;
    final width =
        math.min(560.0, math.max(360.0, availableSize.width - pad * 2));
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      minHeight: 0,
      maxHeight: math.max(360, availableSize.height * 0.88),
    );
  }
}

/// Responsive *create* issue form, presented with the same modern Wolt modal
/// chrome as the issue detail sheet: a bottom sheet on phones, a centered
/// dialog on wider screens, with a persistent top bar (title + close). Editing
/// happens inline in the issue detail view, so this form is create-only.
Future<Issue?> showIssueForm(BuildContext context,
    {String? projectId, String? initialState}) {
  final repository = context.read<HivoraRepository>();
  return WoltModalSheet.show<Issue?>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    modalTypeBuilder: (ctx) => MediaQuery.sizeOf(ctx).width >= 760
        ? const _CreateDialogType()
        : WoltModalType.bottomSheet(),
    pageListBuilder: (modalContext) => [
      WoltModalSheetPage(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        hasTopBarLayer: true,
        isTopBarLayerAlwaysVisible: true,
        topBarTitle: Text(
          context.t('issues.new'),
          style: const TextStyle(
              fontFamily: AppTheme.fontBrand,
              fontSize: 16,
              fontWeight: FontWeight.w700),
        ),
        trailingNavBarWidget: IconButton(
          onPressed: () => Navigator.of(modalContext).maybePop(),
          icon: Icon(Icons.close_rounded, color: AppColors.inkSoft),
        ),
        child: RepositoryProvider.value(
          value: repository,
          child: _IssueFormBody(
              projectId: projectId, initialState: initialState),
        ),
      ),
    ],
  );
}

class _IssueFormBody extends StatefulWidget {
  const _IssueFormBody({this.projectId, this.initialState});

  final String? projectId;
  final String? initialState;

  @override
  State<_IssueFormBody> createState() => _IssueFormBodyState();
}

class _IssueFormBodyState extends State<_IssueFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  List<Project> _projects = const [];
  String? _projectId;
  String _type = 'TASK';
  String _priority = 'NORMAL';
  bool _saving = false;
  String? _error;

  static const _types = ['TASK', 'BUG', 'FEATURE', 'EPIC'];
  static const _priorities = ['SHOWSTOPPER', 'CRITICAL', 'MAJOR', 'NORMAL', 'MINOR'];

  @override
  void initState() {
    super.initState();
    _projectId = widget.projectId;
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await context.read<HivoraRepository>().projects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _projectId ??= projects.isNotEmpty ? projects.first.id : null;
      });
    } on ApiFailure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _projectId,
              decoration: InputDecoration(labelText: context.t('issues.project')),
              items: [
                for (final project in _projects)
                  DropdownMenuItem(
                    value: project.id,
                    child: Text('${project.key} – ${project.name}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _projectId = value),
              validator: (value) =>
                  value == null ? context.t('errors.required') : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: context.t('issues.title')),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? context.t('errors.required')
                  : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              decoration:
                  InputDecoration(labelText: context.t('issues.description')),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration:
                        InputDecoration(labelText: context.t('issues.type')),
                    items: [
                      for (final type in _types)
                        DropdownMenuItem(
                          value: type,
                          child: Text(context.t('type.${type.toLowerCase()}')),
                        ),
                    ],
                    onChanged: (value) => setState(() => _type = value ?? 'TASK'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _priority,
                    decoration:
                        InputDecoration(labelText: context.t('issues.priority')),
                    items: [
                      for (final priority in _priorities)
                        DropdownMenuItem(
                          value: priority,
                          child:
                              Text(context.t('priority.${priority.toLowerCase()}')),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _priority = value ?? 'NORMAL'),
                  ),
                ),
              ],
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
                      child: CircularProgressIndicator(
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
    final repository = context.read<HivoraRepository>();
    try {
      final result = await repository.createIssue({
        'projectId': _projectId,
        'title': _title.text.trim(),
        'description': _description.text,
        'type': _type,
        'priority': _priority,
        if (widget.initialState != null) 'state': widget.initialState,
      });
      if (mounted) Navigator.of(context).pop(result);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }
}
