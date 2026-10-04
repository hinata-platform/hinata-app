import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/blocs/app_config_bloc.dart';
import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../../core/theme/app_type.dart';

/// The organisation's deadline basis while project templates are on, and null
/// while they are off.
///
/// Null means "do not offer the choice and do not send it": the server refuses
/// a deadline basis with 400 while the module is off, so a form that sent one
/// anyway would fail over a field nobody could see.
///
/// Read once, where a form is opened, rather than watched: the forms are short
/// lived, and the nullable lookup keeps them usable in a host that provides no
/// [AppConfigBloc] at all (a widget test of the copy sheet, say).
RelativeDateBasis? offeredDeadlineDefault(BuildContext context) {
  final meta = context.read<AppConfigBloc?>()?.state.meta;
  if (meta == null || !meta.projectTemplates) return null;
  return meta.defaultDeadlineBasis;
}

/// The i18n key naming [basis], the way the switch names it.
String deadlineBasisLabelKey(RelativeDateBasis basis) => switch (basis) {
  RelativeDateBasis.calendar => 'projects.deadlineBasis.calendar',
  RelativeDateBasis.working => 'projects.deadlineBasis.working',
};

/// "Deadlines count in: calendar days | working days", for a project.
///
/// What a project's new relative deadlines start with; the deadline editor
/// preselects it, and an issue can still say otherwise. Existing deadlines do
/// not move when it changes, and the line under the switch says so, because
/// "working days" next to a project full of dates reads like a promise to
/// recount them.
///
/// The switcher is the inline one ([GlassSwitchBar] with `inline: true`): every
/// place this stands is already a sheet or a card, and a lens inside those
/// refracts a refraction. Big opaque segmented blocks were tried for this kind
/// of question and rejected as far too heavy for it.
///
/// Brings no caption of its own; a modal wraps it in its `GlassField`, the
/// settings card in its `FieldLabel`.
class DeadlineBasisField extends StatelessWidget {
  const DeadlineBasisField({
    super.key,
    required this.value,
    required this.organisationDefault,
    required this.onChanged,
    this.followsOrganisation,
    this.onFollowOrganisation,
  });

  /// The basis on screen: the project's own, or the organisation's.
  final RelativeDateBasis value;

  /// The organisation's default.
  final RelativeDateBasis organisationDefault;

  final ValueChanged<RelativeDateBasis> onChanged;

  /// Settings only: whether the project follows the organisation rather than
  /// naming a basis of its own. Null where that question does not arise — a
  /// project that does not exist yet.
  final bool? followsOrganisation;

  /// Settings only: hands the project back to the organisation's default.
  /// Offered while the project names a basis of its own.
  final VoidCallback? onFollowOrganisation;

  @override
  Widget build(BuildContext context) {
    final orgLabel = context.t(deadlineBasisLabelKey(organisationDefault));
    final hintStyle = TextStyle(
      fontSize: AppType.caption,
      height: 1.4,
      color: AppColors.inkFaint,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: GlassSwitchBar(
            inline: true,
            maxWidth: 340,
            chips: [
              _chip(
                context,
                RelativeDateBasis.calendar,
                LucideIcons.calendarDays,
              ),
              const SizedBox(width: 2),
              _chip(context, RelativeDateBasis.working, LucideIcons.briefcase),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.t(
            followsOrganisation == true
                ? 'projects.deadlineBasis.followsOrg'
                : 'projects.deadlineBasis.orgDefault',
            variables: {'basis': orgLabel},
          ),
          style: hintStyle,
        ),
        Text(context.t('projects.deadlineBasis.hint'), style: hintStyle),
        if (followsOrganisation == false && onFollowOrganisation != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onFollowOrganisation,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(LucideIcons.undo2, size: 14),
              label: Text(context.t('projects.deadlineBasis.useOrgDefault')),
            ),
          ),
      ],
    );
  }

  Widget _chip(BuildContext context, RelativeDateBasis basis, IconData icon) {
    final active = value == basis;
    return Semantics(
      selected: active,
      child: GlassSwitchChip(
        label: context.t(deadlineBasisLabelKey(basis)),
        icon: icon,
        active: active,
        onTap: active ? null : () => onChanged(basis),
      ),
    );
  }
}
