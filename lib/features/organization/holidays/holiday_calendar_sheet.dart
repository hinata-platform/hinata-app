import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/availability_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../../account/account_widgets.dart';
import '../../sprint/modals/glass_modal.dart';
import 'org_holidays_cubit.dart';
import '../../../core/widgets/folded_hint.dart';

/// Opens the form for a new holiday calendar, or for [existing]. Resolves to
/// true once it was saved.
Future<bool?> showHolidayCalendarSheet(
  BuildContext context, {
  HolidayCalendar? existing,
}) {
  // The form opens as its own route, so the page's requests are handed in.
  final holidays = context.read<OrgHolidaysCubit>();
  return showGlassModal<bool>(
    context,
    adaptive: true,
    width: 460,
    builder: (sheetContext) => BlocProvider.value(
      value: holidays,
      child: _CalendarForm(existing: existing),
    ),
  );
}

class _CalendarForm extends StatefulWidget {
  const _CalendarForm({this.existing});

  final HolidayCalendar? existing;

  @override
  State<_CalendarForm> createState() => _CalendarFormState();
}

class _CalendarFormState extends State<_CalendarForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _region = TextEditingController(
    text: widget.existing?.region ?? '',
  );
  final _feed = TextEditingController();
  late bool _default = widget.existing?.defaultCalendar ?? false;
  bool _removeFeed = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _region.dispose();
    _feed.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showGlassErrorToast(
        context,
        context.t('availability.admin.nameRequired'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final holidays = context.read<OrgHolidaysCubit>();
      final existing = widget.existing;
      final feed = _feed.text.trim();
      if (existing == null) {
        await holidays.createCalendar(
          name: _name.text.trim(),
          region: _region.text.trim(),
          icsUrl: feed.isEmpty ? null : feed,
          defaultCalendar: _default,
        );
      } else {
        await holidays.updateCalendar(
          existing.id,
          name: _name.text.trim(),
          region: _region.text.trim(),
          // Empty and not removed: the stored address stays as it is.
          icsUrl: _removeFeed ? '' : (feed.isEmpty ? null : feed),
          defaultCalendar: _default,
        );
      }
      if (!mounted) return;
      showGlassToast(context, context.t('availability.admin.saved'));
      Navigator.of(context).pop(true);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _saving = false);
      showGlassErrorToast(context, context.t(failure.message));
    }
  }

  InputDecoration _decoration(String label, {String? helper}) =>
      InputDecoration(
        labelText: label,
        helper: helper == null
            ? null
            : FoldedHint(
                helper,
                title: label,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.inkFaint,
                ),
              ),
      );

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GlassModalHeader(
          icon: LucideIcons.calendarHeart,
          title: context.t(
            existing == null
                ? 'availability.admin.newCalendar'
                : 'availability.admin.editCalendar',
          ),
          subtitle: context.t('availability.admin.cardHint'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: existing == null,
                maxLength: HolidayCalendar.nameMax,
                decoration: _decoration(context.t('availability.admin.name')),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _region,
                maxLength: HolidayCalendar.regionMax,
                decoration: _decoration(context.t('availability.admin.region')),
              ),
              const SizedBox(height: 6),
              if (!_removeFeed)
                TextField(
                  controller: _feed,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: _decoration(
                    context.t('availability.admin.feedUrl'),
                    helper: existing?.feedHost == null
                        ? context.t('availability.admin.feedUrlHint')
                        : context.t(
                            'availability.admin.feedUrlKeep',
                            variables: {'host': existing!.feedHost!},
                          ),
                  ),
                ),
              if (existing?.hasFeed == true)
                SettingRow(
                  label: context.t('availability.admin.removeFeed'),
                  trailing: HiveSwitch(
                    value: _removeFeed,
                    onChanged: (value) => setState(() => _removeFeed = value),
                  ),
                ),
              SettingRow(
                label: context.t('availability.admin.default'),
                description: context.t('availability.admin.defaultHint'),
                trailing: HiveSwitch(
                  value: _default,
                  onChanged: (value) => setState(() => _default = value),
                ),
              ),
            ],
          ),
        ),
        GlassModalFooter(
          confirmLabel: context.t('common.save'),
          busy: _saving,
          onConfirm: _saving ? null : _save,
        ),
      ],
    );
  }
}
