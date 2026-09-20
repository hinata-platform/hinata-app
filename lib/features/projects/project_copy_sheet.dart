import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/project_template_models.dart';
import '../../core/models/work_models.dart';
import '../../core/repositories/project_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hive_widgets.dart';
import '../sprint/modals/glass_modal.dart';
import 'project_key.dart';

/// Which of the two ways in somebody took.
enum ProjectCopyMode {
  /// "Copy …" — every switch is offered, the date is optional.
  copy,

  /// "Create a project from this" — the scope is decided and the date is the
  /// point of the exercise.
  instantiate,
}

/// Opens the copy sheet and returns the project it produced, or null when
/// nobody went through with it.
///
/// One sheet for both ways in. They differ in what is fixed, not in what they
/// do: instantiating is the same copy with the switches decided, and having two
/// sheets would mean two places to keep the key check and the counts right.
Future<ProjectCopyResult?> showProjectCopySheet(
  BuildContext context, {
  required Project source,
  required ProjectCopyMode mode,
}) {
  final projects = context.read<ProjectRepository>();
  return showGlassModal<ProjectCopyResult>(
    context,
    width: 560,
    builder: (modalContext) => RepositoryProvider.value(
      value: projects,
      child: _ProjectCopyBody(source: source, mode: mode),
    ),
  );
}

class _ProjectCopyBody extends StatefulWidget {
  const _ProjectCopyBody({required this.source, required this.mode});

  final Project source;
  final ProjectCopyMode mode;

  @override
  State<_ProjectCopyBody> createState() => _ProjectCopyBodyState();
}

class _ProjectCopyBodyState extends State<_ProjectCopyBody> {
  final _name = TextEditingController();
  final _key = TextEditingController();
  DateTime? _eventDate;

  bool _includeMembers = true;
  bool _includeAttachments = false;
  bool _includeTimeSettings = true;
  bool _includeBoard = false;

  ProjectCopyScope? _scope;
  bool _loadingScope = true;
  bool _saving = false;
  String? _error;

  bool get _isInstantiate => widget.mode == ProjectCopyMode.instantiate;

