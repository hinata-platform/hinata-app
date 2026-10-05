import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/api_client.dart';
import '../../core/blocs/time_policy_cubit.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/time_models.dart';
import '../../core/repositories/domain_providers.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_type.dart';
import '../../core/widgets/field_button.dart';
import '../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../sprint/modals/glass_modal.dart';
import '../time/placement_picker.dart';
import '../time/tag_picker.dart';
import 'account_widgets.dart';

/// Adds a calendar subscription, or edits [subscription] (HIN-94).
///
/// The form asks, in this order, what the job needs every time — a name and
/// the address — then the colour, which has a sensible default. The takeover
/// rule and the explanation of where an address is found are one step away,
/// each behind its own switch or link, so a first-time reader meets two fields.
///
/// [onSave] is the write; the dialog stays open on a refusal and shows it next
/// to the fields, and resolves to what was saved.
Future<CalendarSubscription?> showCalendarSubscriptionDialog(
  BuildContext context, {
  CalendarSubscription? subscription,
  required Future<CalendarSubscription> Function(CalendarSubscriptionDraft)
  onSave,
}) {
  // The pickers read repositories, and the modal rides the root navigator,
  // outside the app's provider scope.
  final repositories = domainRepositoryProviders(context);
  final policy = context.read<TimePolicyCubit>();
  return showGlassModal<CalendarSubscription>(
    context,
    adaptive: true,
    width: 480,
    builder: (_) => MultiRepositoryProvider(
      providers: repositories,
      child: BlocProvider<TimePolicyCubit>.value(
        value: policy,
        child: _SubscriptionForm(subscription: subscription, onSave: onSave),
      ),
    ),
  );
}

class _SubscriptionForm extends StatefulWidget {
  const _SubscriptionForm({required this.subscription, required this.onSave});

  final CalendarSubscription? subscription;
  final Future<CalendarSubscription> Function(CalendarSubscriptionDraft) onSave;

  @override
  State<_SubscriptionForm> createState() => _SubscriptionFormState();
}

class _SubscriptionFormState extends State<_SubscriptionForm> {
  late final _name = TextEditingController(
    text: widget.subscription?.name ?? '',
  );
  final _url = TextEditingController();
  final _projectKey = GlobalKey();
  final _tagsKey = GlobalKey();

