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
import 'deadline_basis_field.dart';
import 'project_copy_cubit.dart';
import 'project_key.dart';
import '../../core/theme/app_type.dart';

/// Which of the two ways in somebody took.
enum ProjectCopyMode {
  /// "Copy …" — every switch is offered, the date is optional.
  copy,

  /// "Create a project from this" — the scope is decided and the date is the
  /// point of the exercise.
  instantiate,

  /// "Make a template from …" — the copy is marked as a template, so the
  /// project it was made from keeps running. The other way round, marking a
  /// project you already have, is the switch in its settings; this is the way in
  /// from the Templates tab, for somebody who wants to keep both.
  template,
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
  final deadlineDefault = offeredDeadlineDefault(context);
  return showGlassModal<ProjectCopyResult>(
    context,
    width: 560,
    // The sheet is a route of its own and inherits nothing from the page.
    builder: (modalContext) => BlocProvider(
      create: (_) => ProjectCopyCubit(projects),
      child: _ProjectCopyBody(
        source: source,
        mode: mode,
        deadlineDefault: deadlineDefault,
      ),
    ),
  );
}

class _ProjectCopyBody extends StatefulWidget {
  const _ProjectCopyBody({
    required this.source,
    required this.mode,
    this.deadlineDefault,
  });

  final Project source;
  final ProjectCopyMode mode;

  /// The organisation's deadline basis while project templates are on; null
  /// hides the switch and keeps the field out of the request.
  final RelativeDateBasis? deadlineDefault;

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

  /// The basis picked for the new project's deadlines, null until somebody
  /// picks one, and then nothing is sent: the copy keeps the source's own
  /// setting, including "follow the organisation".
  RelativeDateBasis? _deadlineBasis;

  ProjectCopyScope? _scope;
  bool _loadingScope = true;
  bool _saving = false;
  String? _error;

  bool get _isInstantiate => widget.mode == ProjectCopyMode.instantiate;
  bool get _isTemplate => widget.mode == ProjectCopyMode.template;

  @override
  void initState() {
    super.initState();
    _eventDate = _isInstantiate ? null : widget.source.eventDate;
    _loadScope();
  }

  /// Whether the name field has had its suggestion. Here rather than in
  /// [initState] because the template's suggestion is a translated string, and
  /// a translation is an inherited widget — reading one before the first
  /// dependency pass is an assertion failure.
  bool _named = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_named) return;
    _named = true;
    _name.text = _isInstantiate
        ? ''
        : _isTemplate
        ? context.t(
            'projects.copy.templateName',
            variables: {'name': widget.source.name},
          )
        : '${widget.source.name} 2';
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _loadScope() async {
    try {
      final scope = await context.read<ProjectCopyCubit>().scopeOfCopy(
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
      final copies = context.read<ProjectCopyCubit>();
      final result = _isInstantiate
          ? await copies.instantiate(
              widget.source.id,
              name: _name.text.trim(),
              key: _key.text.trim(),
              eventDate: _eventDate,
              deadlineBasis: _deadlineBasisToSend,
            )
          : await copies.copy(
              widget.source.id,
              name: _name.text.trim(),
              key: _key.text.trim(),
              eventDate: _eventDate,
              includeMembers: _includeMembers,
              includeAttachments: _includeAttachments,
              includeTimeSettings: _includeTimeSettings,
              includeBoard: _includeBoard,
              asTemplate: _isTemplate,
              deadlineBasis: _deadlineBasisToSend,
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

  RelativeDateBasis? get _deadlineBasisToSend =>
      widget.deadlineDefault == null ? null : _deadlineBasis;

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
          icon: _isInstantiate
              ? LucideIcons.sparkles
              : _isTemplate
              ? LucideIcons.bookmarkPlus
              : LucideIcons.copy,
          title: context.t(
            _isInstantiate
                ? 'projects.copy.fromTemplate'
                : _isTemplate
                ? 'projects.copy.makeTemplate'
                : 'projects.copy.title',
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
                    decoration: glassInputDecoration(hint: scope?.suggestedKey),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 12),
                GlassField(
                  label: context.t('projects.copy.eventDate'),
                  child: _dateRow(),
                ),
                if (widget.deadlineDefault != null) ...[
                  const SizedBox(height: 12),
                  GlassField(
                    label: context.t('projects.deadlineBasis.label'),
                    child: DeadlineBasisField(
                      value:
                          _deadlineBasis ??
                          widget.source.effectiveDeadlineBasis(
                            widget.deadlineDefault!,
                          ),
                      organisationDefault: widget.deadlineDefault!,
                      onChanged: (basis) =>
                          setState(() => _deadlineBasis = basis),
                    ),
                  ),
                ],
                if (!_isInstantiate) ...[
                  const SizedBox(height: 16),
                  Text(
                    context.t('projects.copy.include'),
                    style: const TextStyle(
                      fontSize: AppType.label,
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
                    style: TextStyle(
                      color: AppColors.dangerInk,
                      fontSize: AppType.label,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t(
            _isInstantiate
                ? 'projects.copy.create'
                : _isTemplate
                ? 'projects.copy.makeTemplateConfirm'
                : 'projects.copy.confirm',
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
    // The vertical padding sits on the row's children rather than on the box,
    // so the clear button can take the field's full height as its target
    // instead of the bare 15-point glyph.
    // Both nodes are containers: the clear button inside stays a node of its
    // own instead of merging its tap into the row's.
    return Semantics(
      container: true,
      button: true,
      label: context.t('projects.copy.eventDate'),
      child: InkWell(
        onTap: _pickEventDate,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        child: Container(
          padding: EdgeInsets.only(left: 13, right: date == null ? 13 : 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusControl),
            border: Border.all(color: AppColors.hairline2),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.calendar, size: 15, color: AppColors.inkSoft),
              const SizedBox(width: 9),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    date == null
                        ? context.t('projects.copy.noEventDate')
                        : MaterialLocalizations.of(
                            context,
                          ).formatMediumDate(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: FontWeight.w600,
                      color: date == null ? AppColors.inkFaint : AppColors.ink,
                    ),
                  ),
                ),
              ),
              if (date != null)
                Semantics(
                  container: true,
                  button: true,
                  label: context.t('common.clear'),
                  child: InkResponse(
                    onTap: () => setState(() => _eventDate = null),
                    radius: 20,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 13, 12),
                      child: Icon(
                        LucideIcons.x,
                        size: 15,
                        color: AppColors.inkFaint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
            style: TextStyle(
              fontSize: AppType.label,
              color: AppColors.inkFaint,
            ),
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
                fontSize: AppType.label,
                color: tooBig ? AppColors.dangerInk : AppColors.inkSoft,
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
                    fontSize: AppType.label,
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppColors.ink : AppColors.inkFaint,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.inkFaint,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          HiveSwitch(value: enabled && value, onChanged: onChanged ?? (_) {}),
        ],
      ),
    );
  }
}
