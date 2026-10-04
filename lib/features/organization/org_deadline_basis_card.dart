import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n/i18n.dart';
import '../../core/models/work_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_switch_chip.dart';
import '../admin/admin_form_helpers.dart';
import '../projects/deadline_basis_field.dart' show deadlineBasisLabelKey;
import '../../core/theme/app_type.dart';

/// Organisation → Fristen: what new relative deadlines count in, for every
/// project of the organisation that does not name a basis of its own.
///
/// [value] is the organisation's own choice, or null while it follows the
/// platform's default. The switch shows what is in force either way, and the
/// line under it says where that comes from. Choosing a chip sets the
/// organisation's own basis; "use the platform's default" hands it back.
///
/// Only on screen while project templates are on: the server refuses a basis
/// while they are off, so the page neither shows nor sends one then.
class OrgDeadlineBasisCard extends StatelessWidget {
  const OrgDeadlineBasisCard({
    super.key,
    required this.value,
    required this.platformDefault,
    required this.onChanged,
  });

  /// The organisation's own basis, or null.
  final RelativeDateBasis? value;

  /// What the platform answers while the organisation names nothing. Null when
  /// it is not known from here: the server only reports what is in force, and
  /// while the organisation names a basis that is its own.
  final RelativeDateBasis? platformDefault;

  /// A basis to set, or null to follow the platform again.
  final ValueChanged<RelativeDateBasis?> onChanged;

  @override
  Widget build(BuildContext context) {
    final follows = value == null;
    final inForce = value ?? platformDefault ?? RelativeDateBasis.calendar;
    // Nothing is lit while the organisation follows a platform default this
    // screen cannot name: a lit chip would claim an answer it does not have.
    final known = !follows || platformDefault != null;
    final hintStyle = TextStyle(
      fontSize: AppType.caption,
      height: 1.4,
      color: AppColors.inkFaint,
    );
    return AdminSectionCard(
      icon: LucideIcons.calendarClock,
      title: context.t('org.deadlines.title'),
      subtitle: context.t('org.deadlines.hint'),
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
                active: known && inForce == RelativeDateBasis.calendar,
              ),
              const SizedBox(width: 2),
              _chip(
                context,
                RelativeDateBasis.working,
                LucideIcons.briefcase,
                active: known && inForce == RelativeDateBasis.working,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          follows
              ? platformDefault == null
                    ? context.t('org.deadlines.followsPlatformUnknown')
                    : context.t(
                        'org.deadlines.followsPlatform',
                        variables: {
                          'basis': context.t(deadlineBasisLabelKey(inForce)),
                        },
                      )
              : context.t(
                  'org.deadlines.ownChoice',
                  variables: {
                    'basis': context.t(deadlineBasisLabelKey(inForce)),
                  },
                ),
          style: hintStyle,
        ),
        Text(context.t('org.deadlines.existingStay'), style: hintStyle),
        if (!follows)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('orgDeadlineUsePlatform'),
              onPressed: () => onChanged(null),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(LucideIcons.undo2, size: 14),
              label: Text(context.t('org.deadlines.usePlatform')),
            ),
          ),
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    RelativeDateBasis basis,
    IconData icon, {
    required bool active,
  }) => Semantics(
    selected: active,
    child: GlassSwitchChip(
      label: context.t(deadlineBasisLabelKey(basis)),
      icon: icon,
      active: active,
      // The chip in force for the organisation's own choice is where it
      // already is. While it follows the platform, either chip makes the
      // choice its own — the one lit included.
      onTap: active && value != null ? null : () => onChanged(basis),
    ),
  );
}
