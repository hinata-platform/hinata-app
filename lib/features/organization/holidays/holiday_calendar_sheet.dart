import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/availability_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hive_widgets.dart' show HiveSwitch;
import '../../../core/widgets/holiday_region_picker.dart';
import '../../account/account_widgets.dart';
import '../../sprint/modals/glass_modal.dart';
import 'org_holidays_cubit.dart';
import '../../../core/widgets/folded_hint.dart';
import '../../../core/theme/app_type.dart';

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

/// Where a calendar's days come from.
enum _Source { rules, feed, byHand }

class _CalendarFormState extends State<_CalendarForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _region = TextEditingController(
    text: widget.existing?.region ?? '',
  );
  final _feed = TextEditingController();
  late bool _default = widget.existing?.defaultCalendar ?? false;

  /// A new calendar follows a region: the one choice that never needs looking
  /// after again.
  late _Source _source = switch (widget.existing) {
    null => _Source.rules,
    final existing when existing.hasRules => _Source.rules,
    final existing when existing.hasFeed == true => _Source.feed,
    _ => _Source.byHand,
  };
  late String? _rules = widget.existing?.rules;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _region.dispose();
    _feed.dispose();
    super.dispose();
  }

  /// The message that stops a save, or null when the form is complete.
  String? _missing() {
    if (_name.text.trim().isEmpty) return 'availability.admin.nameRequired';
    if (_source == _Source.rules && _rules == null) {
      return 'availability.admin.rulesRequired';
    }
    if (_source == _Source.feed &&
        _feed.text.trim().isEmpty &&
        widget.existing?.hasFeed != true) {
      return 'availability.admin.feedRequired';
    }
    return null;
  }

  Future<void> _save() async {
    final missing = _missing();
    if (missing != null) {
      showGlassErrorToast(context, context.t(missing));
      return;
    }
    setState(() => _saving = true);
    try {
      final holidays = context.read<OrgHolidaysCubit>();
      final existing = widget.existing;
      final feed = _feed.text.trim();
      // A region names the place itself; the free text is for the other two.
      final region = _source == _Source.rules ? '' : _region.text.trim();
      if (existing == null) {
        await holidays.createCalendar(
          name: _name.text.trim(),
          region: region,
          icsUrl: _source == _Source.feed ? feed : null,
          rules: _source == _Source.rules ? _rules : null,
          defaultCalendar: _default,
        );
      } else {
        await holidays.updateCalendar(
          existing.id,
          name: _name.text.trim(),
          region: region,
          // Empty in feed mode: the stored address stays as it is. Switching
          // to another source drops the address, and the rules the same way.
          icsUrl: switch (_source) {
            _Source.feed => feed.isEmpty ? null : feed,
            _ => existing.hasFeed == true ? '' : null,
          },
          rules: switch (_source) {
            _Source.rules => _rules == existing.rules ? null : _rules,
            _ => existing.hasRules ? '' : null,
          },
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
                  fontSize: AppType.caption,
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
        // The kit's shape: a short window scrolls the fields, never the
        // header or the buttons.
        Flexible(
          child: SingleChildScrollView(
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
                GlassField(
                  label: context.t('availability.admin.source'),
                  child: GlassSegmented(
                    labels: [
                      context.t('availability.admin.sourceRules'),
                      context.t('availability.admin.sourceFeed'),
                      context.t('availability.admin.sourceByHand'),
                    ],
                    selected: _source.index,
                    onChanged: (index) =>
                        setState(() => _source = _Source.values[index]),
                  ),
                ),
                const SizedBox(height: 12),
                switch (_source) {
                  _Source.rules => HolidayRegionField(
                    label: context.t('availability.admin.rules'),
                    helper: context.t('availability.admin.rulesHint'),
                    value: _rules,
                    onChanged: (code) => setState(() => _rules = code),
                  ),
                  _Source.feed => TextField(
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
                  _Source.byHand => Text(
                    context.t('availability.admin.byHandHint'),
                    style: TextStyle(
                      fontSize: AppType.caption,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                },
                if (_source != _Source.rules) ...[
                  const SizedBox(height: 6),
                  TextField(
                    controller: _region,
                    maxLength: HolidayCalendar.regionMax,
                    decoration: _decoration(
                      context.t('availability.admin.region'),
                    ),
                  ),
                ],
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
