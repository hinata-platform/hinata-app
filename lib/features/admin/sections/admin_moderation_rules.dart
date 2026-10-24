import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_client.dart';
import '../../../core/i18n/i18n.dart';
import '../../../core/models/moderation_models.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_type.dart';
import '../../../core/widgets/glass_switch_chip.dart';
import '../../moderation/house_rules_sheet.dart' show moderationDay;
import '../../sprint/modals/glass_modal.dart';
import '../admin_form_helpers.dart';

/// Which version of the house rules holds and since when (HIN-175). Null
/// while it is read, and on a server that keeps none.
class HouseRulesVersionsCubit extends Cubit<HouseRulesVersions?> {
  HouseRulesVersionsCubit(this._admin) : super(null);

  final AdminRepository _admin;

  Future<void> load() async {
    try {
      emit(await _admin.houseRulesVersions());
    } catch (_) {
      emit(null);
    }
  }

  /// Makes everybody accept anew; the failure passes through for the card to
  /// report.
  Future<void> requireReacceptance() async =>
      emit(await _admin.requireRulesReacceptance());
}

/// The house rules card: which rules, in the draft the shell saves under
/// `moderation.rules`, and the one action that is no settings save, asking
/// everybody to accept them anew.
class HouseRulesCard extends StatefulWidget {
  const HouseRulesCard({super.key, required this.moderation});

  /// The `moderation` block of the settings draft.
  final Map<String, dynamic> moderation;

  @override
  State<HouseRulesCard> createState() => _HouseRulesCardState();
}

class _HouseRulesCardState extends State<HouseRulesCard> {
  static const _textMax = 20000;

  bool _asking = false;

  Map<String, dynamic> get _rules =>
      (widget.moderation['rules'] ??= <String, dynamic>{})
          as Map<String, dynamic>;

  HouseRulesMode get _mode => HouseRulesMode.of(_rules['mode']);

  void _choose(HouseRulesMode mode) =>
      setState(() => _rules['mode'] = mode.wire);

  /// Blank is no value, as everywhere in these settings.
  void _put(String key, String value) {
    final text = value.trim();
    _rules[key] = text.isEmpty ? null : text;
  }

  Future<void> _askEverybody(BuildContext context) async {
    final versions = context.read<HouseRulesVersionsCubit>();
    final confirmed = await showGlassConfirm(
      context,
      icon: LucideIcons.refreshCw,
      title: context.t('admin.rules.reacceptTitle'),
      message: context.t('admin.rules.reacceptBody'),
      confirmLabel: context.t('admin.rules.reacceptConfirm'),
      confirmIcon: LucideIcons.refreshCw,
    );
    if (confirmed != true || !context.mounted) return;
    setState(() => _asking = true);
    try {
      await versions.requireReacceptance();
      if (context.mounted) {
        showGlassToast(
          context,
          context.t(
            'admin.rules.reacceptDone',
            variables: {'version': '${versions.state?.version ?? ''}'},
          ),
          kind: GlassToastKind.success,
        );
      }
    } on ApiFailure catch (failure) {
      if (context.mounted) {
        showGlassErrorToast(context, context.t(failure.message));
      }
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _mode;
    final versions = context.watch<HouseRulesVersionsCubit>().state;
    final version = versions?.version;
    final since = versions?.since;
    return AdminSectionCard(
      icon: LucideIcons.bookOpenCheck,
      title: context.t('admin.rules.title'),
      subtitle: version == null || since == null
          ? context.t('admin.rules.hint')
          : '${context.t('admin.rules.hint')} ${context.t('admin.rules.versionSince', variables: {'version': '$version', 'date': moderationDay(context, since)})}',
      children: [
        // Start-aligned: in the card's stretching column the bar would take
        // the whole width and trail an empty track after its last choice.
        LayoutBuilder(
          builder: (context, constraints) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: GlassSwitchBar(
              inline: true,
              maxWidth: constraints.maxWidth,
              chips: [
                for (final option in HouseRulesMode.values)
                  GlassSwitchChip(
                    label: context.t('admin.rules.mode.${option.name}'),
                    active: option == mode,
                    onTap: () => _choose(option),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        switch (mode) {
          HouseRulesMode.builtIn => _Line(
            icon: LucideIcons.bookOpenCheck,
            text: context.t('admin.rules.builtInHint'),
          ),
          HouseRulesMode.text => TextFormField(
            key: const ValueKey('rulesText'),
            initialValue: (_rules['text'] as String?) ?? '',
            minLines: 6,
            maxLines: 16,
            maxLength: _textMax,
            style: TextStyle(fontSize: AppType.body, color: AppColors.ink),
            decoration: adminInputDecoration(
              context,
              label: context.t('admin.rules.text'),
              helper: context.t('admin.rules.textHint'),
            ),
            onChanged: (value) => _put('text', value),
          ),
          HouseRulesMode.url => AdminField(
            key: const ValueKey('rulesUrl'),
            label: context.t('admin.rules.url'),
            hint: 'https://',
            initialValue: (_rules['url'] as String?) ?? '',
            keyboardType: TextInputType.url,
            onChanged: (value) => _put('url', value),
          ),
        },
        const SizedBox(height: 8),
        _Line(
          icon: LucideIcons.info,
          text: context.t('admin.rules.versionHint'),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _asking || version == null
                ? null
                : () => unawaited(_askEverybody(context)),
            icon: const Icon(LucideIcons.refreshCw, size: 16),
            label: Text(context.t('admin.rules.reaccept')),
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Icon(icon, size: 16, color: AppColors.inkSoft),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppType.label,
            height: 1.4,
            color: AppColors.inkSoft,
          ),
        ),
      ),
    ],
  );
}