  late String _color =
      widget.subscription?.color.toUpperCase() ?? calendarColorChoices.first;
  late bool _ruleOn = widget.subscription?.rule.enabled ?? false;
  late TimePlacement _project = TimePlacement(
    projectId: widget.subscription?.rule.projectId,
  );
  late List<String> _tags = List.of(widget.subscription?.rule.tags ?? []);
  bool _showHelp = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.subscription != null;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  /// A new subscription needs both; an edit may leave the address as stored.
  bool get _complete =>
      _name.text.trim().isNotEmpty && (_isEdit || _url.text.trim().isNotEmpty);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(
        CalendarSubscriptionDraft(
          name: _name.text.trim(),
          color: _color,
          url: _url.text.trim().isEmpty ? null : _url.text.trim(),
          rule: CalendarTakeoverRule(
            enabled: _ruleOn,
            projectId: _ruleOn ? _project.projectId : null,
            tags: _ruleOn ? _tags : const [],
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop(saved);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _pickProject() async {
    final picked = await showTimePlacementPicker(
      context,
      anchorRect: anchorRectOf(_projectKey),
      current: _project,
      projectsOnly: true,
    );
    if (picked == null || !mounted) return;
    setState(() => _project = picked);
  }

  Future<void> _pickTags() async {
    final picked = await showTimeTagPicker(
      context,
      anchorRect: anchorRectOf(_tagsKey),
      selected: _tags,
      canCreate: !context.read<TimePolicyCubit>().state.limitTagAccess,
    );
    if (picked == null || !mounted) return;
    setState(() => _tags = picked);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      GlassModalHeader(
        icon: LucideIcons.calendarSync,
        title: context.t(
          _isEdit
              ? 'calendarSubscriptions.form.editTitle'
              : 'calendarSubscriptions.form.addTitle',
        ),
        subtitle: context.t('calendarSubscriptions.form.subtitle'),
      ),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                // Wide only: on a phone the keyboard would rise at once and
                // cover the half of the form that says what the address is.
                autofocus: !_isEdit && !context.isCompact,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.t('calendarSubscriptions.form.name'),
                  hintText: context.t('calendarSubscriptions.form.nameHint'),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 2048,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.t('calendarSubscriptions.form.url'),
                  hintText: _isEdit
                      ? context.t('calendarSubscriptions.form.urlKeep')
                      : 'https://… .ics',
                  helperText: context.t('calendarSubscriptions.form.urlHint'),
                  helperMaxLines: 3,
                  counterText: '',
                  prefixIcon: const Icon(LucideIcons.lock, size: 16),
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showHelp = !_showHelp),
                  icon: Icon(
                    _showHelp ? LucideIcons.chevronUp : LucideIcons.circleHelp,
                    size: 16,
                  ),
                  label: Text(context.t('calendarSubscriptions.help.toggle')),
                ),
              ),
              if (_showHelp) const _WhereToFind(),
              const SizedBox(height: 10),
              _ColorChoice(
                value: _color,
                onChanged: (color) => setState(() => _color = color),
              ),
              const SizedBox(height: 6),
              SettingRow(
                label: context.t('calendarSubscriptions.form.rule'),
                description: context.t('calendarSubscriptions.form.ruleHint'),
                trailing: HiveSwitch(
                  value: _ruleOn,
                  onChanged: (on) => setState(() => _ruleOn = on),
                ),
              ),
              if (_ruleOn) ...[
                const SizedBox(height: 6),
                KeyedSubtree(
                  key: _projectKey,
                  child: FieldButton(
                    icon: LucideIcons.folder,
                    label: context.t('calendarSubscriptions.form.ruleProject'),
                    value: _project.isUnfiled
                        ? context.t('time.placement.none')
                        : _project.label ??
                              context.t('time.placement.assigned'),
                    empty: _project.isUnfiled,
                    onTap: _pickProject,
                  ),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _tagsKey,
                  child: FieldButton(
                    icon: LucideIcons.tag,
                    label: context.t('time.entry.tags'),
                    value: _tags.isEmpty
                        ? context.t('time.tags.none')
                        : _tags.join(' · '),
                    empty: _tags.isEmpty,
                    onTap: _pickTags,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    context.t(_error!),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      color: AppColors.dangerInk,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      GlassModalFooter(
        confirmLabel: context.t(
          _isEdit ? 'common.save' : 'calendarSubscriptions.form.subscribe',
        ),
        busy: _saving,
        onConfirm: _saving || !_complete ? null : _save,
      ),
    ],
  );
}

/// Where Google, Outlook and Apple hand out a calendar's private address.
class _WhereToFind extends StatelessWidget {
  const _WhereToFind();

  @override
  Widget build(BuildContext context) {
    Widget step(String provider, String key) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$provider  ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: context.t(key)),
          ],
        ),
        style: TextStyle(
          fontSize: AppType.caption,
          height: 1.4,
          color: AppColors.inkSoft,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          step('Google', 'calendarSubscriptions.help.google'),
          step('Outlook', 'calendarSubscriptions.help.outlook'),
          step('Apple', 'calendarSubscriptions.help.apple'),
          Text(
            context.t('calendarSubscriptions.help.privacy'),
            style: TextStyle(
              fontSize: AppType.caption,
              height: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

/// The six colours a calendar can take, as a row of round swatches. Six is a
/// handful, so they sit in the form rather than behind a picker; each is a
/// 48-point target with its name for a screen reader.
class _ColorChoice extends StatelessWidget {
  const _ColorChoice({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _names = [
    'calendarSubscriptions.color.blue',
    'calendarSubscriptions.color.teal',
    'calendarSubscriptions.color.orange',
    'calendarSubscriptions.color.plum',
    'calendarSubscriptions.color.olive',
    'calendarSubscriptions.color.red',
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        context.t('calendarSubscriptions.form.color'),
        style: TextStyle(fontSize: AppType.caption, color: AppColors.inkSoft),
      ),
      Wrap(
        children: [
          for (var i = 0; i < calendarColorChoices.length; i++)
            Semantics(
              button: true,
              selected: calendarColorChoices[i] == value,
              label: context.t(_names[i]),
              child: InkResponse(
                onTap: () => onChanged(calendarColorChoices[i]),
                radius: 24,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: calendarColor(calendarColorChoices[i]),
                        shape: BoxShape.circle,
                        border: calendarColorChoices[i] == value
                            ? Border.all(color: AppColors.ink, width: 2.5)
                            : null,
                      ),
                      child: calendarColorChoices[i] == value
                          ? const Icon(
                              LucideIcons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
