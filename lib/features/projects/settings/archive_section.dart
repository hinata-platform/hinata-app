import 'package:flutter/material.dart';

import '../../../core/i18n/i18n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/hive_widgets.dart';
import 'settings_common.dart';
import '../../../core/widgets/folded_hint.dart';

/// Archive card: a switch to archive / restore the project.
class ArchiveSection extends StatelessWidget {
  const ArchiveSection({
    super.key,
    required this.archived,
    required this.onChanged,
  });

  final bool archived;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.t('projectSettings.archive'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  archived
                      ? context.t('projectSettings.projectArchived')
                      : context.t('projectSettings.projectActive'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                FoldedHint(
                  context.t('projectSettings.archiveNote'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          HiveSwitch(value: archived, onChanged: onChanged),
        ],
      ),
    );
  }
}