  @override
  void initState() {
    super.initState();
    _name.text = _isInstantiate ? '' : '${widget.source.name} 2';
    _eventDate = _isInstantiate ? null : widget.source.eventDate;
    _loadScope();
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _loadScope() async {
    try {
      final scope = await context.read<ProjectRepository>().scopeOfCopy(
        widget.source.id,
      );
      if (!mounted) return;
      setState(() {
        _scope = scope;
        _loadingScope = false;
        if (_key.text.isEmpty) _key.text = scope.suggestedKey;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loadingScope = false;
        _error = failure.message;
      });
    }
  }

  /// Whether the form may be submitted: a name, a key of the shape the server
  /// accepts, and a project that is not too large to copy at all.
  bool get _valid {
    if (_saving || _loadingScope) return false;
    if (_scope?.withinLimit == false) return false;
    if (_name.text.trim().isEmpty) return false;
    final key = _key.text.trim();
    // Empty is allowed: the server suggests one. Anything else holds to the
    // shape every other key field in the app holds to.
    return key.isEmpty || isProjectKey(key);
  }

  Future<void> _submit() async {
    if (!_valid) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = context.read<ProjectRepository>();
      final result = _isInstantiate
          ? await repo.instantiateTemplate(
              widget.source.id,
              name: _name.text.trim(),
              key: _key.text.trim(),
              eventDate: _eventDate,
            )
          : await repo.copyProject(
              widget.source.id,
              name: _name.text.trim(),
              key: _key.text.trim(),
              eventDate: _eventDate,
              includeMembers: _includeMembers,
              includeAttachments: _includeAttachments,
              includeTimeSettings: _includeTimeSettings,
              includeBoard: _includeBoard,
            );
      if (mounted) Navigator.of(context).pop(result);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      // The failure stays in the sheet with everything still filled in: "too
      // many issues" names its limit, and retyping a form to read the reason
      // for a refusal is the worst possible way to learn it.
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _pickEventDate() async {
    final picked = await showGlassDatePicker(
      context,
      title: context.t('projects.copy.eventDate'),
      initialDate: _eventDate ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) setState(() => _eventDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: _isInstantiate ? LucideIcons.sparkles : LucideIcons.copy,
          title: context.t(
            _isInstantiate ? 'projects.copy.fromTemplate' : 'projects.copy.title',
          ),
          subtitle: widget.source.name,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GlassField(
                  label: context.t('projects.copy.name'),
                  child: TextField(
                    controller: _name,
                    autofocus: true,
                    decoration: glassInputDecoration(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                GlassField(
                  label: context.t('projects.copy.key'),
                  child: TextField(
                    controller: _key,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(10),
                      const ProjectKeyFormatter(),
                    ],
                    style: const TextStyle(
                      fontFamily: AppTheme.fontMono,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: glassInputDecoration(
                      hint: scope?.suggestedKey,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                GlassField(
                  label: context.t('projects.copy.eventDate'),
                  child: _dateRow(),
                ),
                if (!_isInstantiate) ...[
                  const SizedBox(height: 16),
                  Text(
                    context.t('projects.copy.include'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Toggle(
                    label: context.t('projects.copy.members'),
                    value: _includeMembers,
                    onChanged: (v) => setState(() => _includeMembers = v),
                  ),
                  _Toggle(
                    label: context.t('projects.copy.attachments'),
                    detail: scope == null || scope.attachments == 0
                        ? null
                        : context.t(
                            'projects.copy.attachmentsDetail',
                            variables: {
                              'files': '${scope.attachments}',
                              'size': _megabytes(scope.attachmentBytes),
                            },
                          ),
                    value: _includeAttachments,
                    onChanged: scope != null && scope.attachments == 0
                        ? null
                        : (v) => setState(() => _includeAttachments = v),
                  ),
                  _Toggle(
                    label: context.t('projects.copy.timeSettings'),
                    value: _includeTimeSettings,
                    onChanged: (v) => setState(() => _includeTimeSettings = v),
                  ),
                  _Toggle(
                    label: context.t('projects.copy.board'),
                    value: _includeBoard,
                    onChanged: (v) => setState(() => _includeBoard = v),
                  ),
                ],
                const SizedBox(height: 14),
                _scopeLine(scope),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t(
            _isInstantiate ? 'projects.copy.create' : 'projects.copy.confirm',
          ),
          confirmIcon: LucideIcons.check,
          busy: _saving,
          onConfirm: _valid ? _submit : null,
        ),
      ],
    );
  }

  Widget _dateRow() {
    final date = _eventDate;
    return InkWell(
      onTap: _pickEventDate,
      borderRadius: BorderRadius.circular(AppTheme.radiusControl),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          border: Border.all(color: AppColors.hairline2),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.calendar, size: 15, color: AppColors.inkSoft),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                date == null
                    ? context.t('projects.copy.noEventDate')
                    : MaterialLocalizations.of(context).formatMediumDate(date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: date == null ? AppColors.inkFaint : AppColors.ink,
                ),
              ),
            ),
            if (date != null)
              GestureDetector(
                onTap: () => setState(() => _eventDate = null),
                child: Icon(
                  LucideIcons.x,
                  size: 15,
                  color: AppColors.inkFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// What is about to be copied, in the server's numbers.
  Widget _scopeLine(ProjectCopyScope? scope) {
    if (_loadingScope) {
      return Row(
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 9),
          Text(
            context.t('projects.copy.counting'),
            style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
          ),
        ],
      );
    }
    if (scope == null) return const SizedBox.shrink();
    final tooBig = !scope.withinLimit;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(
          color: tooBig ? AppColors.danger : AppColors.hairline2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            tooBig ? LucideIcons.triangleAlert : LucideIcons.listChecks,
            size: 15,
            color: tooBig ? AppColors.danger : AppColors.inkSoft,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              tooBig
                  ? context.t(
                      'projects.copy.tooLarge',
                      variables: {'count': '${scope.issues}'},
                    )
                  : context.t(
                      'projects.copy.scope',
                      variables: {
                        'issues': '${scope.issues}',
                        'subtasks': '${scope.subtasks}',
                      },
                    ),
              style: TextStyle(
                fontSize: 12.5,
                color: tooBig ? AppColors.danger : AppColors.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _megabytes(int bytes) =>
      (bytes / (1024 * 1024)).toStringAsFixed(bytes > 10 * 1024 * 1024 ? 0 : 1);
}

/// One "take this too" row: what it is, optionally what it weighs, and the
/// app's single toggle. A null [onChanged] greys it out — there is nothing of
/// this kind to take.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppColors.ink : AppColors.inkFaint,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          HiveSwitch(
            value: enabled && value,
            onChanged: onChanged ?? (_) {},
          ),
        ],
      ),
    );
  }
}
